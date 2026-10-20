-- raw 層：除權息、減資的原始回應，四個來源各一張表，每個月份一筆
-- 這些 API 可以查一段期間，所以按月抓；period_end 是該月最後一天

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.twse_ex_rights (
    period_start DATE        PRIMARY KEY,           -- 查詢月份的第一天
    period_end   DATE        NOT NULL,              -- 查詢月份的最後一天
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.twse_ex_rights IS '證交所 exRight/TWT49U 除權除息計算結果表原始回應，每月一筆';

CREATE TABLE IF NOT EXISTS raw.twse_capital_reduction (
    period_start DATE        PRIMARY KEY,
    period_end   DATE        NOT NULL,
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.twse_capital_reduction IS '證交所 reducation/TWTAUU 減資恢復買賣參考價原始回應，每月一筆';

CREATE TABLE IF NOT EXISTS raw.tpex_ex_rights (
    period_start DATE        PRIMARY KEY,
    period_end   DATE        NOT NULL,
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tpex_ex_rights IS '櫃買中心 bulletin/exDailyQ 除權除息計算結果表原始回應，每月一筆';

CREATE TABLE IF NOT EXISTS raw.tpex_capital_reduction (
    period_start DATE        PRIMARY KEY,
    period_end   DATE        NOT NULL,
    stat         TEXT        NOT NULL,
    payload      JSONB       NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.tpex_capital_reduction IS '櫃買中心 bulletin/revivt 減資恢復買賣參考價原始回應，每月一筆';
