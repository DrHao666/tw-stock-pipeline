"""抓取集保股權分散表（開放資料，最新一週、全部證券），原樣寫入 raw。

開放資料只提供最新一週，沒有歷史可回補，所以不吃日期參數；每天跑一次，
集保更新時就會多一週，同一週重抓只會覆蓋同一筆。資料日期以 CSV 內容為準。

用法：
    python -m ingestion.shareholding
"""
import csv
import io
import json
import logging
import sys
import time
from datetime import date, datetime

import requests

from ingestion.common import MAX_RETRIES, TIMEOUT_SECONDS, get_connection, run_sql_file

logger = logging.getLogger(__name__)

TDCC_OPEN_DATA_URL = "https://opendata.tdcc.com.tw/getOD.ashx"
TDCC_DATASET_ID = "1-5"
EXPECTED_FIELDS = ["資料日期", "證券代號", "持股分級", "人數", "股數", "占集保庫存數比例%"]
DDL = "raw/006_create_raw_shareholding.sql"


def fetch() -> dict:
    """下載 CSV，轉成 {fields, data}，值保留原始字串（證券代號後面的空白留給 staging 清）。

    檔案是 UTF-8 有 BOM；格式不對（被擋時常回 HTML）就重試，3 次都失敗丟例外。
    """
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = requests.get(TDCC_OPEN_DATA_URL, params={"id": TDCC_DATASET_ID}, timeout=TIMEOUT_SECONDS)
            resp.raise_for_status()
            rows = list(csv.reader(io.StringIO(resp.content.decode("utf-8-sig"))))
            fields, data = rows[0], [row for row in rows[1:] if row]
            if fields != EXPECTED_FIELDS:
                raise ValueError(f"欄位和預期不同：{fields}")
            if not data:
                raise ValueError("CSV 沒有資料列")
            return {"fields": fields, "data": data}
        except (requests.RequestException, ValueError, IndexError) as exc:
            if attempt == MAX_RETRIES:
                raise
            wait = 2 ** attempt
            logger.warning("第 %d 次下載集保開放資料失敗：%s，%d 秒後重試", attempt, exc, wait)
            time.sleep(wait)


def data_date(payload: dict) -> date:
    """整份 CSV 應該只有一個資料日期，不是的話代表格式變了，寧可失敗。"""
    dates = {row[0] for row in payload["data"]}
    if len(dates) != 1:
        raise ValueError(f"CSV 裡有 {len(dates)} 個資料日期：{sorted(dates)[:5]}")
    return datetime.strptime(dates.pop(), "%Y%m%d").date()


def save_raw(conn, week: date, payload: dict) -> None:
    """Upsert：同一週重抓只會留一筆最新的（冪等）。"""
    sql = """
        INSERT INTO raw.tdcc_shareholding (data_date, payload, fetched_at)
        VALUES (%s, %s::jsonb, now())
        ON CONFLICT (data_date) DO UPDATE
        SET payload = EXCLUDED.payload,
            fetched_at = EXCLUDED.fetched_at
    """
    with conn.cursor() as cur:
        cur.execute(sql, (week, json.dumps(payload, ensure_ascii=False)))
    conn.commit()


def ingest() -> None:
    payload = fetch()
    week = data_date(payload)
    with get_connection() as conn:
        run_sql_file(conn, DDL)
        save_raw(conn, week, payload)
    logger.info("tdcc_shareholding %s 寫入完成，%d 筆", week, len(payload["data"]))


def main(argv: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if len(argv) != 1:
        sys.exit("用法：python -m ingestion.shareholding（開放資料只有最新一週，不吃日期參數）")
    ingest()


if __name__ == "__main__":
    main(sys.argv)
