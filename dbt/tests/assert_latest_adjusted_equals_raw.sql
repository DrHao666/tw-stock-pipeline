-- 向後還原的定義：每檔股票最新一天的還原價要等於原始價。
-- 例外：行情還沒抓到、但除權息表已經公告的事件（事件日晚於最新行情日），這種股票先不檢查
with latest as (
    select stock_id, max(trade_date) as trade_date
    from {{ ref('stg_daily_quotes_adjusted') }}
    group by stock_id
)
select a.*
from {{ ref('stg_daily_quotes_adjusted') }} a
join latest l using (stock_id, trade_date)
where not exists (
        select 1
        from {{ ref('stg_price_adjustments') }} p
        where p.stock_id = a.stock_id
          and p.event_date > a.trade_date
    )
  and (a.adj_factor <> 1 or a.adj_close_price is distinct from round(a.close_price, 4))
