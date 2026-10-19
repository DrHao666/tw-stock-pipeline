-- 有成交的價格一定要大於 0；收盤價 0 代表沒成交卻被當成價格，是清理漏掉的情況
-- dbt 的 singular test：查出任何一列就算失敗
select trade_date, market, stock_id, open_price, high_price, low_price, close_price
from {{ ref('stg_twse_quotes') }}
where open_price <= 0 or high_price <= 0 or low_price <= 0 or close_price <= 0
   or high_price < low_price
