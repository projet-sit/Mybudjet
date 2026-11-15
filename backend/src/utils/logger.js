// Logger minimal structuré (JSON lines) — lisible par Render et tout agrégateur.
// Chaque ligne : {"time","level","msg",...champs}

function write(level, msg, fields) {
  const entry = { time: new Date().toISOString(), level, msg, ...fields };
  const line = JSON.stringify(entry);
  if (level === 'error') {
    process.stderr.write(line + '\n');
  } else {
    process.stdout.write(line + '\n');
  }
}

module.exports = {
  info: (msg, fields) => write('info', msg, fields),
  warn: (msg, fields) => write('warn', msg, fields),
  error: (msg, fields) => write('error', msg, fields),
};
