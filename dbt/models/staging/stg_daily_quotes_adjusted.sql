-- 還原權值後的每日行情（向後還原）：最新價格不變，越早的價格依之後發生的事件往下調
-- 某天的還原係數 = 該股票在那天「之後」所有事件係數的乘積；事件當天的價格已經是事件後的價格，不再調整
-- 資料量大（每天約 2,400 檔），做成 table，避免每次查詢、測試都重算

{{ config(materialized='table') }}

with daily_factors as (
    -- 同一檔同一天若有兩個事件（例如減資和除權同日），先合併成一個係數
    select stock_id, event_date, exp(sum(ln(factor))) as factor
    from {{ ref('stg_price_adjustments') }}
    group by stock_id, event_date
),

cumulative as (
    -- 由新到舊累乘：某事件的 cum_factor = 它和之後所有事件係數的乘積
    select
        stock_id,
        event_date,
        exp(sum(ln(factor)) over (
            partition by stock_id order by event_date desc
            rows between unbounded preceding and current row
        )) as cum_factor
    from daily_factors
),

intervals as (
    -- 每個事件管一段期間：[前一個事件日, 這個事件日)，期間內的價格都乘上這個事件的 cum_factor
    select
        stock_id,
        lag(event_date) over (partition by stock_id order by event_date) as valid_from,
        event_date as valid_to,
        cum_factor
    from cumulative
)

select
    q.trade_date,
    q.market,
    q.stock_id,
    q.stock_name,
    q.volume_shares,
    q.open_price,
    q.high_price,
    q.low_price,
    q.close_price,
    coalesce(i.cum_factor, 1)                          as adj_factor,
    round(q.open_price  * coalesce(i.cum_factor, 1), 4) as adj_open_price,
    round(q.high_price  * coalesce(i.cum_factor, 1), 4) as adj_high_price,
    round(q.low_price   * coalesce(i.cum_factor, 1), 4) as adj_low_price,
    round(q.close_price * coalesce(i.cum_factor, 1), 4) as adj_close_price
from {{ ref('stg_daily_quotes') }} q
left join intervals i
    on  i.stock_id = q.stock_id
    and q.trade_date < i.valid_to
    and (i.valid_from is null or q.trade_date >= i.valid_from)
