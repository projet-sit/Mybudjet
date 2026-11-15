// Le Bénin est à UTC+1 toute l'année (pas d'heure d'été).
// Les débuts et fins de mois / jours se calculent à minuit HEURE LOCALE (Bénin),
// jamais en UTC décalé d'un jour.
const LOCAL_OFFSET_MS = 60 * 60 * 1000; // UTC+1, constant

function localNow() {
  return new Date(Date.now() + LOCAL_OFFSET_MS);
}

function localIsoParts() {
  const d = localNow();
  return {
    year: d.getUTCFullYear(),
    month: d.getUTCMonth() + 1,
    day: d.getUTCDate(),
  };
}

function todayIso() {
  return localNow().toISOString().slice(0, 10);
}

function toDateOnly(value) {
  if (!value) return null;
  if (typeof value === 'string') return value.slice(0, 10);
  return new Date(value).toISOString().slice(0, 10);
}

function monthEnd(dateValue) {
  const value = toDateOnly(dateValue) || todayIso();
  const [year, month] = value.split('-').map(Number);
  // Jour 0 du mois suivant = dernier jour du mois courant (arithmétique pure, pas de fuseau).
  return new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
}

function daysBetween(from, to) {
  const start = Date.parse(`${toDateOnly(from)}T00:00:00Z`);
  const end = Date.parse(`${toDateOnly(to)}T00:00:00Z`);
  return Math.max(0, Math.round((end - start) / 86400000));
}

/** Début du mois courant en heure locale (YYYY-MM-01). */
function localMonthStartIso() {
  const { year, month } = localIsoParts();
  return `${year}-${String(month).padStart(2, '0')}-01`;
}

/** Début de l'année courante en heure locale (YYYY-01-01). */
function localYearStartIso() {
  const { year } = localIsoParts();
  return `${year}-01-01`;
}

/** Il y a N jours en heure locale. */
function localDaysAgoIso(days) {
  const d = localNow();
  return new Date(d.getTime() - days * 86400000).toISOString().slice(0, 10);
}

module.exports = {
  todayIso,
  toDateOnly,
  monthEnd,
  daysBetween,
  localNow,
  localIsoParts,
  localMonthStartIso,
  localYearStartIso,
  localDaysAgoIso,
};
