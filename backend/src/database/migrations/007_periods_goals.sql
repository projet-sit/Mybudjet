-- MYBUDGET 007 - Périodes mensuelles et objectifs d'épargne

-- Une période budgétaire par mois (archive du mois précédent, sans perte d'historique).
CREATE TABLE IF NOT EXISTS periods (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id  UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date   DATE NOT NULL,
    status     VARCHAR(10) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
    snapshot   JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at  TIMESTAMPTZ,
    CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_periods_wallet ON periods (wallet_id, start_date DESC);

-- Chaque transaction appartient à une période (les anciennes sont rattachées ci-dessous).
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS period_id UUID REFERENCES periods(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_tx_wallet_period ON transactions (wallet_id, period_id);

-- Période active initiale pour chaque portefeuille existant.
INSERT INTO periods (user_id, wallet_id, start_date, end_date, status)
SELECT w.user_id,
       w.id,
       LEAST(COALESCE(MIN(t.date), w.start_date), w.start_date),
       (date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::date,
       'active'
FROM wallets w
LEFT JOIN transactions t ON t.wallet_id = w.id
WHERE NOT EXISTS (
    SELECT 1 FROM periods p WHERE p.wallet_id = w.id AND p.status = 'active'
)
GROUP BY w.id, w.user_id, w.start_date;

-- Une seule période active par portefeuille.
CREATE UNIQUE INDEX IF NOT EXISTS uq_periods_one_active
    ON periods (wallet_id) WHERE status = 'active';

UPDATE transactions t
SET period_id = p.id
FROM periods p
WHERE p.wallet_id = t.wallet_id
  AND p.status = 'active'
  AND t.period_id IS NULL;

-- Objectifs d'épargne : l'argent reste dans le portefeuille (réserve "savings").
CREATE TABLE IF NOT EXISTS goals (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id     UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    name          VARCHAR(100) NOT NULL,
    target_amount BIGINT NOT NULL CHECK (target_amount > 0),
    saved_amount  BIGINT NOT NULL DEFAULT 0 CHECK (saved_amount >= 0),
    deadline      DATE,
    status        VARCHAR(12) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (saved_amount <= target_amount)
);

CREATE INDEX IF NOT EXISTS idx_goals_wallet ON goals (wallet_id, created_at ASC);
