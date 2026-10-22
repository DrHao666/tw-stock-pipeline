-- 上市、上櫃融資融券：一天一檔一列，單位都是張
-- 證交所融資、融券兩組欄位名稱重複（都叫「買進、賣出、前日餘額…」），兩邊一律依位置取值：
--   證交所 [2-7] 融資 買進/賣出/現金償還/前日餘額/今日餘額/限額  [8-13] 融券 買進/賣出/現券償還/前日餘額/今日餘額/限額  [14] 資券互抵 [15] 註記
--   櫃買中心 [2] 前資餘額 [3-5] 資買/資賣/現償 [6] 資餘額 [9] 資限額
--            [10] 前券餘額 [11-13] 券賣/券買/券償（賣在買前面，和證交所相反） [14] 券餘額 [17] 券限額 [18] 資券相抵 [19] 備註
-- 位置對錯會讓餘額恆等式不成立，由 assert_margin_balances_consistent 抓
-- incremental：每個市場各自看 raw 的 fetched_at，只處理新抓或重抓的日期；以 (trade_date, market) 先刪後插

{{ config(
    materialized='incremental',
    unique_key=['trade_date', 'market'],
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['trade_date']}]
) }}

with twse_rows as (
    select r.trade_date, r.fetched_at, d.v
    from {{ source('raw', 'twse_mi_margn') }} r
    -- tables[0] 是全市場統計，只取個股彙總那張；休市日沒有 tables
    cross join lateral jsonb_array_elements(coalesce(r.payload -> 'tables', '[]'::jsonb)) as t(tbl)
    cross join lateral jsonb_array_elements(coalesce(t.tbl -> 'data', '[]'::jsonb)) as d(v)
    where t.tbl ->> 'title' like '%融資融券彙總%'
    {% if is_incremental() %}
      and r.fetched_at > (select coalesce(max(fetched_at), '-infinity') from {{ this }} where market = 'TWSE')
    {% endif %}
),

twse as (
    select
        trade_date,
        'TWSE'::text as market,
        trim(v ->> 0) as stock_id,
        trim(v ->> 1) as stock_name,
        {{ clean_number("v ->> 2") }}::bigint  as margin_buy,
        {{ clean_number("v ->> 3") }}::bigint  as margin_sell,
        {{ clean_number("v ->> 4") }}::bigint  as margin_cash_repay,
        {{ clean_number("v ->> 5") }}::bigint  as margin_prev_balance,
        {{ clean_number("v ->> 6") }}::bigint  as margin_balance,
        {{ clean_number("v ->> 7") }}::bigint  as margin_limit,
        {{ clean_number("v ->> 8") }}::bigint  as short_buy,
        {{ clean_number("v ->> 9") }}::bigint  as short_sell,
        {{ clean_number("v ->> 10") }}::bigint as short_stock_repay,
        {{ clean_number("v ->> 11") }}::bigint as short_prev_balance,
        {{ clean_number("v ->> 12") }}::bigint as short_balance,
        {{ clean_number("v ->> 13") }}::bigint as short_limit,
        {{ clean_number("v ->> 14") }}::bigint as margin_short_offset,
        nullif(trim(v ->> 15), '') as note,
        fetched_at
    from twse_rows
),

tpex_rows as (
    select r.trade_date, r.fetched_at, d.v
    from {{ source('raw', 'tpex_margin_balance') }} r
    cross join lateral jsonb_array_elements(coalesce(r.payload -> 'tables' -> 0 -> 'data', '[]'::jsonb)) as d(v)
    {% if is_incremental() %}
    where r.fetched_at > (select coalesce(max(fetched_at), '-infinity') from {{ this }} where market = 'TPEx')
    {% endif %}
),

tpex as (
    select
        trade_date,
        'TPEx'::text as market,
        trim(v ->> 0) as stock_id,
        trim(v ->> 1) as stock_name,
        {{ clean_number("v ->> 3") }}::bigint  as margin_buy,
        {{ clean_number("v ->> 4") }}::bigint  as margin_sell,
        {{ clean_number("v ->> 5") }}::bigint  as margin_cash_repay,
        {{ clean_number("v ->> 2") }}::bigint  as margin_prev_balance,
        {{ clean_number("v ->> 6") }}::bigint  as margin_balance,
        {{ clean_number("v ->> 9") }}::bigint  as margin_limit,
        {{ clean_number("v ->> 12") }}::bigint as short_buy,
        {{ clean_number("v ->> 11") }}::bigint as short_sell,
        {{ clean_number("v ->> 13") }}::bigint as short_stock_repay,
        {{ clean_number("v ->> 10") }}::bigint as short_prev_balance,
        {{ clean_number("v ->> 14") }}::bigint as short_balance,
        {{ clean_number("v ->> 17") }}::bigint as short_limit,
        {{ clean_number("v ->> 18") }}::bigint as margin_short_offset,
        nullif(trim(v ->> 19), '') as note,
        fetched_at
    from tpex_rows
)

select * from twse
union all
select * from tpex
