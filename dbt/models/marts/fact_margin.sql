-- 融資融券 fact：一天一檔一列，單位是張
-- incremental：每個市場各自看 staging 的 fetched_at，以 (trade_date, market) 先刪後插

{{ config(
    materialized='incremental',
    unique_key=['trade_date', 'market'],
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['trade_date']}, {'columns': ['stock_sk']}]
) }}

select
    m.trade_date,
    d.stock_sk,
    m.stock_id,
    m.market,
    m.margin_buy,
    m.margin_sell,
    m.margin_cash_repay,
    m.margin_prev_balance,
    m.margin_balance,
    m.margin_limit,
    m.short_buy,
    m.short_sell,
    m.short_stock_repay,
    m.short_prev_balance,
    m.short_balance,
    m.short_limit,
    m.margin_short_offset,
    m.note,
    m.fetched_at
from {{ ref('stg_margin_trades') }} m
join {{ ref('dim_stock') }} d
    on d.stock_id = m.stock_id
   and m.trade_date >= d.valid_from
   and m.trade_date < d.valid_to
where m.trade_date >= '{{ var("history_start_date") }}'::date
{% if is_incremental() %}
  and m.fetched_at > (
      select coalesce(max(f.fetched_at), '-infinity') from {{ this }} f where f.market = m.market
  )
{% endif %}
