-- MYBUDGET 003 — Transactions financières (moteur du solde)

CREATE TABLE IF NOT EXISTS transactions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id      UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    type           VARCHAR(10) NOT NULL CHECK (type IN ('expense', 'income')),
    amount         BIGINT NOT NULL CHECK (amount > 0),
    category       VARCHAR(50) NOT NULL,
    description    VARCHAR(200),
    date           DATE NOT NULL,
    time           VARCHAR(5) NOT NULL,
    payment_method VARCHAR(30),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tx_wallet_date ON transactions (wallet_id, date DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tx_wallet_type ON transactions (wallet_id, type);
CREATE INDEX IF NOT EXISTS idx_tx_wallet_category ON transactions (wallet_id, category);

-- MYBUDGET 003 — Budgets par catégorie (Phase 9)
CREATE TABLE IF NOT EXISTS budgets (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id    UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    category     VARCHAR(50) NOT NULL,
    limit_amount BIGINT NOT NULL CHECK (limit_amount > 0),
    period       VARCHAR(20) NOT NULL DEFAULT 'monthly',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (wallet_id, category)
);
