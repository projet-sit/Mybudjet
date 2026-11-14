-- MYBUDGET 002 — Portefeuilles et historisation du montant initial

CREATE TABLE IF NOT EXISTS wallets (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name           VARCHAR(100) NOT NULL,
    initial_amount BIGINT NOT NULL DEFAULT 0 CHECK (initial_amount >= 0),
    start_date     DATE NOT NULL DEFAULT CURRENT_DATE,
    currency       VARCHAR(8) NOT NULL DEFAULT 'XOF',
    balance        BIGINT NOT NULL DEFAULT 0 CHECK (balance >= 0),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wallets_user ON wallets (user_id);

-- Historique de chaque modification du montant initial
CREATE TABLE IF NOT EXISTS initial_amount_history (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id  UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    old_value  BIGINT NOT NULL,
    new_value  BIGINT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_iah_wallet ON initial_amount_history (wallet_id);
