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
  //  console.log(`[${new Date().toISOString()}] ✅ Connected to PostgreSQL pool`);
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

// ✅ Create AED Table
async function ensureAedTable() {
    let client;
    const startTime = Date.now(); // Start time for duration tracking
    try {
        client = await pool.connect();

        await client.query(`
            CREATE TABLE IF NOT EXISTS aed_locations (
                id BIGINT PRIMARY KEY,
                latitude DOUBLE PRECISION NOT NULL,
                longitude DOUBLE PRECISION NOT NULL,
                name TEXT DEFAULT 'Unknown',
                address TEXT DEFAULT 'Unknown',
                emergency TEXT DEFAULT 'defibrillator',
                operator TEXT DEFAULT 'Unknown',
                indoor BOOLEAN,
                access TEXT DEFAULT 'unknown',
                defibrillator_location TEXT DEFAULT 'Not specified',
                level TEXT DEFAULT 'unknown',
                opening_hours TEXT DEFAULT 'unknown',
                phone TEXT DEFAULT 'unknown',
                wheelchair TEXT DEFAULT 'unknown',
                last_updated TIMESTAMP DEFAULT NOW()
            );
        `);

        const duration = Date.now() - startTime;
       // console.log(`[${new Date().toISOString()}] ✅ AED table ensured successfully in ${duration}ms`);
        return true;

    } catch (err) {
        console.error(`[${new Date().toISOString()}] ❌ Error ensuring AED table:
        Message: ${err.message}
        Stack: ${err.stack || 'No stack trace'}`);
        return false;

    } finally {
        if (client) {
            client.release();
        }
    }
}

// ✅ Export both pool and initialization function
module.exports = { pool, ensureAedTable };
