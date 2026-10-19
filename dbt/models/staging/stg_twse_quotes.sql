-- 上市（證交所）每日收盤行情：把 raw JSON 攤開成「一天一檔一列」，並清理型別
-- 來源：raw.twse_mi_index，只取 stat = 'OK' 的交易日

with trading_days as (
    select trade_date, payload
    from {{ source('raw', 'twse_mi_index') }}
    where stat = 'OK'
),

-- 一個回應裡有好幾張表，用標題找出個股行情那張（舊年份有空表佔位，不能用位置）
quote_tables as (
    select d.trade_date, t.tbl
    from trading_days d
    cross join lateral jsonb_array_elements(d.payload -> 'tables') as t(tbl)
    where t.tbl ->> 'title' like '%每日收盤行情%'
),

-- 每一列 data 是陣列；把 fields 和值配對成 {"證券代號": "2330", ...}，之後用欄位名稱取值
records as (
    select
        q.trade_date,
        (
            select jsonb_object_agg(trim(f.name), r.row_values -> (f.pos - 1)::int)
            from jsonb_array_elements_text(q.tbl -> 'fields') with ordinality as f(name, pos)
        ) as rec
    from quote_tables q
    cross join lateral jsonb_array_elements(q.tbl -> 'data') as r(row_values)
),

cleaned as (
    select
        trade_date,
        trim(rec ->> '證券代號')                       as stock_id,
        trim(rec ->> '證券名稱')                       as stock_name,
        {{ clean_number("rec ->> '成交股數'") }}::bigint as volume_shares,
        {{ clean_number("rec ->> '成交筆數'") }}::bigint as trade_count,
        {{ clean_number("rec ->> '成交金額'") }}::bigint as turnover,
        {{ clean_number("rec ->> '開盤價'") }}           as open_price,
        {{ clean_number("rec ->> '最高價'") }}           as high_price,
        {{ clean_number("rec ->> '最低價'") }}           as low_price,
        {{ clean_number("rec ->> '收盤價'") }}           as close_price,
        -- 漲跌符號是 HTML（<p style= color:red>+</p>），去掉標籤只留 + / - / X / 空白
        trim(regexp_replace(rec ->> '漲跌(+/-)', '<[^>]*>', '', 'g')) as change_sign,
        {{ clean_number("rec ->> '漲跌價差'") }}         as change_abs,
        {{ clean_number("rec ->> '本益比'") }}           as pe_ratio
    from records
)

select
    trade_date,
    'TWSE'::text as market,
    stock_id,
    stock_name,
    volume_shares,
    trade_count,
    turnover,
    open_price,
    high_price,
    low_price,
    close_price,
    -- 有方向的漲跌：X（不比價，如除權息、新上市）無法和前一日比較，記為 NULL
    case change_sign
        when '+' then change_abs
        when '-' then -change_abs
        when ''  then 0
    end as price_change,
    change_sign = 'X' as is_not_comparable,
    -- 本益比 0 代表不適用（ETF、虧損公司），轉成 NULL 避免被當成真的 0 倍
    nullif(pe_ratio, 0) as pe_ratio
from cleaned
