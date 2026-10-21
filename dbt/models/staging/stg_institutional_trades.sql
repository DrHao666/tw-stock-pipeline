-- 上市、上櫃三大法人買賣超：一天一檔一列，單位都是股
-- 證交所依欄位名稱取值；櫃買中心 7 組欄位名稱重複（都叫「買進股數、賣出股數、買賣超股數」），只能依位置取值：
--   [2-4] 外資及陸資(不含外資自營商)  [5-7] 外資自營商  [8-10] 外資合計  [11-13] 投信
--   [14-16] 自營商(自行買賣)  [17-19] 自營商(避險)  [20-22] 自營商合計  [23] 三大法人合計
-- incremental：每個市場各自看 raw 的 fetched_at，只處理新抓或重抓的日期；以 (trade_date, market) 先刪後插

{{ config(
    materialized='incremental',
    unique_key=['trade_date', 'market'],
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['trade_date']}]
) }}

with twse_days as (
    select trade_date, fetched_at, payload -> 'fields' as fields, payload -> 'data' as data
    from {{ source('raw', 'twse_t86') }}
    -- 休市日沒有 data
    where payload ? 'data'
    {% if is_incremental() %}
      and fetched_at > (select coalesce(max(fetched_at), '-infinity') from {{ this }} where market = 'TWSE')
    {% endif %}
),

-- materialized：讓每列的 rec 只組一次。不加的話 Postgres 會把 CTE 展開，
-- 下面每個 rec ->> '欄位' 都重跑一次 jsonb_object_agg（約 36 次／列），實測慢 30 倍
twse_records as materialized (
    select
        t.trade_date,
        t.fetched_at,
        (
            select jsonb_object_agg(regexp_replace(f.name, '\s', '', 'g'), d.row_values -> (f.pos - 1)::int)
            from jsonb_array_elements_text(t.fields) with ordinality as f(name, pos)
        ) as rec
    from twse_days t
    cross join lateral jsonb_array_elements(t.data) as d(row_values)
),

twse as (
    select
        trade_date,
        'TWSE'::text as market,
        trim(rec ->> '證券代號') as stock_id,
        trim(rec ->> '證券名稱') as stock_name,
        {{ clean_number("rec ->> '外陸資買進股數(不含外資自營商)'") }}::bigint   as foreign_buy,
        {{ clean_number("rec ->> '外陸資賣出股數(不含外資自營商)'") }}::bigint   as foreign_sell,
        {{ clean_number("rec ->> '外陸資買賣超股數(不含外資自營商)'") }}::bigint as foreign_net,
        {{ clean_number("rec ->> '外資自營商買進股數'") }}::bigint              as foreign_dealer_buy,
        {{ clean_number("rec ->> '外資自營商賣出股數'") }}::bigint              as foreign_dealer_sell,
        {{ clean_number("rec ->> '外資自營商買賣超股數'") }}::bigint            as foreign_dealer_net,
        {{ clean_number("rec ->> '投信買進股數'") }}::bigint                    as trust_buy,
        {{ clean_number("rec ->> '投信賣出股數'") }}::bigint                    as trust_sell,
        {{ clean_number("rec ->> '投信買賣超股數'") }}::bigint                  as trust_net,
        {{ clean_number("rec ->> '自營商買進股數(自行買賣)'") }}::bigint        as dealer_self_buy,
        {{ clean_number("rec ->> '自營商賣出股數(自行買賣)'") }}::bigint        as dealer_self_sell,
        {{ clean_number("rec ->> '自營商買賣超股數(自行買賣)'") }}::bigint      as dealer_self_net,
        {{ clean_number("rec ->> '自營商買進股數(避險)'") }}::bigint            as dealer_hedge_buy,
        {{ clean_number("rec ->> '自營商賣出股數(避險)'") }}::bigint            as dealer_hedge_sell,
        {{ clean_number("rec ->> '自營商買賣超股數(避險)'") }}::bigint          as dealer_hedge_net,
        {{ clean_number("rec ->> '自營商買賣超股數'") }}::bigint                as dealer_net,
        {{ clean_number("rec ->> '三大法人買賣超股數'") }}::bigint              as total_net,
        fetched_at
    from twse_records
),

tpex_rows as (
    select r.trade_date, r.fetched_at, d.v
    from {{ source('raw', 'tpex_insti_daily') }} r
    cross join lateral jsonb_array_elements(r.payload -> 'tables') as t(tbl)
    cross join lateral jsonb_array_elements(coalesce(t.tbl -> 'data', '[]'::jsonb)) as d(v)
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
        {{ clean_number("v ->> 2") }}::bigint  as foreign_buy,
        {{ clean_number("v ->> 3") }}::bigint  as foreign_sell,
        {{ clean_number("v ->> 4") }}::bigint  as foreign_net,
        {{ clean_number("v ->> 5") }}::bigint  as foreign_dealer_buy,
        {{ clean_number("v ->> 6") }}::bigint  as foreign_dealer_sell,
        {{ clean_number("v ->> 7") }}::bigint  as foreign_dealer_net,
        -- [8-10] 外資合計 = 前兩組相加，不另外存
        {{ clean_number("v ->> 11") }}::bigint as trust_buy,
        {{ clean_number("v ->> 12") }}::bigint as trust_sell,
        {{ clean_number("v ->> 13") }}::bigint as trust_net,
        {{ clean_number("v ->> 14") }}::bigint as dealer_self_buy,
        {{ clean_number("v ->> 15") }}::bigint as dealer_self_sell,
        {{ clean_number("v ->> 16") }}::bigint as dealer_self_net,
        {{ clean_number("v ->> 17") }}::bigint as dealer_hedge_buy,
        {{ clean_number("v ->> 18") }}::bigint as dealer_hedge_sell,
        {{ clean_number("v ->> 19") }}::bigint as dealer_hedge_net,
        {{ clean_number("v ->> 22") }}::bigint as dealer_net,
        {{ clean_number("v ->> 23") }}::bigint as total_net,
        fetched_at
    from tpex_rows
)

select * from twse
union all
select * from tpex
