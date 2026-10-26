"""回測：各訊號 × 持有天數的統計表，加上單一訊號的報酬分布。"""
import plotly.graph_objects as go
import streamlit as st

import data
from queries import SIGNAL_LABELS

st.subheader("訊號回測")
st.caption(
    "訊號日收盤後才知道訊號，隔天開盤買進，持有 5 或 20 個交易日後收盤賣出；只算個股，全部用還原價。"
    "超額報酬 = 訊號股報酬 − 同一天所有股票的平均報酬。t 值絕對值大於 2 才算統計上顯著。"
)

results = data.backtest_results()
if results.empty:
    st.info("還沒有回測結果，先跑一次 dbt build。")
    st.stop()

table = results.assign(signal=results["signal"].map(SIGNAL_LABELS))
st.dataframe(
    table,
    hide_index=True,
    width="stretch",
    column_order=["signal", "horizon_days", "events", "avg_return", "median_return", "win_rate",
                  "avg_return_after_cost", "baseline_return", "avg_excess_return", "t_stat"],
    column_config={
        "signal": "訊號",
        "horizon_days": st.column_config.NumberColumn("持有天數"),
        "events": st.column_config.NumberColumn("次數", format="localized"),
        "avg_return": st.column_config.NumberColumn("平均報酬", format="percent"),
        "median_return": st.column_config.NumberColumn("中位數", format="percent"),
        "win_rate": st.column_config.NumberColumn("勝率", format="percent"),
        "avg_return_after_cost": st.column_config.NumberColumn("扣成本後", format="percent"),
        "baseline_return": st.column_config.NumberColumn("基準", format="percent"),
        "avg_excess_return": st.column_config.NumberColumn("超額報酬", format="percent"),
        "t_stat": st.column_config.NumberColumn("t 值", format="%.2f"),
    },
)

st.markdown("**報酬分布**")
c1, c2 = st.columns(2)
signal = c1.selectbox("訊號", list(SIGNAL_LABELS), format_func=SIGNAL_LABELS.get)
horizon = c2.segmented_control("持有天數", [5, 20], default=20, format_func=lambda d: f"{d} 天") or 20

returns = data.signal_returns(signal, horizon)
row = results[(results["signal"] == signal) & (results["horizon_days"] == horizon)]
if returns.empty or row.empty:
    st.info("這個組合沒有回測資料。")
    st.stop()

r = row.iloc[0]
# 極端值會把圖壓扁，畫圖時只取 1%～99% 分位數之間，統計數字仍用全部資料
low, high = returns["ret"].quantile([0.01, 0.99])
clipped = returns["ret"][(returns["ret"] >= low) & (returns["ret"] <= high)] * 100

fig = go.Figure(go.Histogram(x=clipped, nbinsx=60, marker_color="#0090ff", name="報酬"))
# 平均和中位數常常很接近，標籤分左右放才不會疊在一起
for value, label, color, position in [
    (r["avg_return"] * 100, "平均", "#e5484d", "top right"),
    (r["median_return"] * 100, "中位數", "#f76b15", "top left"),
    (r["baseline_return"] * 100, "基準", "#8b8d98", "bottom right"),
]:
    fig.add_vline(x=value, line_color=color, line_dash="dash",
                  annotation_text=f"{label} {value:+.2f}%", annotation_position=position)
fig.update_layout(height=420, margin={"l": 10, "r": 10, "t": 30, "b": 10}, showlegend=False,
                  xaxis_title="報酬（%）", yaxis_title="次數")
st.plotly_chart(fig, width="stretch")
st.caption(f"共 {len(returns):,} 次；圖上只畫 1%～99% 分位數之間的部分，避免少數極端值把圖壓扁。")
