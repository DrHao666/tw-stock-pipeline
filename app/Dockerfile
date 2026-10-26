# Dashboard：只裝 Streamlit 相關套件，和 Airflow image 分開
FROM python:3.12-slim

WORKDIR /app
COPY app/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

# 程式碼由 compose 掛進來（./app:/app），改了存檔就生效，不用重 build
EXPOSE 8501
CMD ["streamlit", "run", "main.py", "--server.address=0.0.0.0", "--server.port=8501"]
