-- 缺漏交易日：回補起始日到最新一天之間，每個日曆日（含週末）上市、上櫃都要抓過
-- backfill 和每日 DAG 連休市日都會記一筆，所以交易日曆裡缺任何一天、或某個市場是 NULL，就代表那天漏抓
-- （個股因停止買賣而沒有行情是正常的，不在這裡檢查）
with expected as (
    select d::date as trade_date
    from generate_series(
        '{{ var("history_start_date") }}'::date,
        (select max(trade_date) from {{ ref('stg_trading_calendar') }}),
        interval '1 day'
    ) d
)

select e.trade_date, c.twse_open, c.tpex_open
from expected e
left join {{ ref('stg_trading_calendar') }} c on c.trade_date = e.trade_date
where c.trade_date is null
   or c.twse_open is null
   or c.tpex_open is null
