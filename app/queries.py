"""Dashboard 用的查詢，全部讀 marts，每個函式回傳 pandas DataFrame。

這裡不 import streamlit：之後的 LINE bot 會直接重用這些查詢，只換掉顯示的那一層。
"""
import os

import pandas as pd
import psycopg2
from dotenv import load_dotenv

# 訊號代碼和 backtest_results.signal、stock_summary.signals_last_5d 一致
SIGNAL_LABELS = {
    "breakout": "帶量突破 20 日高點",
    "pullback": "跌破 20 日低點",
    "three_white_soldiers": "紅三兵",
    "evening_star": "黃昏之星",
    "dark_cloud_cover": "烏雲蓋頂",
}

TREND_LABELS = {
    "breakout": "帶量突破",
    "pullback": "跌破低點",
    "range": "盤整",
    "none": "無明顯趨勢",
}

# signals 一列一天，把五個訊號轉成長表（一列一個出現的訊號）；和 backtest_results 的寫法相同
_SIGNAL_EVENTS = """
    select s.trade_date, s.stock_id, e.signal
    from marts.signals s
    cross join lateral (values
        ('three_white_soldiers', s.three_white_soldiers),
        ('evening_star',         s.evening_star),
        ('dark_cloud_cover',     s.dark_cloud_cover),
        ('breakout',             s.trend_state = 'breakout'),
        ('pullback',             s.trend_state = 'pullback')
    ) as e(signal, fired)
    where e.fired
"""


# numeric 欄位預設會變成 Decimal，pandas 和 plotly 不好算；畫面用途不需要精確小數，統一轉 float
_NUMERIC_AS_FLOAT = psycopg2.extensions.new_type(
    psycopg2.extensions.DECIMAL.values, "NUMERIC_AS_FLOAT",
    lambda value, cur: float(value) if value is not None else None,
)
psycopg2.extensions.register_type(_NUMERIC_AS_FLOAT)


def get_connection():
    """連到 warehouse DB；本機直接執行時從 .env 讀帳密，在 Docker 裡由 compose 給環境變數。"""
    load_dotenv()
    return psycopg2.connect(
        host=os.getenv("WAREHOUSE_HOST", "localhost"),
        port=os.getenv("WAREHOUSE_PORT", os.getenv("POSTGRES_HOST_PORT", "5433")),
        dbname=os.getenv("WAREHOUSE_DB", "warehouse"),
        user=os.getenv("POSTGRES_USER", "postgres"),
        password=os.getenv("POSTGRES_PASSWORD"),
    )


def _query(sql: str, params: dict | None = None) -> pd.DataFrame:
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(sql, params or {})
        columns = [c.name for c in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=columns)


def latest_trade_date():
    """資料庫裡最新的交易日。"""
    df = _query("select max(trade_date) as d from marts.fact_daily_price")
    return df.loc[0, "d"]


def stock_list() -> pd.DataFrame:
    """所有股票的代號與名稱，給搜尋框用；已下市的排在後面。"""
    return _query("""
        select stock_id, stock_name, market, is_delisted
        from marts.stock_summary
        order by is_delisted, stock_id
    """)


def stock_summary(stock_id: str) -> pd.DataFrame:
    """單檔摘要，一列；查不到時是空的 DataFrame。"""
    return _query("select * from marts.stock_summary where stock_id = %(stock_id)s", {"stock_id": stock_id})


def price_history(stock_id: str, days: int = 250) -> pd.DataFrame:
    """最近 days 個有成交日的還原 OHLC、成交量、均線與訊號，日期由舊到新。"""
    return _query("""
        select
            p.trade_date,
            p.adj_open_price  as open,
            p.adj_high_price  as high,
            p.adj_low_price   as low,
            p.adj_close_price as close,
            i.adj_volume      as volume,
            i.ma5, i.ma20, i.ma60,
            s.three_white_soldiers, s.evening_star, s.dark_cloud_cover, s.trend_state
        from marts.fact_daily_price p
        join marts.indicators i on i.stock_id = p.stock_id and i.trade_date = p.trade_date
        join marts.signals s on s.stock_id = p.stock_id and s.trade_date = p.trade_date
        where p.stock_id = %(stock_id)s
        order by p.trade_date desc
        limit %(days)s
    """, {"stock_id": stock_id, "days": days}).sort_values("trade_date").reset_index(drop=True)


def signal_history(stock_id: str, days: int = 60) -> pd.DataFrame:
    """最近 days 個有成交日內出現過的訊號，一列一個訊號，日期由新到舊。"""
    return _query(f"""
        with recent as (
            select trade_date
            from marts.fact_daily_price
            where stock_id = %(stock_id)s and adj_close_price is not null
            order by trade_date desc
            limit %(days)s
        )
        select e.trade_date, e.signal, p.close_price
        from ({_SIGNAL_EVENTS}) e
        join recent r on r.trade_date = e.trade_date
        join marts.fact_daily_price p on p.stock_id = e.stock_id and p.trade_date = e.trade_date
        where e.stock_id = %(stock_id)s
        order by e.trade_date desc, e.signal
    """, {"stock_id": stock_id, "days": days})


def signals_on(trade_date) -> pd.DataFrame:
    """某一天出現訊號的個股（排除 ETF 等），附上該訊號持有 20 天的回測數字。"""
    return _query(f"""
        select
            e.signal,
            e.stock_id,
            ss.stock_name,
            ss.market,
            ss.industry,
            p.close_price,
            round((p.adj_close_price / prev.adj_close_price - 1)::numeric, 6) as change_pct,
            b.win_rate          as bt_win_rate,
            b.avg_excess_return as bt_avg_excess_return,
            b.t_stat            as bt_t_stat
        from ({_SIGNAL_EVENTS}) e
        join marts.stock_summary ss on ss.stock_id = e.stock_id
        join marts.fact_daily_price p on p.stock_id = e.stock_id and p.trade_date = e.trade_date
        left join lateral (
            select adj_close_price
            from marts.fact_daily_price
            where stock_id = e.stock_id and trade_date < e.trade_date and adj_close_price is not null
            order by trade_date desc
            limit 1
        ) prev on true
        left join marts.backtest_results b on b.signal = e.signal and b.horizon_days = 20
        where e.trade_date = %(trade_date)s
          and ss.is_common_stock
        order by e.signal, e.stock_id
    """, {"trade_date": trade_date})


def backtest_results() -> pd.DataFrame:
    return _query("select * from marts.backtest_results order by horizon_days desc, t_stat desc")


def signal_returns(signal: str, horizon_days: int) -> pd.DataFrame:
    """某個訊號每次出現後的報酬，畫分布圖用。"""
    column = {5: "return_5d", 20: "return_20d"}[horizon_days]
    return _query(f"""
        select f.{column} as ret
        from ({_SIGNAL_EVENTS}) e
        join marts.forward_returns f on f.stock_id = e.stock_id and f.trade_date = e.trade_date
        where e.signal = %(signal)s and f.{column} is not null
    """, {"signal": signal})
