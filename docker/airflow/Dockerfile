# Airflow + 專案自己的 Python 環境
# ingestion 與 dbt 的套件裝在獨立 venv（/opt/pipeline-venv），不動 Airflow 本身的套件，
# 避免 dbt 和 Airflow 的相依版本互相衝突。DAG 用 BashOperator 呼叫這個 venv 裡的 python / dbt。
FROM apache/airflow:2.10.5

USER root
COPY requirements.txt /tmp/requirements.txt
RUN python -m venv /opt/pipeline-venv \
    && /opt/pipeline-venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt
USER airflow
