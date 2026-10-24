-- 每日行情 fact：一天一檔一列，原始價格與還原價格並列
-- 新的除權息／減資事件會改變過去所有日期的還原價，所以整張重建，不做 incremental
-- stock_sk：用交易日對到 dim_stock 當天有效的版本；對不到的代號不收

select
    q.trade_date,
    d.stock_sk,
    q.stock_id,
    q.market,
    q.volume_shares,
    q.trade_count,
    q.turnover,
    q.open_price,
    q.high_price,
    q.low_price,
    q.close_price,
    q.adj_factor,
    q.adj_open_price,
    q.adj_high_price,
    q.adj_low_price,
    q.adj_close_price
from {{ ref('stg_daily_quotes_adjusted') }} q
join {{ ref('dim_stock') }} d
    on d.stock_id = q.stock_id
   and q.trade_date >= d.valid_from
   and q.trade_date < d.valid_to
where q.trade_date >= '{{ var("history_start_date") }}'::date
