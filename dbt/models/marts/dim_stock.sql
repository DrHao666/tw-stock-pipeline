-- 股票維度表（SCD Type 2）：一檔一個版本一列，名稱、市場、證券類別、產業別任一項變了就開新版本
-- ISIN 清單只有「目前」，歷史從每日行情推：
--   1. 回補起始日之後每檔每個交易日，名稱、市場取自當天行情；證券類別、產業別取當天以前最近一份 ISIN 快照
--      （快照開始抓之前的日期用第一份快照補，所以早期的產業別是「目前」的產業別）
--   2. gaps-and-islands：屬性和前一個交易日不同就開新版本，連續相同的日期合成一個版本
-- 期間是左閉右開 [valid_from, valid_to)；下一個版本的 valid_from 就是上一個的 valid_to，不會有空檔
-- 3 年內下市的股票 ISIN 查不到：仍保留，證券類別、產業別為 NULL，is_delisted = true，最後一版到最後交易日隔天為止

{{ config(materialized='table', indexes=[{'columns': ['stock_id']}]) }}

with quotes as (
    select trade_date, stock_id, stock_name, market
    from {{ ref('stg_daily_quotes') }}
    where trade_date >= '{{ var("history_start_date") }}'::date
),

-- 每份快照涵蓋的期間：[這份的日期, 下一份的日期)；第一份往前延伸到最早
snapshot_ranges as (
    select
        snapshot_date,
        case when snapshot_date = min(snapshot_date) over () then '-infinity'::date else snapshot_date end as range_start,
        coalesce(lead(snapshot_date) over (order by snapshot_date), 'infinity'::date) as range_end
    from (select distinct snapshot_date from {{ ref('stg_securities') }}) s
),

daily_attributes as (
    select
        q.trade_date,
        q.stock_id,
        q.stock_name,
        q.market,
        s.security_type,
        s.industry
    from quotes q
    left join snapshot_ranges r
        on q.trade_date >= r.range_start and q.trade_date < r.range_end
    left join {{ ref('stg_securities') }} s
        on s.snapshot_date = r.snapshot_date and s.stock_id = q.stock_id
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
        v.valid_from,
        coalesce(
            lead(v.valid_from) over (partition by v.stock_id order by v.valid_from),
            case when l.stock_id is null and exists (select 1 from latest_snapshot)
                 then v.last_trade_date + 1 else '9999-12-31'::date end
        ) as valid_to
    from versions v
    left join latest_snapshot l on l.stock_id = v.stock_id
)

select
    md5(stock_id || '|' || valid_from) as stock_sk,
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
