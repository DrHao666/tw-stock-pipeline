"""抓取證交所（上市）每日收盤行情 MI_INDEX，原封不動寫入 raw.twse_mi_index。

用法：
    python -m ingestion.twse 20261016
"""
import json
import logging
import sys
from datetime import date, datetime

import requests

from ingestion.common import get_connection, get_json_with_retry, run_sql_file

logger = logging.getLogger(__name__)

MI_INDEX_URL = "https://www.twse.com.tw/rwd/zh/afterTrading/MI_INDEX"


def fetch_mi_index(trade_date: date, session: requests.Session | None = None) -> dict:
    """打 MI_INDEX 取得某一天全市場行情。

    休市日證交所仍回 200，只是 stat 不是 'OK'；這裡不把它當錯誤，交給呼叫端判斷。
    """
    params = {"date": trade_date.strftime("%Y%m%d"), "type": "ALLBUT0999", "response": "json"}
    return get_json_with_retry(MI_INDEX_URL, params, session)


def find_quotes_table(payload: dict) -> dict | None:
    """用標題找「每日收盤行情」那張表；不寫死位置，因為舊年份會有空表佔位。"""
    for table in payload.get("tables", []):
        if "每日收盤行情" in (table.get("title") or ""):
            return table
    return None


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
        run_sql_file(conn, "raw/001_create_raw_twse.sql")
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
