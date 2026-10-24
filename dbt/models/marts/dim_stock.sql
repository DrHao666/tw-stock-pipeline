-- 股票維度表（SCD Type 2）：一檔一個版本一列，名稱、市場、證券類別、產業別任一項變了就開新版本
-- ISIN 清單只有「目前」，歷史從每日行情推：
--   1. 回補起始日之後每檔每個交易日，名稱、市場取自當天行情；證券類別、產業別取當天以前最近一份 ISIN 快照
--      （快照開始抓之前的日期用第一份快照補，所以早期的產業別是「目前」的產業別；
--       已下市的股票如果曾出現在快照裡，會沿用最後一次看到的類別與產業別）
--   2. gaps-and-islands：屬性和前一個交易日不同就開新版本，連續相同的日期合成一個版本
-- 期間是左閉右開 [valid_from, valid_to)；下一個版本的 valid_from 就是上一個的 valid_to，不會有空檔
-- 期間邊界會延伸到沒有行情的日子，讓融資融券等 fact 表也對得到版本：
--   第一版從回補起始日開始；已下市股票的最後一版到融資融券／三大法人最後出現那天的隔天為止
-- 3 年內下市的股票 ISIN 查不到：仍保留，is_delisted = true

-- 要排序約 160 萬筆行情；預設 work_mem（4MB）會把排序寫到暫存檔，在 Windows 的 Docker Desktop 上特別慢
-- set local 只在這個 model 的交易內有效，不影響其他 model
{{ config(
    materialized='table',
    indexes=[{'columns': ['stock_id']}],
    pre_hook="set local work_mem = '256MB'"
) }}

with quotes as (
    select trade_date, stock_id, stock_name, market
    from {{ ref('stg_daily_quotes') }}
    where trade_date >= '{{ var("history_start_date") }}'::date
),

-- 先把每日 ISIN 快照壓成「每檔的屬性區間」：證券類別、產業別連續相同的快照合成一段
-- 這樣每筆行情只要用 stock_id 等值 join 到該檔的少數幾段，不會隨快照天數變多而變慢
snapshot_flagged as (
    select
        stock_id,
        snapshot_date,
        security_type,
        industry,
        case
            when (security_type, industry) is not distinct from
                 (lag(security_type) over w, lag(industry) over w)
            then 0 else 1
        end as is_new_segment
    from {{ ref('stg_securities') }}
    window w as (partition by stock_id order by snapshot_date)
),

snapshot_segments as (
    select stock_id, security_type, industry, min(snapshot_date) as segment_start
    from (
        select *, sum(is_new_segment) over (partition by stock_id order by snapshot_date) as segment_no
        from snapshot_flagged
    ) s
    group by stock_id, segment_no, security_type, industry
),

-- 區間左閉右開；第一段往前延伸到最早（快照開始抓之前的日期用第一份快照補），最後一段延伸到最晚
attribute_ranges as (
    select
        stock_id,
        security_type,
        industry,
        case when row_number() over w = 1 then '-infinity'::date else segment_start end as range_start,
        coalesce(lead(segment_start) over w, 'infinity'::date) as range_end
    from snapshot_segments
    window w as (partition by stock_id order by segment_start)
),

daily_attributes as (
    select
        q.trade_date,
        q.stock_id,
        q.stock_name,
        q.market,
        a.security_type,
        a.industry
    from quotes q
    left join attribute_ranges a
        on a.stock_id = q.stock_id
       and q.trade_date >= a.range_start
       and q.trade_date < a.range_end
),

flagged as (
    select
        *,
        case
            when (stock_name, market, security_type, industry) is not distinct from
                 (lag(stock_name) over w, lag(market) over w, lag(security_type) over w, lag(industry) over w)
            then 0 else 1
        end as is_new_version
    from daily_attributes
    window w as (partition by stock_id order by trade_date)
),

numbered as (
    select *, sum(is_new_version) over (partition by stock_id order by trade_date) as version_no
    from flagged
),

versions as (
    select
        stock_id,
        version_no,
        stock_name,
        market,
        security_type,
        industry,
        min(trade_date) as valid_from,
        max(trade_date) as last_trade_date
    from numbered
    group by stock_id, version_no, stock_name, market, security_type, industry
),

-- 最新一份快照：判斷是否已下市，並帶出不分版本的屬性（ISIN、上市日、CFI）
latest_snapshot as (
    select *
    from {{ ref('stg_securities') }}
    where snapshot_date = (select max(snapshot_date) from {{ ref('stg_securities') }})
),

-- 已下市股票在最後一筆成交之後，融資融券、三大法人表可能還會列一段時間（停止買賣到正式下市）
last_seen as (
    select stock_id, max(trade_date) as last_seen_date
    from (
        select stock_id, trade_date from {{ ref('stg_margin_trades') }}
        union all
        select stock_id, trade_date from {{ ref('stg_institutional_trades') }}
    ) s
    group by stock_id
),

final as (
    select
        v.stock_id,
        v.version_no,
        v.stock_name,
        v.market,
        v.security_type,
        v.industry,
        l.isin_code,
        l.cfi_code,
        l.listing_date,
        -- 還沒抓過任何 ISIN 快照時無從判斷，一律當作仍掛牌
        l.stock_id is null and exists (select 1 from latest_snapshot) as is_delisted,
        v.valid_from as first_trade_date,
        -- 第一個版本往前延伸到回補起始日：新上市前一兩天、或回補初期停止買賣時，融資融券表已經有資料但還沒有行情
        case
            when v.version_no = 1 then least(v.valid_from, '{{ var("history_start_date") }}'::date)
            else v.valid_from
        end as valid_from,
        coalesce(
            lead(v.valid_from) over (partition by v.stock_id order by v.valid_from),
            -- 已下市：最後一版延到任何每日資料最後出現那天的隔天
            case when l.stock_id is null and exists (select 1 from latest_snapshot)
                 then greatest(v.last_trade_date, s.last_seen_date) + 1 else '9999-12-31'::date end
        ) as valid_to
    from versions v
    left join latest_snapshot l on l.stock_id = v.stock_id
    left join last_seen s on s.stock_id = v.stock_id
)

select
    -- 代理鍵用版本「實際第一筆成交日」算，不受上面的期間延伸影響，已經寫進 fact 表的 key 才不會變
    md5(stock_id || '|' || first_trade_date) as stock_sk,
    stock_id,
    version_no,
    stock_name,
    market,
    security_type,
    industry,
    isin_code,
    cfi_code,
    listing_date,
    is_delisted,
    valid_from,
    valid_to,
    valid_to = '9999-12-31'::date as is_current
from final
