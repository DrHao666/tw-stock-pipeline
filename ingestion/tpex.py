"""抓取櫃買中心（上櫃）每日收盤行情，原封不動寫入 raw.tpex_otc_quotes。

用法：
    python -m ingestion.tpex 20261016
"""
import json
import logging
import sys
from datetime import date, datetime

import requests

from ingestion.common import get_connection, get_json_with_retry, run_sql_file

logger = logging.getLogger(__name__)

OTC_URL = "https://www.tpex.org.tw/www/zh-tw/afterTrading/otc"


def fetch_otc_quotes(trade_date: date, session: requests.Session | None = None) -> dict:
    """打櫃買中心取得某一天上櫃股票行情（type=EW：不含權證、牛熊證）。"""
    params = {"date": trade_date.strftime("%Y/%m/%d"), "type": "EW", "response": "json"}
    return get_json_with_retry(OTC_URL, params, session)


def count_quote_rows(payload: dict) -> int:
    """回傳行情筆數。櫃買中心休市日 stat 仍是 'ok'，只能靠筆數為 0 判斷。"""
    return sum(len(table.get("data") or []) for table in payload.get("tables", []))


def save_raw(conn, trade_date: date, payload: dict) -> None:
    """Upsert：同一天跑兩次只會留一筆，內容與抓取時間更新成最新的（冪等）。"""
    sql = """
        INSERT INTO raw.tpex_otc_quotes (trade_date, stat, payload, fetched_at)
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
    payload = fetch_otc_quotes(trade_date)
    with get_connection() as conn:
        run_sql_file(conn, "raw/002_create_raw_tpex.sql")
        save_raw(conn, trade_date, payload)

    rows = count_quote_rows(payload)
    if rows == 0:
        logger.info("%s 無行情資料（休市），已記錄", trade_date)
    else:
        logger.info("%s 寫入完成，上櫃行情 %d 筆", trade_date, rows)


def main(argv: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if len(argv) != 2:
        sys.exit("用法：python -m ingestion.tpex YYYYMMDD")
    ingest(datetime.strptime(argv[1], "%Y%m%d").date())


if __name__ == "__main__":
    main(sys.argv)
