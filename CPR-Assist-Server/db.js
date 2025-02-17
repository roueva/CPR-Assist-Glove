// ✅ Load environment variables
require('dotenv').config();
const { Pool } = require('pg');

// 🟢 Log creation of the pool
console.log("🟢 PostgreSQL Pool created from db.js");

// ✅ Use DATABASE_URL for Railway (Preferred)
// Fallback to manual config for local development
const pool = new Pool({
    connectionString: process.env.DATABASE_URL || `postgresql://${process.env.POSTGRES_USER}:${process.env.POSTGRES_PASSWORD}@${process.env.POSTGRES_HOST}:${process.env.POSTGRES_PORT}/${process.env.POSTGRES_DATABASE}`,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// ✅ Pool Events for Logging
pool.on('connect', () => {
  console.log('✅ PostgreSQL pool connected');
});

pool.on('error', (err) => {
  console.error('❌ PostgreSQL Pool error:', err);
  process.exit(1); // Exit immediately on pool error
});

// ✅ Function to Ensure AED Table Exists
async function ensureAedTable() {
    const client = await pool.connect();
    try {
        console.log("🟡 Checking for AED table...");
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
        process.exit(1); // Fail fast if table creation fails
    } finally {
        client.release();
    }
}

// ✅ Call Ensure Table Immediately (before export)
ensureAedTable()
  .then(() => console.log("✅ Database structure ready!"))
  .catch((error) => {
      console.error("❌ Database setup failed:", error);
      process.exit(1);
  });

// ✅ Handle Unexpected Errors on the Pool
pool.on('error', (err) => {
    console.error('❌ Unexpected error on idle PostgreSQL client:', err);
    process.exit(-1);
});

// ✅ Export the pool to use in other files
module.exports = pool;
