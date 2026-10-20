"""回補一段期間的上市、上櫃 raw 資料（每日行情、三大法人），可中斷後重跑續抓。

每個日曆日（含週末、假日）每個來源各抓一次，休市也記一筆，交易日曆才不會有缺口。
已在 raw 表裡的日期直接跳過；抓失敗的日期不寫入，下次重跑會自動補。

用法：
    python -m ingestion.backfill 20231019 20261018
"""
import logging
import sys
import time
from datetime import date, datetime, timedelta

from ingestion import institutional, tpex, twse
from ingestion.common import get_connection, run_sql_file

logger = logging.getLogger(__name__)

REQUEST_INTERVAL_SECONDS = 5
# 連續失敗這麼多次，多半是被來源擋了，繼續打只會更糟，直接停下來
MAX_CONSECUTIVE_FAILURES = 5

SOURCES = {
    "TWSE": {"ingest": twse.ingest, "table": "raw.twse_mi_index", "ddl": "raw/001_create_raw_twse.sql"},
    "TPEx": {"ingest": tpex.ingest, "table": "raw.tpex_otc_quotes", "ddl": "raw/002_create_raw_tpex.sql"},
    "TWSE_INSTI": {"ingest": institutional.ingest_twse, "table": "raw.twse_t86",
                   "ddl": "raw/004_create_raw_institutional.sql"},
    "TPEx_INSTI": {"ingest": institutional.ingest_tpex, "table": "raw.tpex_insti_daily",
                   "ddl": "raw/004_create_raw_institutional.sql"},
}


def date_range(start: date, end: date) -> list[date]:
    return [start + timedelta(days=i) for i in range((end - start).days + 1)]


def existing_dates(conn, table: str, start: date, end: date) -> set[date]:
    """查 raw 表在區間內已經有哪些日期，用來跳過。"""
    with conn.cursor() as cur:
        cur.execute(f"SELECT trade_date FROM {table} WHERE trade_date BETWEEN %s AND %s", (start, end))
        return {row[0] for row in cur.fetchall()}


def plan(start: date, end: date) -> list[tuple[str, date]]:
    """列出還沒抓的 (source, date)。先建表，第一次跑時表還不存在也能查。"""
    todo = []
    with get_connection() as conn:
        for source, cfg in SOURCES.items():
            run_sql_file(conn, cfg["ddl"])
            done = existing_dates(conn, cfg["table"], start, end)
            todo += [(source, d) for d in date_range(start, end) if d not in done]
    return sorted(todo, key=lambda item: (item[1], item[0]))


def backfill(start: date, end: date) -> list[tuple[str, date]]:
    """逐筆抓取，回傳失敗清單。"""
    todo = plan(start, end)
    logger.info("%s ~ %s 共 %d 筆待抓（已存在的日期已跳過）", start, end, len(todo))

    failed = []
    consecutive_failures = 0
    for i, (source, trade_date) in enumerate(todo, start=1):
        if i > 1:
            time.sleep(REQUEST_INTERVAL_SECONDS)
        try:
            SOURCES[source]["ingest"](trade_date)
            consecutive_failures = 0
        except Exception:
            logger.exception("[%d/%d] %s %s 抓取失敗，跳過", i, len(todo), source, trade_date)
            failed.append((source, trade_date))
            consecutive_failures += 1
            if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                logger.error("連續失敗 %d 次，可能被來源封鎖，先停止；稍後重跑即可續抓", consecutive_failures)
                break
        if i % 50 == 0:
            logger.info("進度 %d/%d", i, len(todo))
    return failed


def main(argv: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if len(argv) != 3:
        sys.exit("用法：python -m ingestion.backfill YYYYMMDD YYYYMMDD")
    start, end = (datetime.strptime(arg, "%Y%m%d").date() for arg in argv[1:])
    if start > end:
        sys.exit("開始日期不能晚於結束日期")

    failed = backfill(start, end)
    if failed:
        logger.warning("有 %d 筆失敗，重跑同一個指令會再補：%s", len(failed),
                       ", ".join(f"{m} {d}" for m, d in failed))
        sys.exit(1)
    logger.info("回補完成，沒有失敗")


if __name__ == "__main__":
    main(sys.argv)
