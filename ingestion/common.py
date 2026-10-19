"""ingestion 共用工具：HTTP 重試、資料庫連線、執行 DDL。"""
import logging
import os
import time
from pathlib import Path

import psycopg2
import requests
from dotenv import load_dotenv

logger = logging.getLogger(__name__)

MAX_RETRIES = 3
TIMEOUT_SECONDS = 30
SQL_DIR = Path(__file__).resolve().parent.parent / "sql"


def get_json_with_retry(url: str, params: dict, session: requests.Session | None = None) -> dict:
    """GET 並解析 JSON，失敗時以 exponential backoff 重試（2、4 秒），第 3 次仍失敗就丟出例外。

    被來源擋下時常回 HTML 而不是 JSON，resp.json() 會丟 ValueError，一樣進入重試。
    """
    session = session or requests.Session()
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = session.get(url, params=params, timeout=TIMEOUT_SECONDS)
            resp.raise_for_status()
            payload = resp.json()
            if "stat" not in payload:
                raise ValueError(f"回應缺少 stat 欄位：{str(payload)[:200]}")
            return payload
        except (requests.RequestException, ValueError) as exc:
            if attempt == MAX_RETRIES:
                raise
            wait = 2 ** attempt
            logger.warning("第 %d 次請求 %s 失敗：%s，%d 秒後重試", attempt, params, exc, wait)
            time.sleep(wait)


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


def run_sql_file(conn, relative_path: str) -> None:
    """執行 sql/ 底下的 DDL 檔（檔案內用 IF NOT EXISTS，重跑無副作用）。"""
    with conn.cursor() as cur:
        cur.execute((SQL_DIR / relative_path).read_text(encoding="utf-8"))
    conn.commit()
