-- 證交所 ISIN 清單：每份快照、每檔證券一列（不含權證，ingestion 已排除）
-- payload 欄位：[0] 證券類別 [1] 代號 [2] 名稱 [3] ISIN [4] 上市日（上櫃股票是上櫃日） [5] 市場別 [6] 產業別 [7] CFICode [8] 備註
-- 產業別只有普通股、創新板有值，其他類別為 NULL
-- incremental：只處理新抓或重抓的快照，以 snapshot_date 先刪後插

{{ config(
    materialized='incremental',
    unique_key='snapshot_date',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['snapshot_date']}]
) }}

with source_rows as (
    select r.snapshot_date, r.fetched_at, d.v
    from {{ source('raw', 'twse_isin') }} r
    cross join lateral jsonb_array_elements(r.payload -> 'data') as d(v)
    {% if is_incremental() %}
    where r.fetched_at > (select coalesce(max(fetched_at), '-infinity') from {{ this }})
    {% endif %}
)

select
    snapshot_date,
    v ->> 1 as stock_id,
    v ->> 2 as stock_name,
    v ->> 3 as isin_code,
    -- 市場別有「上市」「上市臺灣創新板」「上櫃」
    case when v ->> 5 like '上市%' then 'TWSE' when v ->> 5 = '上櫃' then 'TPEx' end as market,
    v ->> 5 as market_label,
    v ->> 0 as security_type,
    nullif(v ->> 6, '') as industry,
    nullif(v ->> 7, '') as cfi_code,
    to_date(nullif(v ->> 4, ''), 'YYYY/MM/DD') as listing_date,
    nullif(v ->> 8, '') as note,
    fetched_at
from source_rows
