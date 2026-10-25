-- 未來報酬：一天一檔一列，假設訊號日收盤後才知道訊號，「隔天開盤」買進，持有到第 5、第 20 個有成交日收盤賣出
-- 不用訊號日收盤價當買價：收盤後才確定的訊號不可能用當天收盤價買到（look-ahead bias）
-- 全部用還原價，除權息不會被算成報酬的漲跌；只收個股（普通股、創新板與已下市的 4 碼代號），ETF、債券不算
-- 最近的日子還沒有足夠的未來資料，報酬為 NULL

{{ config(pre_hook="set local work_mem = '256MB'") }}

with priced as (
    select
        p.trade_date,
        p.stock_sk,
        p.stock_id,
        p.adj_open_price,
        p.adj_close_price
    from {{ ref('fact_daily_price') }} p
    join {{ ref('dim_stock') }} d on d.stock_sk = p.stock_sk
    where p.adj_close_price is not null
      and p.adj_open_price is not null
      and (d.security_type in ('股票', '創新板') or (d.security_type is null and p.stock_id ~ '^[0-9]{4}$'))
),

leads as (
    select
        trade_date,
        stock_sk,
        stock_id,
        lead(adj_open_price, 1)   over w as entry_price,
        lead(adj_close_price, 5)  over w as exit_price_5d,
        lead(adj_close_price, 20) over w as exit_price_20d
    from priced
    window w as (partition by stock_id order by trade_date)
)

select
    trade_date,
    stock_sk,
    stock_id,
    entry_price,
    exit_price_5d / entry_price - 1  as return_5d,
    exit_price_20d / entry_price - 1 as return_20d
from leads
