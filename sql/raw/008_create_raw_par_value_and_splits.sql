-- raw 層：變更面額、ETF 分割／反分割的恢復買賣參考價原始回應，每個來源一張表，每個月份一筆
-- 格式和 003 的除權息、減資表相同，由 ingestion/corporate_actions.py 一起抓

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.twse_par_value_change (
    period_start DATE        PRIMARY KEY,           -- 查詢月份的第一天
    period_end   DATE        NOT NULL,              -- 查詢月份的最後一天
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.twse_par_value_change IS '證交所 change/TWTB8U 變更股票面額恢復買賣參考價原始回應，每月一筆';

CREATE TABLE IF NOT EXISTS raw.twse_etf_split (
    period_start DATE        PRIMARY KEY,
    period_end   DATE        NOT NULL,
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.twse_etf_split IS '證交所 split/TWTCAU ETF 分割（反分割）恢復買賣參考價原始回應，分割與反分割在同一張表，每月一筆';

CREATE TABLE IF NOT EXISTS raw.tpex_par_value_change (
    period_start DATE        PRIMARY KEY,
    period_end   DATE        NOT NULL,
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tpex_par_value_change IS '櫃買中心 bulletin/pvChgRslt 變更股票面額恢復買賣參考價原始回應，每月一筆';

CREATE TABLE IF NOT EXISTS raw.tpex_etf_split (
    period_start DATE        PRIMARY KEY,
    period_end   DATE        NOT NULL,
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tpex_etf_split IS '櫃買中心 bulletin/etfSplitRslt ETF 分割恢復買賣參考價原始回應，每月一筆';

CREATE TABLE IF NOT EXISTS raw.tpex_etf_reverse_split (
    period_start DATE        PRIMARY KEY,
    period_end   DATE        NOT NULL,
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tpex_etf_reverse_split IS '櫃買中心 bulletin/etfRvsRslt ETF 反分割恢復買賣參考價原始回應，每月一筆';
