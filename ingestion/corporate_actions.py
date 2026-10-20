"""抓取上市、上櫃的除權息與減資結果表，按月原封不動寫入 raw。

四個來源格式不同（日期寫法、千分位、空值符號），清理留給 dbt staging。
已抓過且抓取時該月已結束的月份會跳過；當月或抓的時候還沒結束的月份一律重抓，
因為月中還會有新的公告。

用法：
    python -m ingestion.corporate_actions 202310 202610
"""
import calendar
import json
import logging
import sys
import time
from datetime import date, datetime

from ingestion.common import get_connection, get_json_with_retry, run_sql_file

logger = logging.getLogger(__name__)

REQUEST_INTERVAL_SECONDS = 5
MAX_CONSECUTIVE_FAILURES = 5

SOURCES = {
    "twse_ex_rights": {
        "url": "https://www.twse.com.tw/rwd/zh/exRight/TWT49U",
        "date_format": "%Y%m%d",
    },
    "twse_capital_reduction": {
        "url": "https://www.twse.com.tw/rwd/zh/reducation/TWTAUU",
        "date_format": "%Y%m%d",
    },
    "tpex_ex_rights": {
        "url": "https://www.tpex.org.tw/www/zh-tw/bulletin/exDailyQ",
        "date_format": "%Y/%m/%d",
    },
    "tpex_capital_reduction": {
        "url": "https://www.tpex.org.tw/www/zh-tw/bulletin/revivt",
        "date_format": "%Y/%m/%d",
    },
}


def month_end(month_start: date) -> date:
    return month_start.replace(day=calendar.monthrange(month_start.year, month_start.month)[1])


def month_range(start: date, end: date) -> list[date]:
    """start、end 所在月份之間（含頭尾）每個月的第一天。"""
    months = []
    current = start.replace(day=1)
    while current <= end:
        months.append(current)
        current = date(current.year + current.month // 12, current.month % 12 + 1, 1)
    return months


def fetch(source: str, month_start: date) -> dict:
    """查一整個月；當月的結束日只查到今天。"""
    cfg = SOURCES[source]
    end = min(month_end(month_start), date.today())
    params = {
        "startDate": month_start.strftime(cfg["date_format"]),
        "endDate": end.strftime(cfg["date_format"]),
        "response": "json",
    }
    return get_json_with_retry(cfg["url"], params)


def count_rows(payload: dict) -> int:
    """事件筆數。資料有的放在最外層 data，有的放在 tables[].data。"""
    rows = len(payload.get("data") or [])
    return rows + sum(len(table.get("data") or []) for table in payload.get("tables", []))


def save_raw(conn, source: str, month_start: date, payload: dict) -> None:
    """Upsert：同一個月重抓只會留一筆最新的（冪等）。"""
    sql = f"""
        INSERT INTO raw.{source} (period_start, period_end, stat, payload, fetched_at)
        VALUES (%s, %s, %s, %s::jsonb, now())
        ON CONFLICT (period_start) DO UPDATE
        SET period_end = EXCLUDED.period_end,
            stat = EXCLUDED.stat,
            payload = EXCLUDED.payload,
            fetched_at = EXCLUDED.fetched_at
    """
    with conn.cursor() as cur:
        cur.execute(sql, (month_start, month_end(month_start), payload["stat"],
                          json.dumps(payload, ensure_ascii=False)))
    conn.commit()


def completed_months(conn, source: str) -> set[date]:
    """抓取時間晚於該月最後一天的月份，資料已經完整，不用重抓。"""
    with conn.cursor() as cur:
        cur.execute(f"""
            SELECT period_start FROM raw.{source}
            WHERE (fetched_at AT TIME ZONE 'Asia/Taipei')::date > period_end
        """)
        return {row[0] for row in cur.fetchall()}


def run(start: date, end: date) -> list[tuple[str, date]]:
    """抓取區間內缺的月份，回傳失敗清單。"""
    with get_connection() as conn:
        run_sql_file(conn, "raw/003_create_raw_corporate_actions.sql")
        todo = []
        for source in SOURCES:
            done = completed_months(conn, source)
            todo += [(source, m) for m in month_range(start, end) if m not in done]
    logger.info("共 %d 筆待抓（已完整的月份已跳過）", len(todo))

    failed = []
    consecutive_failures = 0
    for i, (source, month_start) in enumerate(todo, start=1):
        if i > 1:
            time.sleep(REQUEST_INTERVAL_SECONDS)
        try:
            payload = fetch(source, month_start)
            with get_connection() as conn:
                save_raw(conn, source, month_start, payload)
            logger.info("[%d/%d] %s %s 寫入 %d 筆（stat=%s）", i, len(todo), source,
                        month_start.strftime("%Y-%m"), count_rows(payload), payload["stat"])
            consecutive_failures = 0
        except Exception:
            logger.exception("[%d/%d] %s %s 抓取失敗，跳過", i, len(todo), source, month_start.strftime("%Y-%m"))
            failed.append((source, month_start))
            consecutive_failures += 1
            if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                logger.error("連續失敗 %d 次，可能被來源封鎖，先停止；稍後重跑即可續抓", consecutive_failures)
                break
    return failed


def main(argv: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if len(argv) != 3:
        sys.exit("用法：python -m ingestion.corporate_actions YYYYMM YYYYMM")
    start, end = (datetime.strptime(arg, "%Y%m").date() for arg in argv[1:])
    if start > end:
        sys.exit("開始月份不能晚於結束月份")

    failed = run(start, end)
    if failed:
        logger.warning("有 %d 筆失敗，重跑同一個指令會再補：%s", len(failed),
                       ", ".join(f"{s} {m:%Y-%m}" for s, m in failed))
        sys.exit(1)
    logger.info("抓取完成，沒有失敗")


if __name__ == "__main__":
    main(sys.argv)
