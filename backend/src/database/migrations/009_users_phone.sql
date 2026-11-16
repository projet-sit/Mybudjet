-- Numéro de téléphone comme identifiant de compte.
-- L'e-mail devient facultatif (réservé à la récupération de mot de passe) :
-- les anciens comptes e-mail restent acceptés pour la connexion (rétrocompatibilité).

ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);

-- e-mail facultatif sur les nouveaux comptes ; l'unicité (contrainte inline)
-- tolère les NULL multiples en PostgreSQL.
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- Un numéro = un compte. Index partiel : les comptes sans téléphone (legacy) ne gênent pas.
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_unique ON users (phone) WHERE phone IS NOT NULL;
