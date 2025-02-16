require('dotenv').config(); // Load environment variables
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { Pool } = require('pg');
const { parse } = require('pg-connection-string');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');

if (!process.env.DATABASE_URL) {
  console.error('❌ Error: DATABASE_URL is missing in Railway environment variables!');
  process.exit(1);
}

const databaseUrl = process.env.DATABASE_URL.includes('?')
  ? process.env.DATABASE_URL
  : `${process.env.DATABASE_URL}?sslmode=require`;

const connection = parse(databaseUrl);

const pool = new Pool({
  ...connection,
  ssl: { rejectUnauthorized: false },
  keepAlive: true,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 10000,
  max: process.env.DB_MAX_CONNECTIONS || 5,
});

pool.on('error', (err) => {
  console.error('❌ Database error:', err.message);
  setTimeout(() => {
    console.log('ℹ️ Retrying database connection...');
  }, 5000);
});

const app = express();
app.use(helmet());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
}));

app.get('/', (req, res) => {
  res.json({ message: '🚀 Server is running on Railway!', status: 'healthy' });
});

app.get('/api/maps-key', (req, res) => {
  res.json({ apiKey: process.env.GOOGLE_MAPS_API_KEY });
});

app.use('/auth', (req, res, next) => {
  req.db = pool;
  next();
}, createAuthRoutes(pool));

app.use('/sessions', (req, res, next) => {
  req.db = pool;
  next();
}, createSessionRoutes(pool));

app.use('/aed', (req, res, next) => {
  req.db = pool;
  next();
}, createAedRoutes(pool));

app.use((req, res) => {
  res.status(404).json({ error: '❌ Route not found' });
});

app.use((err, req, res, next) => {
  console.error('❌ Server Error:', err);
  res.status(500).json({
    message: '❌ Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : null,
  });
});

const PORT = process.env.PORT || 3000;

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`❌ Port ${PORT} is already in use. Exiting...`);
    process.exit(1);
  } else {
    throw err;
  }
});

async function connectDatabase() {
  try {
    const result = await pool.query('SELECT NOW()');
    console.log(`✅ Database connected at ${result.rows[0].now}`);
  } catch (error) {
    console.error('❌ Database connection error:', error.message);
    console.error('🟠 Retrying in 5 seconds...');
    setTimeout(connectDatabase, 5000);
  }
}
connectDatabase();

async function shutdown() {
  console.log('🛑 Shutting down gracefully...');
  await pool.end();
  console.log('✅ Database pool closed.');
  setTimeout(() => {
    console.log('👋 Exiting process...');
    process.exit(0);
  }, 1000);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

process.stdin.resume();
