-- 010 : catégories personnalisées + période "data_epoch" + category_id sur opérations et budgets.
-- Additive, sans perte : les anciennes colonnes `category` (texte dénormalisé) sont conservées
-- et sont toujours remplies par le code applicatif (source de vérité = category_id).
-- Rollback manuel possible : DROP TABLE categories; ALTER TABLE ... DROP COLUMN category_id;
-- ALTER TABLE users DROP COLUMN data_epoch;

CREATE TABLE IF NOT EXISTS categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL pour les catégories système (par défaut) ; sinon propriétaire.
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(10) NOT NULL CHECK (type IN ('expense', 'income')),
  name VARCHAR(30) NOT NULL,
  normalized_name VARCHAR(30) NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT false,
  icon_key VARCHAR(30) NOT NULL DEFAULT 'label',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unicité par (propriétaire, type, nom normalisé) ; NULL côté système traité comme "tous".
CREATE UNIQUE INDEX IF NOT EXISTS categories_owner_type_name
  ON categories (COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid), type, normalized_name);

-- Catégories système par défaut (user_id NULL, is_default true). Noms normalisés : minuscule + sans accents.
INSERT INTO categories (user_id, type, name, normalized_name, is_default, icon_key) VALUES
  (NULL, 'expense', 'Alimentation', 'alimentation', true, 'restaurant'),
  (NULL, 'expense', 'Transport', 'transport', true, 'directions_car'),
  (NULL, 'expense', 'Logement', 'logement', true, 'home'),
  (NULL, 'expense', 'Santé', 'sante', true, 'favorite'),
  (NULL, 'expense', 'Études', 'etudes', true, 'school'),
  (NULL, 'expense', 'Communication', 'communication', true, 'chat_bubble'),
  (NULL, 'expense', 'Loisirs', 'loisirs', true, 'sports_esports'),
  (NULL, 'expense', 'Shopping', 'shopping', true, 'shopping_bag'),
  (NULL, 'expense', 'Abonnements', 'abonnements', true, 'subscriptions'),
  (NULL, 'expense', 'Famille', 'famille', true, 'family_restroom'),
  (NULL, 'expense', 'Autres', 'autres', true, 'more_horiz'),
  (NULL, 'income', 'Salaire', 'salaire', true, 'payments'),
  (NULL, 'income', 'Business', 'business', true, 'business_center'),
  (NULL, 'income', 'Cadeau', 'cadeau', true, 'card_giftcard'),
  (NULL, 'income', 'Bourse', 'bourse', true, 'school'),
  (NULL, 'income', 'Autres', 'autres', true, 'more_horiz')
ON CONFLICT DO NOTHING;

-- Incrémenté à chaque réinitialisation complète (POST /me/reset) : les autres appareils
-- détectent le changement et effacent leur cache local.
ALTER TABLE users ADD COLUMN IF NOT EXISTS data_epoch INTEGER NOT NULL DEFAULT 0;

-- Liens propriétaires (NULL tant que le backfill n'a pas tourné ; voir src/database/backfill_categories.js)
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS category_id UUID;
ALTER TABLE budgets ADD COLUMN IF NOT EXISTS category_id UUID;

ALTER TABLE transactions ADD CONSTRAINT transactions_category_fk
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;

ALTER TABLE budgets ADD CONSTRAINT budgets_category_fk
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;

-- Index de recherche par catégorie (filtre listes, stats, export)
CREATE INDEX IF NOT EXISTS idx_tx_category_id ON transactions (category_id);
CREATE INDEX IF NOT EXISTS idx_budgets_category_id ON budgets (category_id);
