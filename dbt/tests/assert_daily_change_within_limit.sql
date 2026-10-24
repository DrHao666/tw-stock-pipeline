-- 台股普通股漲跌幅限制 10%：和「前一個交易日」比，還原收盤價的漲跌幅不應超過 10%
-- 用還原價比，除權息、減資、變更面額造成的價格跳動不會被誤判；容許 0.05% 的誤差（還原因子四捨五入）
-- 只比連續兩個交易日都有成交的情況：前一個有價格的日子若在更早之前（沒成交、停止買賣），
-- 中間可以累積好幾個漲跌停，不適用 10% 的限制
-- 有事件的那天（除權息、減資等）改用交易所的漲跌停算法，以原始收盤價檢查：
--   現金增資除權時漲停 = 減除股利參考價 × 1.1、跌停 = 除權息參考價 × 0.9，上下界不對稱，
--   所以容許區間是 [兩個參考價較小者 × 0.9, 較大者 × 1.1]
-- 排除：
--   在某個市場的前 5 個交易日（新上市、上櫃轉上市都不設漲跌幅）；回補起點就已經在交易的不算
--   ETF、ETN、TDR 等（部分追蹤國外標的，沒有漲跌幅限制），只檢查普通股、創新板與已下市的 4 碼代號
with market_days as (
    select trade_date, 'TWSE'::text as market,
        lag(trade_date) over (order by trade_date) as prev_trading_day
    from {{ ref('stg_trading_calendar') }}
    where twse_open
    union all
    select trade_date, 'TPEx',
        lag(trade_date) over (order by trade_date)
    from {{ ref('stg_trading_calendar') }}
    where tpex_open
),

event_bounds as (
    -- 同一檔同一天可能有兩個事件，取最寬的區間
    select
        stock_id,
        event_date,
        min(least(reference_price, ex_rights_reference_price)) * 0.9    as lower_bound,
        max(greatest(reference_price, ex_rights_reference_price)) * 1.1 as upper_bound
    from {{ ref('stg_price_adjustments') }}
    group by stock_id, event_date
),

priced as (
    select
        p.trade_date,
        p.stock_id,
        p.market,
        p.close_price,
        p.adj_close_price,
        d.security_type,
        lag(p.trade_date) over (partition by p.stock_id order by p.trade_date) as prev_priced_date,
        lag(p.adj_close_price) over (partition by p.stock_id order by p.trade_date) as prev_adj_close,
        row_number() over (partition by p.stock_id, p.market order by p.trade_date) as nth_in_market,
        min(p.trade_date) over (partition by p.stock_id, p.market) as first_in_market
    from {{ ref('fact_daily_price') }} p
    join {{ ref('dim_stock') }} d on d.stock_sk = p.stock_sk
    where p.adj_close_price is not null
)

select
    p.trade_date,
    p.stock_id,
    p.prev_adj_close,
    p.adj_close_price,
    round((p.adj_close_price / p.prev_adj_close - 1) * 100, 2) as change_pct
from priced p
join market_days m on m.trade_date = p.trade_date and m.market = p.market
left join event_bounds e on e.stock_id = p.stock_id and e.event_date = p.trade_date
where p.prev_priced_date = m.prev_trading_day
  and (
      (e.stock_id is null and abs(p.adj_close_price / p.prev_adj_close - 1) > 0.1005)
      or (e.stock_id is not null and (p.close_price < e.lower_bound * 0.9995 or p.close_price > e.upper_bound * 1.0005))
  )
  and (p.security_type in ('股票', '創新板') or (p.security_type is null and p.stock_id ~ '^[0-9]{4}$'))
  and not (
      p.nth_in_market <= 5
      and p.first_in_market > (select min(trade_date) from {{ ref('fact_daily_price') }})
  )
