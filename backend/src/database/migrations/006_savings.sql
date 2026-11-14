-- MYBUDGET 006 — Épargne dans le même compte
-- L'épargne est une réserve à l'intérieur du solde :
-- disponible = solde − épargne. Aucun compte supplémentaire.

ALTER TABLE wallets ADD COLUMN IF NOT EXISTS savings_amount BIGINT NOT NULL DEFAULT 0;

ALTER TABLE wallets DROP CONSTRAINT IF EXISTS wallets_savings_amount_check;
ALTER TABLE wallets ADD CONSTRAINT wallets_savings_amount_check CHECK (savings_amount >= 0);

-- Si le solde baisse (dépense, correction), l'épargne ne peut jamais le dépasser.
CREATE OR REPLACE FUNCTION clamp_wallet_savings() RETURNS trigger AS $$
BEGIN
  IF NEW.savings_amount > NEW.balance THEN
    NEW.savings_amount := GREATEST(0, NEW.balance);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_clamp_wallet_savings ON wallets;
CREATE TRIGGER trg_clamp_wallet_savings
BEFORE UPDATE ON wallets
FOR EACH ROW EXECUTE FUNCTION clamp_wallet_savings();
