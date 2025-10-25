const axios = require('axios');

class AEDService {
    constructor(pool) {
        this.pool = pool;
        this.API_URL = 'https://isavelivesapi-qa.azurewebsites.net/aed_endpoint';
    }

    /**
     * Fetch AEDs from iSaveLives API
     */
    async fetchFromExternalAPI() {
        try {
            console.log('🔄 Fetching AEDs from iSaveLives API...');
            
            const response = await axios.get(this.API_URL, {
                headers: {
                    'Accept': 'application/json'
                },
                timeout: 30000 // 30 second timeout
            });

            if (!Array.isArray(response.data)) {
                throw new Error('API response is not an array');
            }

            console.log(`✅ Fetched ${response.data.length} AEDs from iSaveLives API`);
            return this.transformExternalData(response.data);
            
        } catch (error) {
            console.error('❌ Error fetching from iSaveLives API:', error.message);
            throw new Error(`Failed to fetch from iSaveLives API: ${error.message}`);
        }
    }

    /**
     * Transform iSaveLives data to your database schema
     */
    transformExternalData(externalData) {
        return externalData.map(item => {
            // Parse the AED_ID to integer
            const id = parseInt(item.AED_ID);
            
            if (isNaN(id)) {
                console.warn(`⚠️ Invalid AED_ID: ${item.AED_ID}, skipping...`);
                return null;
            }

            // Validate coordinates
            const latitude = parseFloat(item.latitude);
            const longitude = parseFloat(item.longitude);
            
            if (isNaN(latitude) || isNaN(longitude)) {
                console.warn(`⚠️ Invalid coordinates for AED ${id}, skipping...`);
                return null;
            }

            return {
                id: id,
                latitude: latitude,
                longitude: longitude,
                name: item.foundation || 'Unknown',
                address: item.address || 'Unknown',
                operator: item.foundation || 'Unknown',
                opening_hours: item.availability || 'unknown',
                aed_webpage: item.aed_webpage || null,
                emergency: 'defibrillator',
                indoor: null,
                access: 'unknown',
                defibrillator_location: item.foundation || 'Not specified',
                level: 'unknown',
                phone: 'unknown',
                wheelchair: null
            };
        }).filter(item => item !== null); // Remove invalid entries
    }

    /**
     * Bulk insert/update AEDs into database
     */
    async bulkInsertAEDs(aeds) {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            
            let inserted = 0;
            let updated = 0;
            
            for (const aed of aeds) {
                const result = await client.query(`
                    INSERT INTO aed_locations (
                        id, latitude, longitude, name, address, operator,
                        opening_hours, aed_webpage, emergency, indoor, access,
                        defibrillator_location, level, phone, wheelchair, last_updated
                    )
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW())
                    ON CONFLICT (id)
                    DO UPDATE SET
                        latitude = EXCLUDED.latitude,
                        longitude = EXCLUDED.longitude,
                        name = EXCLUDED.name,
                        address = EXCLUDED.address,
                        operator = EXCLUDED.operator,
                        opening_hours = EXCLUDED.opening_hours,
                        aed_webpage = EXCLUDED.aed_webpage,
                        last_updated = NOW()
                    RETURNING (xmax = 0) AS inserted
                `, [
                    aed.id, aed.latitude, aed.longitude, aed.name, aed.address,
                    aed.operator, aed.opening_hours, aed.aed_webpage, aed.emergency,
                    aed.indoor, aed.access, aed.defibrillator_location, aed.level,
                    aed.phone, aed.wheelchair
                ]);
                
                if (result.rows[0].inserted) {
                    inserted++;
                } else {
                    updated++;
                }
            }
            
            await client.query('COMMIT');
            console.log(`✅ Bulk operation complete: ${inserted} inserted, ${updated} updated`);
            return { success: true, inserted, updated, total: aeds.length };
            
        } catch (error) {
            await client.query('ROLLBACK');
            console.error('❌ Bulk operation failed:', error.message);
            throw error;
        } finally {
            client.release();
        }
    }

    /**
     * Delete old AEDs not in the new data
     */
    async deleteOldAEDs(newAedIds) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(
                'DELETE FROM aed_locations WHERE id NOT IN (SELECT unnest($1::bigint[]))',
                [newAedIds]
            );
            
            const deletedCount = result.rowCount;
            console.log(`🗑️ Deleted ${deletedCount} old AEDs`);
            return deletedCount;
            
        } catch (error) {
            console.error('❌ Error deleting old AEDs:', error.message);
            throw error;
        } finally {
            client.release();
        }
    }
}

module.exports = AEDService;