"""抓取證交所（上市）每日收盤行情 MI_INDEX，原封不動寫入 raw.twse_mi_index。

用法：
    python -m ingestion.twse 20261016
"""
import json
import logging
import os
import sys
import time
from datetime import date, datetime
from pathlib import Path

import psycopg2
import requests
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

MI_INDEX_URL = "https://www.twse.com.tw/rwd/zh/afterTrading/MI_INDEX"
DDL_PATH = Path(__file__).resolve().parent.parent / "sql" / "raw" / "001_create_raw_twse.sql"
MAX_RETRIES = 3
TIMEOUT_SECONDS = 30


def fetch_mi_index(trade_date: date, session: requests.Session | None = None) -> dict:
    """打 MI_INDEX 取得某一天全市場行情，失敗時以 exponential backoff 重試（2、4、8 秒）。

    休市日證交所仍回 200，只是 stat 不是 'OK'；這裡不把它當錯誤，交給呼叫端判斷。
    """
    session = session or requests.Session()
    params = {"date": trade_date.strftime("%Y%m%d"), "type": "ALLBUT0999", "response": "json"}

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = session.get(MI_INDEX_URL, params=params, timeout=TIMEOUT_SECONDS)
            resp.raise_for_status()
            payload = resp.json()  # 被擋時會回 HTML，這裡會丟 ValueError，一樣進入重試
            if "stat" not in payload:
                raise ValueError(f"回應缺少 stat 欄位：{str(payload)[:200]}")
            return payload
        except (requests.RequestException, ValueError) as exc:
            if attempt == MAX_RETRIES:
                raise
            wait = 2 ** attempt
            logger.warning("第 %d 次抓取 %s 失敗：%s，%d 秒後重試", attempt, trade_date, exc, wait)
            time.sleep(wait)


def find_quotes_table(payload: dict) -> dict | None:
    """用標題找「每日收盤行情」那張表；不寫死位置，因為舊年份會有空表佔位。"""
    for table in payload.get("tables", []):
        if "每日收盤行情" in (table.get("title") or ""):
            return table
    return None


def get_connection():
    """連到 warehouse DB。本機跑時從 .env 讀帳密，連 localhost 的對外 port。"""
    load_dotenv()
    return psycopg2.connect(
        host=os.getenv("WAREHOUSE_HOST", "localhost"),
        port=os.getenv("WAREHOUSE_PORT", os.getenv("POSTGRES_HOST_PORT", "5433")),
        dbname=os.getenv("WAREHOUSE_DB", "warehouse"),
        user=os.getenv("POSTGRES_USER", "postgres"),
        password=os.getenv("POSTGRES_PASSWORD"),
    )


def ensure_schema(conn) -> None:
    """建立 raw schema 與表（IF NOT EXISTS，重跑無副作用）。"""
    with conn.cursor() as cur:
        cur.execute(DDL_PATH.read_text(encoding="utf-8"))
    conn.commit()


def save_raw(conn, trade_date: date, payload: dict) -> None:
    """Upsert：同一天跑兩次只會留一筆，內容與抓取時間更新成最新的（冪等）。"""
    sql = """
        INSERT INTO raw.twse_mi_index (trade_date, stat, payload, fetched_at)
        VALUES (%s, %s, %s::jsonb, now())
        ON CONFLICT (trade_date) DO UPDATE
        SET stat = EXCLUDED.stat,
            payload = EXCLUDED.payload,
            fetched_at = EXCLUDED.fetched_at
    """
    with conn.cursor() as cur:
        cur.execute(sql, (trade_date, payload["stat"], json.dumps(payload, ensure_ascii=False)))
    conn.commit()


def ingest(trade_date: date) -> None:
    payload = fetch_mi_index(trade_date)
    with get_connection() as conn:
        ensure_schema(conn)
        save_raw(conn, trade_date, payload)

    if payload["stat"] != "OK":
        logger.info("%s 休市（stat=%s），已記錄", trade_date, payload["stat"])
        return
    table = find_quotes_table(payload)
    rows = len(table["data"]) if table else 0
    logger.info("%s 寫入完成，個股行情 %d 筆", trade_date, rows)


def main(argv: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if len(argv) != 2:
        sys.exit("用法：python -m ingestion.twse YYYYMMDD")
    ingest(datetime.strptime(argv[1], "%Y%m%d").date())


if __name__ == "__main__":
    main(sys.argv)
