-- 股權分散表各級加總要等於合計（分級 17）；欄位或分級定義變了，這裡會抓到
--   人數：級距 1-15 加總 = 合計
--   股數：級距 1-15 加總 - 差異數調整（分級 16） = 合計
with by_stock as (
    select
        data_date,
        stock_id,
        sum(holders) filter (where level_type = 'bracket')    as bracket_holders,
        sum(shares) filter (where level_type = 'bracket')     as bracket_shares,
        coalesce(sum(shares) filter (where level_type = 'adjustment'), 0) as adjustment_shares,
        sum(holders) filter (where level_type = 'total')      as total_holders,
        sum(shares) filter (where level_type = 'total')       as total_shares
    from {{ ref('stg_shareholding_distribution') }}
    group by data_date, stock_id
)

select *
from by_stock
where bracket_holders <> total_holders
   or bracket_shares - adjustment_shares <> total_shares
