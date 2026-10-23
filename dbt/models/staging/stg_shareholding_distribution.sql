-- 集保股權分散表：一週、一檔、一個持股分級一列，單位是股（不是張）
-- 分級 1-15 是持股級距，16 是差異數調整（網頁版沒有這一級），17 是合計；級距定義在 seed tdcc_holding_levels
-- 開放資料欄位：[0] 資料日期 [1] 證券代號（後面補空白） [2] 持股分級 [3] 人數 [4] 股數 [5] 占集保庫存數比例%
-- incremental：只處理新抓或重抓的週，以 data_date 先刪後插

{{ config(
    materialized='incremental',
    unique_key='data_date',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['data_date']}, {'columns': ['stock_id']}]
) }}

with source_rows as (
    select r.data_date, r.fetched_at, d.v
    from {{ source('raw', 'tdcc_shareholding') }} r
    cross join lateral jsonb_array_elements(r.payload -> 'data') as d(v)
    {% if is_incremental() %}
    where r.fetched_at > (select coalesce(max(fetched_at), '-infinity') from {{ this }})
    {% endif %}
)

select
    s.data_date,
    trim(s.v ->> 1) as stock_id,
    (s.v ->> 2)::int as level,
    l.level_type,
    l.label as level_label,
    l.min_shares,
    l.max_shares,
    {{ clean_number("s.v ->> 3") }}::bigint as holders,
    {{ clean_number("s.v ->> 4") }}::bigint as shares,
    {{ clean_number("s.v ->> 5") }} as pct_of_custody,
    s.fetched_at
from source_rows s
left join {{ ref('tdcc_holding_levels') }} l on l.level = (s.v ->> 2)::int
