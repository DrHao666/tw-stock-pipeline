"""今日訊號：某個交易日出現訊號的個股，附上該訊號持有 20 天的回測數字；點一列就跳到個股頁。"""
import streamlit as st

import data
from queries import SIGNAL_LABELS

latest = data.latest_trade_date()
if latest is None:
    st.warning("資料庫裡還沒有行情資料。")
    st.stop()

trade_date = st.date_input("交易日", value=latest, max_value=latest)
events = data.signals_on(trade_date)

if events.empty:
    st.info(f"{trade_date} 沒有個股出現訊號（可能是休市日）。")
    st.stop()

counts = events["signal"].value_counts()
chosen = st.pills(
    "訊號", list(SIGNAL_LABELS), selection_mode="multi", default=["breakout"],
    format_func=lambda k: f"{SIGNAL_LABELS[k]}（{counts.get(k, 0)}）",
)
shown = events[events["signal"].isin(chosen)].copy()
shown["signal"] = shown["signal"].map(SIGNAL_LABELS)

st.caption(
    "只列個股（排除 ETF、債券等）。回測欄位是這個訊號過去三年「隔天開盤買、持有 20 天」的統計，"
    "超額報酬是扣掉同一天所有股票平均之後的數字；t 值絕對值小於 2 代表和隨便挑一天差不多。點一列看個股。"
)

selection = st.dataframe(
    shown,
    hide_index=True,
    width="stretch",
    on_select="rerun",
    selection_mode="single-row",
    column_order=["signal", "stock_id", "stock_name", "market", "industry", "close_price", "change_pct",
                  "bt_win_rate", "bt_avg_excess_return", "bt_t_stat"],
    column_config={
        "signal": "訊號",
        "stock_id": "代號",
        "stock_name": "名稱",
        "market": "市場",
        "industry": "產業",
        "close_price": st.column_config.NumberColumn("收盤", format="%.2f"),
        "change_pct": st.column_config.NumberColumn("漲跌幅", format="percent"),
        "bt_win_rate": st.column_config.NumberColumn("回測勝率", format="percent"),
        "bt_avg_excess_return": st.column_config.NumberColumn("回測超額報酬", format="percent"),
        "bt_t_stat": st.column_config.NumberColumn("t 值", format="%.2f"),
    },
)

if selection.selection.rows:
    picked = shown.iloc[selection.selection.rows[0]]["stock_id"]
    st.switch_page("views/stock.py", query_params={"stock": picked})
