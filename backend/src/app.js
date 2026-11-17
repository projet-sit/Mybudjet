const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const morgan = require('morgan');
const env = require('./config/env');
const healthRoutes = require('./routes/health');
const authRoutes = require('./routes/auth');
const walletRoutes = require('./routes/wallets');
const transactionRoutes = require('./routes/transactions');
const statsRoutes = require('./routes/stats');
const budgetRoutes = require('./routes/budgets');
const periodRoutes = require('./routes/periods');
const goalRoutes = require('./routes/goals');
const categoryRoutes = require('./routes/categories');
const meRoutes = require('./routes/me');
const cielRoutes = require('./routes/cielRoutes');
const { notFoundHandler, errorHandler } = require('./middlewares/errorHandler');

const app = express();

app.set('trust proxy', 1);
app.use(helmet());
app.use(express.json({ limit: '256kb' }));
app.use(express.urlencoded({ extended: false }));

const corsOrigin = env.corsOrigin === '*' ? true : env.corsOrigin.split(',');
app.use(cors({ origin: corsOrigin }));

if (env.nodeEnv !== 'test') {
  app.use(morgan(env.nodeEnv === 'production' ? 'combined' : 'dev'));
}

const { requestLogger } = require('./middlewares/requestLogger');
app.use(requestLogger);

app.use(
  rateLimit({
    windowMs: env.rateLimit.windowMs,
    max: env.rateLimit.max,
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, error: { code: 'RATE_LIMITED', message: 'Trop de requêtes, réessaie plus tard' } },
  })
);

// Endpoints Ciel Phase 5 (Directs & API v1)
app.use('/', cielRoutes);
app.use('/api/v1', cielRoutes);

app.use('/api/v1/health', healthRoutes);
app.use('/api/v1/client-errors', require('./routes/clientErrors'));
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/me', meRoutes);
app.use('/api/v1/categories', categoryRoutes);
app.use('/api/v1/wallets', walletRoutes);
app.use('/api/v1/wallets', transactionRoutes);
app.use('/api/v1/wallets', statsRoutes);
app.use('/api/v1/wallets', budgetRoutes);
app.use('/api/v1/wallets', periodRoutes);
app.use('/api/v1/wallets', goalRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
