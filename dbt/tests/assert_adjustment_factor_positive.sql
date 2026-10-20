-- 係數必須大於 0；也抓出明顯不合理的係數（20 倍以上），通常是欄位對錯或單位錯
select *
from {{ ref('stg_price_adjustments') }}
where factor <= 0 or factor > 20
