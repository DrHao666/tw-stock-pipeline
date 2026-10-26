"""個股：摘要、還原 K 線（均線、成交量、訊號標記）、近 60 天訊號。"""
import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from plotly.subplots import make_subplots

import data
from queries import SIGNAL_LABELS, TREND_LABELS

# 台股慣例：紅漲綠跌
UP_COLOR = "#e5484d"
DOWN_COLOR = "#30a46c"

# 訊號標在 K 線上的樣式：看多的標在最低價下方，看空的標在最高價上方
MARKERS = {
    "breakout":             {"symbol": "triangle-up",   "color": "#e5484d", "below": True},
    "three_white_soldiers": {"symbol": "star",          "color": "#f76b15", "below": True},
    "pullback":             {"symbol": "triangle-down", "color": "#30a46c", "below": False},
    "evening_star":         {"symbol": "star",          "color": "#0090ff", "below": False},
    "dark_cloud_cover":     {"symbol": "x",             "color": "#8e4ec6", "below": False},
}


def pct(value) -> str:
    return "—" if pd.isna(value) else f"{value * 100:+.2f}%"


def price_chart(history: pd.DataFrame) -> go.Figure:
    fig = make_subplots(rows=2, cols=1, shared_xaxes=True, row_heights=[0.75, 0.25], vertical_spacing=0.03)
    # 用字串當 x 軸，休市日不會在圖上留空白
    x = history["trade_date"].astype(str)

    fig.add_trace(go.Candlestick(
        x=x, open=history["open"], high=history["high"], low=history["low"], close=history["close"],
        increasing_line_color=UP_COLOR, decreasing_line_color=DOWN_COLOR, name="還原 K 線",
    ), row=1, col=1)
    for column, color in [("ma5", "#f5a524"), ("ma20", "#0090ff"), ("ma60", "#8e4ec6")]:
        fig.add_trace(go.Scatter(x=x, y=history[column], name=column.upper(),
                                 line={"width": 1.2, "color": color}), row=1, col=1)

    price_range = history["high"].max() - history["low"].min()
    offset = price_range * 0.03
    for signal, style in MARKERS.items():
        if signal in ("breakout", "pullback"):
            fired = history["trend_state"] == signal
        else:
            fired = history[signal]
        rows = history[fired]
        if rows.empty:
            continue
        y = rows["low"] - offset if style["below"] else rows["high"] + offset
        fig.add_trace(go.Scatter(
            x=rows["trade_date"].astype(str), y=y, mode="markers", name=SIGNAL_LABELS[signal],
            marker={"symbol": style["symbol"], "size": 10, "color": style["color"]},
        ), row=1, col=1)

    volume_colors = [UP_COLOR if c >= o else DOWN_COLOR for o, c in zip(history["open"], history["close"])]
    fig.add_trace(go.Bar(x=x, y=history["volume"] / 1000, marker_color=volume_colors,
                         name="成交量（張）", showlegend=False), row=2, col=1)

    fig.update_layout(
        height=620, margin={"l": 10, "r": 10, "t": 10, "b": 10},
        xaxis_rangeslider_visible=False,
        legend={"orientation": "h", "y": 1.02, "x": 0},
    )
    fig.update_xaxes(type="category", nticks=10)
    fig.update_yaxes(title_text="還原價", row=1, col=1)
    fig.update_yaxes(title_text="張", row=2, col=1)
    return fig


stocks = data.stock_list()
options = stocks["stock_id"].tolist()
names = dict(zip(stocks["stock_id"], stocks["stock_name"]))

# 從「今日訊號」點進來時，網址帶 ?stock=代號
requested = st.query_params.get("stock", "2330")
default_index = options.index(requested) if requested in options else 0

stock_id = st.selectbox(
    "股票（可輸入代號或名稱搜尋）", options, index=default_index,
    format_func=lambda s: f"{s} {names.get(s, '')}",
)
st.query_params["stock"] = stock_id

summary = data.stock_summary(stock_id)
if summary.empty:
    st.warning("查不到這檔股票。")
    st.stop()
s = summary.iloc[0]

title = f"{s['stock_id']} {s['stock_name']}"
if s["is_delisted"]:
    title += "（已下市）"
st.subheader(title)
st.caption(" · ".join(str(v) for v in [s["market"], s["security_type"], s["industry"]] if pd.notna(v))
           + f" · 資料日期 {s['last_trade_date']}")

c1, c2, c3, c4 = st.columns(4)
c1.metric("收盤價", f"{s['close_price']:,.2f}", pct(s["change_pct"]), delta_color="inverse")
c2.metric("趨勢", TREND_LABELS.get(s["trend_state"], "—"))
c3.metric("MA20", "—" if pd.isna(s["ma20"]) else f"{s['ma20']:,.2f}")
c4.metric("20 日高／低", "—" if pd.isna(s["high_20"]) else f"{s['high_20']:,.2f} / {s['low_20']:,.2f}")

recent = [SIGNAL_LABELS[x] for x in s["signals_last_5d"]]
st.write("**近 5 個交易日出現的訊號**：" + ("、".join(recent) if recent else "沒有"))

days = st.segmented_control("K 線範圍", [60, 120, 250, 500], default=250,
                            format_func=lambda d: f"{d} 天")
history = data.price_history(stock_id, days or 250)
if history.empty:
    st.info("這檔沒有足夠的成交資料可以畫圖。")
else:
    st.plotly_chart(price_chart(history), width="stretch")
    st.caption("價格與成交量都是還原後的數字（除權息、減資、面額變更都已調整），所以和看盤軟體的歷史價格可能不同。")

left, right = st.columns([1, 2])
with left:
    st.markdown("**每種訊號最近一次出現**")
    last_seen = pd.DataFrame({
        "訊號": [SIGNAL_LABELS[k] for k in SIGNAL_LABELS],
        "日期": [s[f"last_{k}"] for k in SIGNAL_LABELS],
    })
    last_seen["日期"] = last_seen["日期"].map(lambda d: "三年內沒有" if pd.isna(d) else str(d))
    st.dataframe(last_seen, hide_index=True, width="stretch")

with right:
    st.markdown("**近 60 個交易日的訊號**")
    recent_signals = data.signal_history(stock_id, 60)
    if recent_signals.empty:
        st.write("沒有。")
    else:
        recent_signals["signal"] = recent_signals["signal"].map(SIGNAL_LABELS)
        st.dataframe(
            recent_signals.rename(columns={"trade_date": "日期", "signal": "訊號", "close_price": "當天收盤"}),
            hide_index=True, width="stretch",
        )
