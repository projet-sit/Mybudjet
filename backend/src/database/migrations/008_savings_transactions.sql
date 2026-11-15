-- 008 - Opérations d'épargne (savings_deposit / savings_withdrawal)
-- L'épargne devient un type de transaction à part entière :
--   savings_deposit    : versement (sort du Reste vers l'épargne)
--   savings_withdrawal : retrait (retour de l'épargne vers le Reste)
-- Elles ne comptent JAMAIS comme des dépenses/revenus.

ALTER TABLE transactions ALTER COLUMN type TYPE VARCHAR(20);

-- Le nom du CHECK inline varie selon l'implémentation (transactions_type_check en Postgres,
-- autre auto-généré ailleurs) : on purge les deux par prudence (IF EXISTS).
ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_type_check;
ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_constraint_1;
ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_type_check1;
ALTER TABLE transactions ADD CONSTRAINT transactions_type_check
  CHECK (type IN ('expense', 'income', 'savings_deposit', 'savings_withdrawal'));

-- Recherche rapide des opérations d'épargne.
CREATE INDEX IF NOT EXISTS idx_tx_wallet_savings
  ON transactions (wallet_id, type)
  WHERE type LIKE 'savings_%';
