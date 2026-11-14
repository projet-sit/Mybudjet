-- MYBUDGET 005 — Retour à un seul espace (suppression des comptes multiples)

DROP INDEX IF EXISTS idx_wallets_user_type;

ALTER TABLE wallets DROP COLUMN IF EXISTS provider;
ALTER TABLE wallets DROP COLUMN IF EXISTS type;
