-- 回補起始日之後的每一筆行情，都要剛好對到 dim_stock 的一個有效版本；
-- 對不到（0）之後 fact 表 join 會掉資料，對到兩個以上會重複
select q.trade_date, q.stock_id, count(d.stock_sk) as matched_versions
from {{ ref('stg_daily_quotes') }} q
left join {{ ref('dim_stock') }} d
    on d.stock_id = q.stock_id
   and q.trade_date >= d.valid_from
   and q.trade_date < d.valid_to
where q.trade_date >= '{{ var("history_start_date") }}'::date
group by q.trade_date, q.stock_id
having count(d.stock_sk) <> 1
