-- K 線型態與趨勢狀態：一天一檔一列（和 indicators 一樣只含有成交的日子），沒有型態的日子也有一列，欄位為 false
-- 型態都用還原後的 OHLC，用 LAG 取前 1、2 個有成交日的 K 線比對
-- 門檻放在 config/signal_thresholds.csv（dbt seed），調參數不用改 SQL
-- 依賴的還原價會隨新事件改變，所以整張重建

-- 索引：Dashboard 查「某一天」所有訊號、查「某一檔」近期訊號
{{ config(
    pre_hook="set local work_mem = '256MB'",
    indexes=[{'columns': ['trade_date']}, {'columns': ['stock_id', 'trade_date']}]
) }}

with thresholds as (
    -- 設定檔是一列一個參數，轉成一列多欄方便 cross join
    select
        max(value) filter (where name = 'long_body_pct')            as long_body_pct,
        max(value) filter (where name = 'small_body_pct')           as small_body_pct,
        max(value) filter (where name = 'soldier_body_pct')         as soldier_body_pct,
        max(value) filter (where name = 'breakout_volume_multiple') as breakout_volume_multiple,
        max(value) filter (where name = 'range_width_pct')          as range_width_pct
    from {{ ref('signal_thresholds') }}
),

candles as (
    select
        i.trade_date,
        i.stock_sk,
        i.stock_id,
        i.market,
        p.adj_open_price  as o,
        p.adj_high_price  as h,
        p.adj_low_price   as l,
        p.adj_close_price as c,
        i.adj_volume,
        i.high_20,
        i.low_20,
        i.vol_ma20
    from {{ ref('indicators') }} i
    join {{ ref('fact_daily_price') }} p
        on p.trade_date = i.trade_date and p.stock_id = i.stock_id
),

with_history as (
    -- 後綴 1 = 前一個有成交日，2 = 前兩個
    select
        candles.*,
        lag(o) over w as o1, lag(h) over w as h1, lag(c) over w as c1,
        lag(o, 2) over w as o2, lag(c, 2) over w as c2,
        lag(high_20) over w  as prev_high_20,
        lag(low_20) over w   as prev_low_20,
        lag(vol_ma20) over w as prev_vol_ma20
    from candles
    window w as (partition by stock_id order by trade_date)
)

select
    k.trade_date,
    k.stock_sk,
    k.stock_id,
    k.market,

    -- 紅三兵：連三根夠長的紅 K，收盤一天比一天高，每根都開在前一根的實體內
    coalesce(
        k.c > k.o and k.c1 > k.o1 and k.c2 > k.o2
        and (k.c - k.o)   / k.o  >= t.soldier_body_pct
        and (k.c1 - k.o1) / k.o1 >= t.soldier_body_pct
        and (k.c2 - k.o2) / k.o2 >= t.soldier_body_pct
        and k.c > k.c1 and k.c1 > k.c2
        and k.o  between k.o1 and k.c1
        and k.o1 between k.o2 and k.c2,
        false
    ) as three_white_soldiers,

    -- 黃昏之星：第 1 天長紅；第 2 天小實體，整根實體跳空在第 1 天收盤之上；第 3 天黑 K，收盤跌破第 1 天實體的一半
    coalesce(
        k.c2 > k.o2 and (k.c2 - k.o2) / k.o2 >= t.long_body_pct
        and abs(k.c1 - k.o1) / k.o1 <= t.small_body_pct
        and least(k.o1, k.c1) > k.c2
        and k.c < k.o
        and k.c < (k.o2 + k.c2) / 2,
        false
    ) as evening_star,

    -- 烏雲蓋頂：第 1 天長紅；第 2 天開在第 1 天最高價之上，收黑 K，收盤跌破第 1 天實體一半、但仍在第 1 天開盤價之上
    coalesce(
        k.c1 > k.o1 and (k.c1 - k.o1) / k.o1 >= t.long_body_pct
        and k.o > k.h1
        and k.c < k.o
        and k.c < (k.o1 + k.c1) / 2
        and k.c > k.o1,
        false
    ) as dark_cloud_cover,

    -- 趨勢狀態：和「前一天」的 20 日高低點比（今天的 20 日高點已包含今天，不可能突破自己）
    case
        when k.c > k.prev_high_20
             and k.adj_volume >= t.breakout_volume_multiple * k.prev_vol_ma20 then 'breakout'
        when k.c < k.prev_low_20 then 'pullback'
        when (k.high_20 - k.low_20) / k.c <= t.range_width_pct then 'range'
        else 'none'
    end as trend_state
from with_history k
cross join thresholds t
