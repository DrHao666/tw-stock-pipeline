-- 防止 look-ahead：買進價必須是「下一個有成交日」的還原開盤價，不能是當天的價格
with priced as (
    select
        trade_date,
        stock_id,
        lead(adj_open_price) over (partition by stock_id order by trade_date) as next_open
    from {{ ref('fact_daily_price') }}
    where adj_close_price is not null and adj_open_price is not null
)

select f.trade_date, f.stock_id, f.entry_price, p.next_open
from {{ ref('forward_returns') }} f
join priced p on p.trade_date = f.trade_date and p.stock_id = f.stock_id
where f.entry_price is distinct from p.next_open
