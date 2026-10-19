"""先載入專案根目錄的 .env，再執行 dbt，讓 profiles.yml 讀得到帳密。

用法（在專案根目錄）：
    python scripts/run_dbt.py debug
    python scripts/run_dbt.py run
"""
import os
import sys
from pathlib import Path

from dbt.cli.main import dbtRunner
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
DBT_DIR = ROOT / "dbt"

if __name__ == "__main__":
    load_dotenv(ROOT / ".env")
    os.chdir(DBT_DIR)
    args = sys.argv[1:] + ["--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    result = dbtRunner().invoke(args)
    sys.exit(0 if result.success else 1)
