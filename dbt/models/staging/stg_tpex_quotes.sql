-- 上櫃（櫃買中心）每日收盤行情：把 raw JSON 攤開成「一天一檔一列」，並清理型別
-- 來源：raw.tpex_otc_quotes。休市日 stat 仍是 'ok' 但 data 為空陣列，攤開後自然不會產生資料列
-- incremental：只處理上次 build 之後新抓或重抓的日期（看 raw 的 fetched_at），
-- 以 trade_date 為單位先刪後插，重抓同一天不會產生重複

{{ config(
    materialized='incremental',
    unique_key='trade_date',
    incremental_strategy='delete+insert',
    indexes=[{'columns': ['trade_date']}]
) }}

with quote_tables as (
    select r.trade_date, r.fetched_at, t.tbl
    from {{ source('raw', 'tpex_otc_quotes') }} r
    cross join lateral jsonb_array_elements(r.payload -> 'tables') as t(tbl)
    {% if is_incremental() %}
    where r.fetched_at > (select coalesce(max(fetched_at), '-infinity') from {{ this }})
    {% endif %}
),

-- 欄位名稱夾著空白與 <br>（例如 '收盤 '、'最後買量<br>(張數)'），先正規化再和值配對。
-- 2010 年只有 15 欄、2026 年有 17 欄，用名稱取值就不受欄位數與順序影響
records as (
    select
        q.trade_date,
        q.fetched_at,
        (
            select jsonb_object_agg(
                regexp_replace(f.name, '<br>|\s', '', 'g'),
                d.row_values -> (f.pos - 1)::int
            )
            from jsonb_array_elements_text(q.tbl -> 'fields') with ordinality as f(name, pos)
        ) as rec
    from quote_tables q
    cross join lateral jsonb_array_elements(q.tbl -> 'data') as d(row_values)
),

cleaned as (
    select
        trade_date,
        fetched_at,
        trim(rec ->> '代號')                              as stock_id,
        trim(rec ->> '名稱')                              as stock_name,
        {{ clean_number("rec ->> '成交股數'") }}::bigint    as volume_shares,
        {{ clean_number("rec ->> '成交筆數'") }}::bigint    as trade_count,
        {{ clean_number("rec ->> '成交金額(元)'") }}::bigint as turnover,
        -- 沒成交時 2026 年是 '----'、2010 年是 '0.00'；價格不可能是 0，一律轉成 NULL
        nullif({{ clean_number("rec ->> '開盤'") }}, 0)    as open_price,
        nullif({{ clean_number("rec ->> '最高'") }}, 0)    as high_price,
        nullif({{ clean_number("rec ->> '最低'") }}, 0)    as low_price,
        nullif({{ clean_number("rec ->> '收盤'") }}, 0)    as close_price,
        -- 漲跌：'+0.05'、'- 0.19'（2010 年符號後有空格）、'0.00'、'---'（沒成交）、'除息' 等文字
        replace(trim(rec ->> '漲跌'), ' ', '')            as change_text
    from records
)

select
    trade_date,
    'TPEx'::text as market,
    stock_id,
    stock_name,
    volume_shares,
    trade_count,
    turnover,
    open_price,
    high_price,
    low_price,
    close_price,
    case
        when change_text ~ '^[+-]?[0-9.]+$' then change_text::numeric
    end as price_change,
    -- 漲跌欄是文字（除息、除權等）表示當天無法和前一日比較，對應上市的 'X'
    change_text !~ '^[+-]?[0-9.]+$' and change_text not in ('---', '----', '') as is_not_comparable,
    null::numeric as pe_ratio,  -- 櫃買中心這份報表沒有本益比
    fetched_at  -- raw 的抓取時間，incremental 用來判斷哪些日期要重算
from cleaned
