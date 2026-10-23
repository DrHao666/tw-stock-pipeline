"""每日收盤後抓取上市、上櫃行情、三大法人買賣超、融資融券、除權息／減資與集保股權分散表，寫入 raw，再用 dbt 轉換與測試。

- 每天台北時間 18:00 執行，週末、假日也跑：休市日照樣記一筆，交易日曆才不會有缺口。
- 抓哪一天由 Airflow 的 data interval 決定，不是「今天」；要補某一天，在 UI 重跑那一次即可。
  raw 是 upsert、staging 是以 trade_date 先刪後插的 incremental，重跑不會產生重複。
- 例外：股權分散表的開放資料只有最新一週，不看 data interval；重跑舊日期補不回當時那週。
- dbt build 的測試就是品質檢查，任何一個失敗整個 DAG 就會失敗。
"""
from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.operators.bash import BashOperator

PROJECT_DIR = "/opt/airflow/project"
VENV_BIN = "/opt/pipeline-venv/bin"
# 排程在每天 18:00 觸發，data_interval_end 就是當天 18:00，取台北時區的日期當作交易日
TRADE_DATE = "{{ data_interval_end.in_timezone('Asia/Taipei').strftime('%Y%m%d') }}"
TRADE_MONTH = "{{ data_interval_end.in_timezone('Asia/Taipei').strftime('%Y%m') }}"

default_args = {
    # 程式內已有 HTTP 重試；這裡再重試是為了應付來源晚公布或暫時連不上
    "retries": 2,
    "retry_delay": timedelta(minutes=10),
}

with DAG(
    dag_id="tw_stock_daily",
    schedule="0 18 * * *",
    start_date=pendulum.datetime(2026, 10, 20, tz="Asia/Taipei"),
    catchup=False,  # 歷史資料用 ingestion.backfill 回補，不靠 Airflow catchup
    max_active_runs=1,
    default_args=default_args,
    tags=["tw-stock"],
) as dag:
    fetch_twse = BashOperator(
        task_id="fetch_twse",
        bash_command=f"{VENV_BIN}/python -m ingestion.twse {TRADE_DATE}",
        cwd=PROJECT_DIR,
    )

    fetch_tpex = BashOperator(
        task_id="fetch_tpex",
        bash_command=f"{VENV_BIN}/python -m ingestion.tpex {TRADE_DATE}",
        cwd=PROJECT_DIR,
    )

    fetch_twse_institutional = BashOperator(
        task_id="fetch_twse_institutional",
        bash_command=f"{VENV_BIN}/python -m ingestion.institutional twse {TRADE_DATE}",
        cwd=PROJECT_DIR,
    )

    fetch_tpex_institutional = BashOperator(
        task_id="fetch_tpex_institutional",
        bash_command=f"{VENV_BIN}/python -m ingestion.institutional tpex {TRADE_DATE}",
        cwd=PROJECT_DIR,
    )

    fetch_twse_margin = BashOperator(
        task_id="fetch_twse_margin",
        bash_command=f"{VENV_BIN}/python -m ingestion.margin twse {TRADE_DATE}",
        cwd=PROJECT_DIR,
    )

    fetch_tpex_margin = BashOperator(
        task_id="fetch_tpex_margin",
        bash_command=f"{VENV_BIN}/python -m ingestion.margin tpex {TRADE_DATE}",
        cwd=PROJECT_DIR,
    )

    # 開放資料只有最新一週、更新日不固定，每天抓最新的；同一週重抓只會覆蓋同一筆
    fetch_shareholding = BashOperator(
        task_id="fetch_shareholding",
        bash_command=f"{VENV_BIN}/python -m ingestion.shareholding",
        cwd=PROJECT_DIR,
    )

    # 當月的除權息與減資公告會陸續增加，每天重抓當月
    fetch_corporate_actions = BashOperator(
        task_id="fetch_corporate_actions",
        bash_command=f"{VENV_BIN}/python -m ingestion.corporate_actions {TRADE_MONTH} {TRADE_MONTH}",
        cwd=PROJECT_DIR,
    )

    # target、log 寫到容器內的 /tmp，不寫回掛載的專案目錄
    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=(
            f"{VENV_BIN}/dbt build"
            f" --project-dir {PROJECT_DIR}/dbt --profiles-dir {PROJECT_DIR}/dbt"
            " --target-path /tmp/dbt/target --log-path /tmp/dbt/logs"
        ),
        cwd=PROJECT_DIR,
    )

    [
        fetch_twse,
        fetch_tpex,
        fetch_twse_institutional,
        fetch_tpex_institutional,
        fetch_twse_margin,
        fetch_tpex_margin,
        fetch_shareholding,
        fetch_corporate_actions,
    ] >> dbt_build
