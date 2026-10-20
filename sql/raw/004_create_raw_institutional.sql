-- raw 層：上市、上櫃三大法人買賣超日報原始回應，每個日期一筆
-- 休市日：證交所 stat 不是 'OK' 且沒有 fields/data；櫃買中心 stat 仍是 'ok' 但 data 為空

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.twse_t86 (
    trade_date  DATE        PRIMARY KEY,
    stat        TEXT        NOT NULL,
    payload     JSONB       NOT NULL,
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.twse_t86 IS '證交所 fund/T86 三大法人買賣超日報原始回應，每個日期一筆';

CREATE TABLE IF NOT EXISTS raw.tpex_insti_daily (
    trade_date  DATE        PRIMARY KEY,
    stat        TEXT        NOT NULL,
    payload     JSONB       NOT NULL,
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tpex_insti_daily IS '櫃買中心 insti/dailyTrade 三大法人日交易資訊原始回應，每個日期一筆';
