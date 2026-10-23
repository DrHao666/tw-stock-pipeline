"""抓取證交所 ISIN 清單（上市、上櫃目前掛牌的有價證券），解析後寫入 raw，一天一筆快照。

和其他來源不同，這裡不存原始回應：兩頁 HTML 一天約 13 MB、九成是權證，
原封不動存一年要好幾 GB，所以只存解析後的非權證列（約 2,400 列）。
清單只有「目前」，沒有歷史可回補；每天抓一份，產業別、證券類別的變化從開始抓的那天往後累積。

用法：
    python -m ingestion.isin
"""
import json
import logging
import sys
import time
from datetime import date, datetime, timedelta, timezone
from html.parser import HTMLParser

import requests

from ingestion.common import MAX_RETRIES, TIMEOUT_SECONDS, get_connection, run_sql_file

logger = logging.getLogger(__name__)

ISIN_URL = "https://isin.twse.com.tw/isin/C_public.jsp"
# strMode：2 上市、4 上櫃
MODES = {"2": "上市", "4": "上櫃"}
HEADERS = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"}
FIELDS = ["證券類別", "代號", "名稱", "ISIN", "上市日", "市場別", "產業別", "CFICode", "備註"]
# 解析出來的普通股少於這個數字，多半是頁面格式變了或只抓到一半，寧可失敗也不要寫進一份殘缺的快照
MIN_STOCK_ROWS = 1500
DDL = "raw/007_create_raw_isin.sql"
TAIPEI = timezone(timedelta(hours=8))


class IsinTableParser(HTMLParser):
    """把頁面上每個 <tr> 的 <td> 文字收成一個 list。"""

    def __init__(self):
        super().__init__()
        self.rows, self._row, self._cell = [], None, None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self._row = []
        elif tag == "td" and self._row is not None:
            self._cell = []

    def handle_endtag(self, tag):
        if tag == "td" and self._cell is not None:
            self._row.append("".join(self._cell).strip())
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self.rows.append(self._row)
            self._row = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)


def parse(html: str) -> list[list[str]]:
    """只有一格的列是分類標題（股票、ETF、權證…），下面接該類的資料列；權證整類跳過。

    第一欄是「代號＋全形空白＋名稱」，拆成兩欄。
    """
    parser = IsinTableParser()
    parser.feed(html)
    rows, category = [], None
    for cells in parser.rows:
        if len(cells) == 1:
            category = cells[0]
        elif len(cells) == 7 and category and "　" in cells[0]:
            if "權證" in category:
                continue
            code, name = cells[0].split("　", 1)
            rows.append([category, code.strip(), name.strip(), *cells[1:]])
    return rows


def fetch(mode: str) -> list[list[str]]:
    """頁面是 MS950（cp950）編碼，用 big5 解會在擴充字失敗。"""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = requests.get(ISIN_URL, params={"strMode": mode}, headers=HEADERS, timeout=TIMEOUT_SECONDS)
            resp.raise_for_status()
            rows = parse(resp.content.decode("cp950"))
            if not rows:
                raise ValueError("頁面裡解析不出任何資料列")
            return rows
        except (requests.RequestException, ValueError) as exc:
            if attempt == MAX_RETRIES:
                raise
            wait = 2 ** attempt
            logger.warning("第 %d 次抓取 ISIN 清單（%s）失敗：%s，%d 秒後重試", attempt, MODES[mode], exc, wait)
            time.sleep(wait)


def save_raw(conn, snapshot_date: date, payload: dict) -> None:
    """Upsert：同一天重抓只會留一筆最新的（冪等）。"""
    sql = """
        INSERT INTO raw.twse_isin (snapshot_date, payload, fetched_at)
        VALUES (%s, %s::jsonb, now())
        ON CONFLICT (snapshot_date) DO UPDATE
        SET payload = EXCLUDED.payload,
            fetched_at = EXCLUDED.fetched_at
    """
    with conn.cursor() as cur:
        cur.execute(sql, (snapshot_date, json.dumps(payload, ensure_ascii=False)))
    conn.commit()


def ingest() -> None:
    data = []
    for i, mode in enumerate(MODES):
        if i > 0:
            time.sleep(5)
        data += fetch(mode)
    stock_rows = sum(1 for row in data if row[0] == "股票")
    if stock_rows < MIN_STOCK_ROWS:
        raise ValueError(f"只解析出 {stock_rows} 檔普通股（預期至少 {MIN_STOCK_ROWS}），頁面格式可能變了")

    snapshot_date = datetime.now(TAIPEI).date()
    with get_connection() as conn:
        run_sql_file(conn, DDL)
        save_raw(conn, snapshot_date, {"fields": FIELDS, "data": data})
    logger.info("twse_isin %s 寫入完成，%d 筆（其中普通股 %d）", snapshot_date, len(data), stock_rows)


def main(argv: list[str]) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if len(argv) != 1:
        sys.exit("用法：python -m ingestion.isin（清單只有目前掛牌的證券，不吃日期參數）")
    ingest()


if __name__ == "__main__":
    main(sys.argv)
