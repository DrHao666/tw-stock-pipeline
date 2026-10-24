-- 股權分散表 fact：一週一檔一個持股分級一列，單位是股；grain 和其他 fact 表不同
-- stock_sk 用資料日期對 dim_stock；興櫃等沒有行情的代號對不到，不收
-- incremental：只處理新抓或重抓的週，以 data_date 先刪後插

{{ config(
    materialized='incremental',
    unique_key='data_date',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['data_date']}, {'columns': ['stock_sk']}]
) }}

select
    s.data_date,
    d.stock_sk,
    s.stock_id,
    s.level,
    s.level_type,
    s.level_label,
    s.min_shares,
    s.max_shares,
    s.holders,
    s.shares,
    s.pct_of_custody,
    s.fetched_at
from {{ ref('stg_shareholding_distribution') }} s
join {{ ref('dim_stock') }} d
    on d.stock_id = s.stock_id
   and s.data_date >= d.valid_from
   and s.data_date < d.valid_to
{% if is_incremental() %}
where s.fetched_at > (select coalesce(max(fetched_at), '-infinity') from {{ this }})
{% endif %}
