require('dotenv').config();
const { Pool } = require('pg');


const connectionString = process.env.DATABASE_URL;


// Pool Configuration
const pool = new Pool({
    connectionString,
    ssl: process.env.DATABASE_URL?.includes('railway.app') ? { rejectUnauthorized: false } : false,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    allowExitOnIdle: true,
});

// Pool Error Handling
pool.on('connect', () => {
    console.log('✅ PostgreSQL connected successfully');
});

pool.on('error', (err) => {
    console.error('❌ Unexpected PostgreSQL pool error:', err.message);
    if (err.code === 'ECONNREFUSED') {
        console.error('💀 Database connection refused — is PostgreSQL running?');
    } else if (err.code === '57P01') {
        console.error('🔌 Database connection terminated by admin.');
    } else if (err.code === '53300') {
        console.error('🔒 Too many database connections — consider reducing pool size.');
    } else if (err.code === '08006' || err.code === '08001') {
        console.error('📡 Database connection failure.');
    }
});

// Table Creation
async function ensureAedTable() {
    let client;
    try {
        client = await pool.connect();

        await client.query(`
            CREATE TABLE IF NOT EXISTS aed_locations (
                id BIGINT PRIMARY KEY,
                foundation TEXT,
                address TEXT,
                latitude DOUBLE PRECISION NOT NULL,
                longitude DOUBLE PRECISION NOT NULL,
                availability TEXT,
                aed_webpage TEXT,
                last_updated TIMESTAMP DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS aed_sync_log (
                id SERIAL PRIMARY KEY,
                synced_at TIMESTAMP DEFAULT NOW(),
                aeds_checked INTEGER,
                aeds_inserted INTEGER,
                aeds_updated INTEGER
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_aed_lat_lng 
            ON aed_locations (latitude, longitude);
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
