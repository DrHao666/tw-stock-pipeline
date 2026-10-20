"""抓取上市、上櫃三大法人買賣超日報，原封不動寫入 raw。

用法：
    python -m ingestion.institutional twse 20261020
    python -m ingestion.institutional tpex 20261020
"""
import json
import logging
import sys
from datetime import date, datetime

from ingestion.common import get_connection, get_json_with_retry, run_sql_file

logger = logging.getLogger(__name__)

TWSE_T86_URL = "https://www.twse.com.tw/rwd/zh/fund/T86"
TPEX_INSTI_URL = "https://www.tpex.org.tw/www/zh-tw/insti/dailyTrade"
DDL = "raw/004_create_raw_institutional.sql"


def fetch_twse(trade_date: date) -> dict:
    """證交所 T86；休市日回 stat='很抱歉，沒有符合條件的資料!'，沒有 fields/data。"""
    params = {"date": trade_date.strftime("%Y%m%d"), "selectType": "ALLBUT0999", "response": "json"}
    return get_json_with_retry(TWSE_T86_URL, params)


def fetch_tpex(trade_date: date) -> dict:
    """櫃買中心三大法人日交易資訊（sect=EW：不含權證）；休市日 stat 仍是 'ok'，data 為空。"""
    params = {"type": "Daily", "sect": "EW", "date": trade_date.strftime("%Y/%m/%d"), "response": "json"}
    return get_json_with_retry(TPEX_INSTI_URL, params)


def count_rows(payload: dict) -> int:
    """資料筆數。證交所放在最外層 data，櫃買中心放在 tables[].data。"""
    rows = len(payload.get("data") or [])
    return rows + sum(len(table.get("data") or []) for table in payload.get("tables", []))


def save_raw(conn, table: str, trade_date: date, payload: dict) -> None:
    """Upsert：同一天跑兩次只會留一筆，內容與抓取時間更新成最新的（冪等）。"""
    sql = f"""
        INSERT INTO raw.{table} (trade_date, stat, payload, fetched_at)
        VALUES (%s, %s, %s::jsonb, now())
        ON CONFLICT (trade_date) DO UPDATE
        SET stat = EXCLUDED.stat,
            payload = EXCLUDED.payload,
            fetched_at = EXCLUDED.fetched_at
    """
    with conn.cursor() as cur:
        cur.execute(sql, (trade_date, payload["stat"], json.dumps(payload, ensure_ascii=False)))
    conn.commit()


def _ingest(table: str, payload: dict, trade_date: date) -> None:
    with get_connection() as conn:
        run_sql_file(conn, DDL)
        save_raw(conn, table, trade_date, payload)
    rows = count_rows(payload)
    if rows == 0:
        logger.info("%s %s 無資料（休市，stat=%s），已記錄", table, trade_date, payload["stat"])
    else:
        logger.info("%s %s 寫入完成，%d 筆", table, trade_date, rows)


def ingest_twse(trade_date: date) -> None:
    _ingest("twse_t86", fetch_twse(trade_date), trade_date)


def ingest_tpex(trade_date: date) -> None:
    _ingest("tpex_insti_daily", fetch_tpex(trade_date), trade_date)


def main(argv: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    ingest_funcs = {"twse": ingest_twse, "tpex": ingest_tpex}
    if len(argv) != 3 or argv[1] not in ingest_funcs:
        sys.exit("用法：python -m ingestion.institutional twse|tpex YYYYMMDD")
    ingest_funcs[argv[1]](datetime.strptime(argv[2], "%Y%m%d").date())


if __name__ == "__main__":
    main(sys.argv)
