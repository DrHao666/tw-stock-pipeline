-- 日期維度：一天一列，從回補起始日到明年底；is_trading_day 取自交易日曆，還沒抓過的日期（含未來）為 NULL

select
    d::date as date_day,
    extract(year from d)::int as year,
    extract(year from d)::int - 1911 as roc_year,
    extract(quarter from d)::int as quarter,
    extract(month from d)::int as month,
    extract(day from d)::int as day_of_month,
    extract(isoyear from d)::int as iso_year,
    extract(week from d)::int as iso_week,
    extract(isodow from d)::int as day_of_week,   -- 1 = 星期一 … 7 = 星期日
    extract(isodow from d) >= 6 as is_weekend,
    c.is_trading_day
from generate_series(
    '{{ var("history_start_date") }}'::date,
    (date_trunc('year', current_date) + interval '2 years - 1 day')::date,
    interval '1 day'
) as d
left join {{ ref('stg_trading_calendar') }} c on c.trade_date = d::date
