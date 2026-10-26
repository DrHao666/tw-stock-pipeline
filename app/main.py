"""Dashboard 入口：streamlit run app/main.py（Docker 裡由 compose 的 dashboard service 執行）。"""
import streamlit as st

st.set_page_config(page_title="台股訊號", page_icon="📈", layout="wide")

pages = [
    st.Page("views/today.py", title="今日訊號", icon="🔔", default=True),
    st.Page("views/stock.py", title="個股", icon="📈", url_path="stock"),
    st.Page("views/backtest.py", title="回測", icon="🧪", url_path="backtest"),
]
st.navigation(pages, position="top").run()
