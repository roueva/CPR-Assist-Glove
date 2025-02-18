require('dotenv').config();
const { Pool } = require('pg');


const connectionString = process.env.DATABASE_URL;


// ✅ Enhanced Pool Configuration
const pool = new Pool({
  connectionString,
  ssl: process.env.DATABASE_URL?.includes('railway.app') ? { rejectUnauthorized: false } : false,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  allowExitOnIdle: true,
});


pool.on('error', (err) => {
    console.error('❌ Unexpected PostgreSQL pool error:', err);
    if (err.code === 'PROTOCOL_CONNECTION_LOST') {
        console.error('Database connection was closed.');
    }
    if (err.code === 'ER_CON_COUNT_ERROR') {
        console.error('Database has too many connections.');
    }
    if (err.code === 'ECONNREFUSED') {
        console.error('Database connection was refused.');
    }
});

// ✅ Better Table Creation
async function ensureAedTable() {
    let client;
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
        
        return true;
    } catch (err) {
        console.error("❌ Error ensuring AED table:", err);
        return false;
    } finally {
        if (client) {
            client.release();
        }
    }
}

// ✅ Export both pool and initialization function
module.exports = { pool, ensureAedTable };
