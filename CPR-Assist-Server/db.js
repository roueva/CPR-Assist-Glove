require('dotenv').config();
const { Pool } = require('pg');

console.log("🟢 PostgreSQL Pool created from db.js");

pool.on('connect', () => {
  console.log('✅ PostgreSQL pool connected');
});

pool.on('error', (err) => {
  console.error('❌ PostgreSQL Pool error:', err);
});


// Ensure required environment variables are set
if (!process.env.POSTGRES_PASSWORD) {
    console.error("❌ Error: POSTGRES_PASSWORD is missing in the .env file!");
    process.exit(1);
}

const password = String(process.env.POSTGRES_PASSWORD).trim();

const pool = new Pool({
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    password: password,
    port: process.env.POSTGRES_PORT || 5432,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// ✅ Ensure AED locations table exists (Block until Ready)
async function ensureAedTable() {
    const client = await pool.connect();
    try {
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
        console.log("✅ AED table ensured.");
    } catch (err) {
        console.error("❌ Error ensuring AED table:", err);
        process.exit(1); // Exit if DB fails
    } finally {
        client.release();
    }
}

// ✅ Call Ensure Table Immediately (before export)
ensureAedTable().then(() => {
    console.log("✅ Database structure ready!");
}).catch((error) => {
    console.error("❌ Database setup failed:", error);
    process.exit(1);
});

// ✅ Handle unexpected errors on the pool
pool.on('error', (err) => {
    console.error('Unexpected error on idle client:', err);
    process.exit(-1);
});

// ✅ Export the pool to use in other files
module.exports = pool;
