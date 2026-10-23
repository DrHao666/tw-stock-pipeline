-- dim_stock 同一檔的版本要首尾相接：期間不重疊、沒有空檔，而且每個版本長度大於 0
select *
from (
    select
        stock_id,
        valid_from,
        valid_to,
        lead(valid_from) over (partition by stock_id order by valid_from) as next_valid_from
    from {{ ref('dim_stock') }}
) v
where valid_from >= valid_to
   or (next_valid_from is not null and next_valid_from <> valid_to)
