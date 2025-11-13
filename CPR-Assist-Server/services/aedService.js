const axios = require('axios');
const fs = require('fs').promises;
const path = require('path');

class AEDService {
    constructor(pool) {
        this.pool = pool;
        this.API_URL = 'https://isavelivesapi-qa.azurewebsites.net/aed_endpoint';
        this.API_KEY = process.env.ISAVELIVES_API_KEY;
        this.CACHE_FILE = path.join(__dirname, '../data/aed_cache.json');

        if (!this.API_KEY) {
            throw new Error('ISAVELIVES_API_KEY environment variable is not set');
        }
    }

    /**
     * Fetch AEDs from iSaveLives API
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
            
            // Save to cache file
            await this.saveCacheFile(response.data);
            
            return this.transformExternalData(response.data);
            
        } catch (error) {
            console.error('❌ Error fetching from iSaveLives API:', error.message);
            
            // Try to load from cache if API fails
            console.log('⚠️ Attempting to load from cache file...');
            const cachedData = await this.loadCacheFile();
            
            if (cachedData) {
                console.log(`✅ Loaded ${cachedData.length} AEDs from cache`);
                return this.transformExternalData(cachedData);
            }
            
            throw new Error(`Failed to fetch from API and no cache available: ${error.message}`);
        }
    }

    /**
     * Save API response to cache file
     */
    async saveCacheFile(data) {
        try {
            const cacheData = {
                lastUpdated: new Date().toISOString(),
                count: data.length,
                data: data
            };

            // Ensure data directory exists
            const dataDir = path.dirname(this.CACHE_FILE);
            await fs.mkdir(dataDir, { recursive: true });

            await fs.writeFile(
                this.CACHE_FILE,
                JSON.stringify(cacheData, null, 2),
                'utf8'
            );

            console.log(`💾 Saved ${data.length} AEDs to cache file`);
        } catch (error) {
            console.error('❌ Error saving cache file:', error.message);
            // Don't throw - cache save failure shouldn't break the sync
        }
    }

    /**
     * Load AEDs from cache file
     */
    async loadCacheFile() {
        try {
            const fileContent = await fs.readFile(this.CACHE_FILE, 'utf8');
            const cacheData = JSON.parse(fileContent);
            
            console.log(`📂 Cache file from: ${cacheData.lastUpdated}`);
            return cacheData.data;
        } catch (error) {
            if (error.code === 'ENOENT') {
                console.log('ℹ️ No cache file found');
            } else {
                console.error('❌ Error loading cache file:', error.message);
            }
            return null;
        }
    }

    /**
     * Transform API data to database schema (exact match)
     */
    transformExternalData(externalData) {
        return externalData.map(item => {
            const id = parseInt(item.AED_ID);
            
            if (isNaN(id)) {
                console.warn(`⚠️ Invalid AED_ID: ${item.AED_ID}, skipping...`);
                return null;
            }

            const latitude = parseFloat(item.latitude);
            const longitude = parseFloat(item.longitude);
            
            if (isNaN(latitude) || isNaN(longitude)) {
                console.warn(`⚠️ Invalid coordinates for AED ${id}, skipping...`);
                return null;
            }

            return {
                id: id,
                foundation: item.foundation || null,
                address: item.address || null,
                latitude: latitude,
                longitude: longitude,
                availability: item.availability || null,
                aed_webpage: item.aed_webpage || null
            };
        }).filter(item => item !== null);
    }

    /**
     * Sync AEDs: Update existing records or insert new ones
     */
    async syncAEDs(aeds) {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            
            let inserted = 0;
            let updated = 0;
            let unchanged = 0;
            
            for (const aed of aeds) {
                const result = await client.query(`
                    INSERT INTO aed_locations (
                        id, foundation, address, latitude, longitude,
                        availability, aed_webpage, last_updated
                    )
                    VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
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
                `, [
                    aed.id, aed.foundation, aed.address, aed.latitude,
                    aed.longitude, aed.availability, aed.aed_webpage
                ]);
                
                if (result.rows.length === 0) {
                    unchanged++;
                } else if (result.rows[0].inserted) {
                    inserted++;
                } else {
                    updated++;
                }
            }
            
            await client.query('COMMIT');
            console.log(`✅ Sync complete: ${inserted} inserted, ${updated} updated, ${unchanged} unchanged`);
            return { success: true, inserted, updated, unchanged, total: aeds.length };
            
        } catch (error) {
            await client.query('ROLLBACK');
            console.error('❌ Sync operation failed:', error.message);
            throw error;
        } finally {
            client.release();
        }
    }

    /**
     * Get cache file info
     */
    async getCacheInfo() {
        try {
            const fileContent = await fs.readFile(this.CACHE_FILE, 'utf8');
            const cacheData = JSON.parse(fileContent);
            return {
                exists: true,
                lastUpdated: cacheData.lastUpdated,
                count: cacheData.count
            };
        } catch (error) {
            return { exists: false };
        }
    }
}

module.exports = AEDService;