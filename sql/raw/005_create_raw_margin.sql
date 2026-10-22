-- raw 層：上市、上櫃融資融券餘額日報原始回應，每個日期一筆
-- 休市日：證交所 stat 不是 'OK' 且沒有 tables；櫃買中心 stat 仍是 'ok' 但 data 為空

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.twse_mi_margn (
    trade_date  DATE        PRIMARY KEY,
    stat        TEXT        NOT NULL,
    payload     JSONB       NOT NULL,
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.twse_mi_margn IS '證交所 marginTrading/MI_MARGN 融資融券餘額原始回應，每個日期一筆';

CREATE TABLE IF NOT EXISTS raw.tpex_margin_balance (
    trade_date  DATE        PRIMARY KEY,
    stat        TEXT        NOT NULL,
    payload     JSONB       NOT NULL,
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tpex_margin_balance IS '櫃買中心 margin/balance 融資融券餘額原始回應，每個日期一筆';
