const axios = require('axios');

class AEDService {
    constructor(pool) {
        this.pool = pool;
        this.API_URL = 'https://isavelivesapi-qa.azurewebsites.net/aed_endpoint';
        this.API_KEY = process.env.ISAVELIVES_API_KEY;

        if (!this.API_KEY) {
            throw new Error('ISAVELIVES_API_KEY environment variable is not set');
        }
    }

    /**
     * Fetch AEDs from iSaveLives API with database fallback
     */
    async fetchFromExternalAPI() {
        try {
            console.log('🔄 Fetching AEDs from iSaveLives API...');
            
            const response = await axios.get(this.API_URL, {
                headers: {
                    'Accept': 'application/json',
                    'x-api-key': this.API_KEY
                },
                timeout: 30000
            });

            if (!Array.isArray(response.data)) {
                throw new Error('API response is not an array');
            }

            console.log(`✅ Fetched ${response.data.length} AEDs from iSaveLives API`);
            return this.transformExternalData(response.data);
            
        } catch (error) {
            console.error('❌ Error fetching from iSaveLives API:', error.message);
            
            // ✅ Try database as fallback instead of file cache
            console.log('⚠️ API failed - attempting to use existing database data...');
            
            const client = await this.pool.connect();
            try {
                const result = await client.query(
                    'SELECT * FROM aed_locations ORDER BY id'
                );
                
                if (result.rows.length > 0) {
                    console.log(`✅ Using ${result.rows.length} AEDs from database as fallback`);
                    return result.rows;
                }
                
                throw new Error('No data available in database');
            } finally {
                client.release();
            }
        }
    }

    /**
     * Transform API data to database schema with validation
     */
    transformExternalData(externalData) {
        const transformed = [];
        const skipped = { invalidId: 0, invalidCoords: 0, duplicates: 0 };
        const seenIds = new Set();

        for (const item of externalData) {
            const id = parseInt(item.AED_ID);
            
            // ✅ Check for invalid ID
            if (isNaN(id)) {
                skipped.invalidId++;
                console.warn(`⚠️ Skipped: Invalid AED_ID "${item.AED_ID}"`);
                continue;
            }

            // ✅ Check for duplicate ID
            if (seenIds.has(id)) {
                skipped.duplicates++;
                console.warn(`⚠️ Skipped: Duplicate AED_ID ${id}`);
                continue;
            }
            seenIds.add(id);

            const latitude = parseFloat(item.latitude);
            const longitude = parseFloat(item.longitude);
            
            // ✅ Check for invalid coordinates
            if (isNaN(latitude) || isNaN(longitude)) {
                skipped.invalidCoords++;
                console.warn(`⚠️ Skipped: Invalid coordinates for AED ${id}`);
                continue;
            }

            // ✅ Valid record
            transformed.push({
                id: id,
                foundation: item.foundation || null,
                address: item.address || null,
                latitude: latitude,
                longitude: longitude,
                availability: item.availability || null,
                aed_webpage: item.aed_webpage || null
            });
        }

        // ✅ Log skip summary
        const totalSkipped = skipped.invalidId + skipped.invalidCoords + skipped.duplicates;
        if (totalSkipped > 0) {
            console.log(`⚠️ Skipped ${totalSkipped} records: ${skipped.invalidId} invalid IDs, ${skipped.invalidCoords} invalid coords, ${skipped.duplicates} duplicates`);
        }

        return transformed;
    }

    /**
     * Sync AEDs with accurate insert/update tracking
     */
    async syncAEDs(aeds) {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            
            console.log(`📦 Syncing ${aeds.length} AEDs...`);
            
            const batchSize = 500;
            let totalInserted = 0;
            let totalUpdated = 0;
            
            for (let i = 0; i < aeds.length; i += batchSize) {
                const batch = aeds.slice(i, i + batchSize);
                
                // Build VALUES for batch
                const values = [];
                const params = [];
                let paramIndex = 1;
                
                for (const aed of batch) {
                    values.push(`($${paramIndex}, $${paramIndex+1}, $${paramIndex+2}, $${paramIndex+3}, $${paramIndex+4}, $${paramIndex+5}, $${paramIndex+6}, NOW())`);
                    params.push(
                        aed.id,
                        aed.foundation,
                        aed.address,
                        aed.latitude,
                        aed.longitude,
                        aed.availability,
                        aed.aed_webpage
                    );
                    paramIndex += 7;
                }
                
                // ✅ Use xmax to accurately track inserts vs updates
                const query = `
                    WITH upsert_result AS (
                        INSERT INTO aed_locations (
                            id, foundation, address, latitude, longitude,
                            availability, aed_webpage, last_updated
                        )
                        VALUES ${values.join(', ')}
                        ON CONFLICT (id)
                        DO UPDATE SET
                            foundation = EXCLUDED.foundation,
                            address = EXCLUDED.address,
                            latitude = EXCLUDED.latitude,
                            longitude = EXCLUDED.longitude,
                            availability = EXCLUDED.availability,
                            aed_webpage = EXCLUDED.aed_webpage,
                            last_updated = NOW()
                        WHERE 
                            aed_locations.foundation IS DISTINCT FROM EXCLUDED.foundation OR
                            aed_locations.address IS DISTINCT FROM EXCLUDED.address OR
                            aed_locations.latitude IS DISTINCT FROM EXCLUDED.latitude OR
                            aed_locations.longitude IS DISTINCT FROM EXCLUDED.longitude OR
                            aed_locations.availability IS DISTINCT FROM EXCLUDED.availability OR
                            aed_locations.aed_webpage IS DISTINCT FROM EXCLUDED.aed_webpage
                        RETURNING (xmax = 0) AS inserted
                    )
                    SELECT 
                        COUNT(*) FILTER (WHERE inserted) as inserted,
                        COUNT(*) FILTER (WHERE NOT inserted) as updated
                    FROM upsert_result
                `;
                
                const result = await client.query(query, params);
                
                if (result.rows[0]) {
                    totalInserted += parseInt(result.rows[0].inserted || 0);
                    totalUpdated += parseInt(result.rows[0].updated || 0);
                }
                
                const progress = Math.min(i + batchSize, aeds.length);
                if (progress % 1000 === 0 || progress === aeds.length) {
                    console.log(`📦 Processed ${progress}/${aeds.length} AEDs`);
                }
            }
            
            // ✅ Get final count
            const countResult = await client.query('SELECT COUNT(*) as total FROM aed_locations');
            const totalInDB = parseInt(countResult.rows[0].total);
            
            await client.query('COMMIT');
            
            console.log(`✅ Sync complete:`);
            console.log(`   → ${totalInserted} new AEDs inserted`);
            console.log(`   → ${totalUpdated} existing AEDs updated`);
            console.log(`   → ${totalInDB} total AEDs in database`);
            
            return { 
                success: true, 
                inserted: totalInserted, 
                updated: totalUpdated, 
                total: totalInDB 
            };
            
        } catch (error) {
            await client.query('ROLLBACK');
            console.error('❌ Sync operation failed:', error.message);
            throw error;
        } finally {
            client.release();
        }
    }
}

module.exports = AEDService;