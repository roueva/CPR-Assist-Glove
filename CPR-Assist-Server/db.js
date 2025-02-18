// ✅ Cleaned db.js (Removed `CREATE TABLE`)
require('dotenv').config();
const { Pool } = require('pg');

// ✅ Database Connection Configuration
const connectionString = process.env.DATABASE_URL;
const pool = new Pool({
    connectionString,
    ssl: process.env.DATABASE_URL?.includes('railway.app') ? { rejectUnauthorized: false } : false,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    allowExitOnIdle: true,
});

// ✅ Pool Event Logs
pool.on('connect', () => {
    console.log(`[${new Date().toISOString()}] ✅ Connected to PostgreSQL pool`);
});

pool.on('remove', () => {
    console.log(`[${new Date().toISOString()}] 🛑 Client removed from PostgreSQL pool`);
});

pool.on('error', (err) => {
    console.error(`[${new Date().toISOString()}] ❌ PostgreSQL Pool Error:
  Code: ${err.code}
  Message: ${err.message}
  Stack: ${err.stack || 'No stack trace'}`);
});

// ✅ Export Pool Only (No Table Creation)
module.exports = { pool };
