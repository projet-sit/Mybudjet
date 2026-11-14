function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function toDateOnly(value) {
  if (!value) return null;
  if (typeof value === 'string') return value.slice(0, 10);
  return new Date(value).toISOString().slice(0, 10);
}

function monthEnd(dateValue) {
  const value = toDateOnly(dateValue) || todayIso();
  const [year, month] = value.split('-').map(Number);
  return new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
}

function daysBetween(from, to) {
  const start = Date.parse(`${toDateOnly(from)}T00:00:00Z`);
  const end = Date.parse(`${toDateOnly(to)}T00:00:00Z`);
  return Math.max(0, Math.round((end - start) / 86400000));
}

module.exports = { todayIso, toDateOnly, monthEnd, daysBetween };
