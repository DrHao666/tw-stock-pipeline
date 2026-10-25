-- 技術指標：一天一檔一列，均線、均量、N 日高低點
-- 全部用還原價計算，除權息、減資、面額變更不會讓均線出現假的跳動
-- 只用有成交的日子：沒成交的日子沒有收盤價，不算進視窗，所以 MA5 = 最近 5 個「有成交」的交易日
-- 視窗內資料不足 N 天時給 NULL，不拿較少天數硬算（例如新上市第 3 天沒有 MA5）
-- 新的除權息事件會改變過去的還原價，所以和 fact_daily_price 一樣整張重建

with priced as (
    select
        trade_date,
        stock_sk,
        stock_id,
        market,
        adj_close_price,
        adj_high_price,
        adj_low_price,
        -- 成交量也要還原：面額 10 元變 1 元時股數變 10 倍，價格乘上係數、股數就除以係數
        volume_shares / adj_factor as adj_volume,
        -- 第幾個有成交的日子，用來判斷視窗內的資料夠不夠
        row_number() over (partition by stock_id order by trade_date) as nth_trade
    from {{ ref('fact_daily_price') }}
    where adj_close_price is not null
),

windowed as (
    select
        trade_date,
        stock_sk,
        stock_id,
        market,
        adj_close_price,
        adj_volume,
        nth_trade,
        avg(adj_close_price) over w5  as ma5_raw,
        avg(adj_close_price) over w20 as ma20_raw,
        avg(adj_close_price) over w60 as ma60_raw,
        avg(adj_volume)      over w5  as vol_ma5_raw,
        avg(adj_volume)      over w20 as vol_ma20_raw,
        max(adj_high_price)  over w20 as high_20_raw,
        min(adj_low_price)   over w20 as low_20_raw,
        max(adj_high_price)  over w60 as high_60_raw,
        min(adj_low_price)   over w60 as low_60_raw
    from priced
    window
        w5  as (partition by stock_id order by trade_date rows between 4 preceding and current row),
        w20 as (partition by stock_id order by trade_date rows between 19 preceding and current row),
        w60 as (partition by stock_id order by trade_date rows between 59 preceding and current row)
)

select
    trade_date,
    stock_sk,
    stock_id,
    market,
    adj_close_price,
    round(adj_volume)                                                as adj_volume,
    case when nth_trade >= 5  then round(ma5_raw, 4)  end            as ma5,
    case when nth_trade >= 20 then round(ma20_raw, 4) end            as ma20,
    case when nth_trade >= 60 then round(ma60_raw, 4) end            as ma60,
    case when nth_trade >= 5  then round(vol_ma5_raw)  end           as vol_ma5,
    case when nth_trade >= 20 then round(vol_ma20_raw) end           as vol_ma20,
    case when nth_trade >= 20 then high_20_raw end                   as high_20,
    case when nth_trade >= 20 then low_20_raw  end                   as low_20,
    case when nth_trade >= 60 then high_60_raw end                   as high_60,
    case when nth_trade >= 60 then low_60_raw  end                   as low_60
from windowed
