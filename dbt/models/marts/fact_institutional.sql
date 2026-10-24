-- 三大法人 fact：一天一檔一列，單位是股；net 正數為買超、負數為賣超
-- incremental：每個市場各自看 staging 的 fetched_at，以 (trade_date, market) 先刪後插
-- stock_sk 由「代號＋版本開始日」算出，新版本不會改到舊資料的 key，所以 incremental 是安全的

{{ config(
    materialized='incremental',
    unique_key=['trade_date', 'market'],
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['trade_date']}, {'columns': ['stock_sk']}]
) }}

select
    i.trade_date,
    d.stock_sk,
    i.stock_id,
    i.market,
    i.foreign_buy,
    i.foreign_sell,
    i.foreign_net,
    i.foreign_dealer_buy,
    i.foreign_dealer_sell,
    i.foreign_dealer_net,
    i.trust_buy,
    i.trust_sell,
    i.trust_net,
    i.dealer_self_buy,
    i.dealer_self_sell,
    i.dealer_self_net,
    i.dealer_hedge_buy,
    i.dealer_hedge_sell,
    i.dealer_hedge_net,
    i.dealer_net,
    i.total_net,
    i.fetched_at
from {{ ref('stg_institutional_trades') }} i
join {{ ref('dim_stock') }} d
    on d.stock_id = i.stock_id
   and i.trade_date >= d.valid_from
   and i.trade_date < d.valid_to
where i.trade_date >= '{{ var("history_start_date") }}'::date
{% if is_incremental() %}
  and i.fetched_at > (
      select coalesce(max(f.fetched_at), '-infinity') from {{ this }} f where f.market = i.market
  )
{% endif %}
