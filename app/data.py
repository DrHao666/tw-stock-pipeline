"""queries.py 加上快取：同樣的查詢 10 分鐘內不重查資料庫（資料一天只更新一次）。"""
import streamlit as st

import queries

TTL_SECONDS = 600

latest_trade_date = st.cache_data(ttl=TTL_SECONDS)(queries.latest_trade_date)
stock_list = st.cache_data(ttl=TTL_SECONDS)(queries.stock_list)
stock_summary = st.cache_data(ttl=TTL_SECONDS)(queries.stock_summary)
price_history = st.cache_data(ttl=TTL_SECONDS)(queries.price_history)
signal_history = st.cache_data(ttl=TTL_SECONDS)(queries.signal_history)
signals_on = st.cache_data(ttl=TTL_SECONDS)(queries.signals_on)
backtest_results = st.cache_data(ttl=TTL_SECONDS)(queries.backtest_results)
signal_returns = st.cache_data(ttl=TTL_SECONDS)(queries.signal_returns)
