#!/bin/bash
# Postgres 第一次初始化（volume 是空的）時會自動執行 /docker-entrypoint-initdb.d/ 裡的腳本。
# POSTGRES_DB 已經建好 Airflow 的 metadata DB，這裡再建一個放股票資料的 warehouse DB。
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    CREATE DATABASE ${WAREHOUSE_DB};
SQL
