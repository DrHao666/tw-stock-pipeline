-- 台股普通股漲跌幅限制 10%：和前一個有成交的交易日比，還原收盤價的漲跌幅不應超過 10%
-- 用還原價比，除權息、減資造成的價格跳動不會被誤判；容許 0.05% 的誤差（還原因子四捨五入）
-- 排除：
--   新股上市前 5 個交易日（不設漲跌幅限制）
--   ETF、ETN、TDR 等（部分追蹤國外標的，沒有漲跌幅限制），只檢查普通股、創新板與已下市的 4 碼代號
with priced as (
    select
        p.trade_date,
        p.stock_id,
        p.adj_close_price,
        d.security_type,
        d.listing_date,
        lag(p.adj_close_price) over (partition by p.stock_id order by p.trade_date) as prev_adj_close,
        row_number() over (partition by p.stock_id order by p.trade_date) as nth_trade
    from {{ ref('fact_daily_price') }} p
    join {{ ref('dim_stock') }} d on d.stock_sk = p.stock_sk
    where p.adj_close_price is not null
)

select
    trade_date,
    stock_id,
    prev_adj_close,
    adj_close_price,
    round((adj_close_price / prev_adj_close - 1) * 100, 2) as change_pct
from priced
where prev_adj_close is not null
  and abs(adj_close_price / prev_adj_close - 1) > 0.1005
  and (security_type in ('股票', '創新板') or (security_type is null and stock_id ~ '^[0-9]{4}$'))
  -- 上市日在回補期間內的，前 5 個交易日不檢查
  and not (listing_date >= '{{ var("history_start_date") }}'::date and nth_trade <= 5)
