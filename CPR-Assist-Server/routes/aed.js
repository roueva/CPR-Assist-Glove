const express = require('express');
const router = express.Router();
const AEDService = require('../services/aedService');

module.exports = (pool) => {
    // ✅ Fetch all AED locations
    router.get('/', async (req, res) => {
        try {
            const result = await pool.query("SELECT * FROM aed_locations ORDER BY foundation;");
            return res.json({ success: true, data: result.rows });
        } catch (error) {
            console.error("❌ Error fetching AED locations:", error);
            res.status(500).json({ 
                success: false, 
                message: "Failed to fetch AED locations.",
                ...(process.env.NODE_ENV === 'development' && { error: error.message })
            });
        }
    });

    // ✅ Get single AED by ID
    router.get('/:id', async (req, res) => {
        const { id } = req.params;
        
        try {
            const result = await pool.query("SELECT * FROM aed_locations WHERE id = $1", [id]);
            
            if (result.rows.length === 0) {
                return res.status(404).json({ success: false, message: "AED not found" });
            }
            
            return res.json({ success: true, data: result.rows[0] });
        } catch (error) {
            console.error("❌ Error fetching AED:", error);
            res.status(500).json({ 
                success: false, 
                message: "Failed to fetch AED.",
                ...(process.env.NODE_ENV === 'development' && { error: error.message })
            });
        }
    });

    // ✅ Manual sync from iSaveLives API
    router.post('/sync', async (req, res) => {
        try {
            const aedService = new AEDService(pool);
            
            console.log('🔄 Starting manual AED sync...');
            const externalAEDs = await aedService.fetchFromExternalAPI();
            
            if (externalAEDs.length === 0) {
                return res.json({ 
                    success: true, 
                    message: 'No AEDs found to sync',
                    inserted: 0,
                    updated: 0,
                    unchanged: 0,
                    total: 0
                });
            }
            
            const result = await aedService.syncAEDs(externalAEDs);
            
            res.json({ 
                success: true, 
                message: `✅ Successfully synced ${result.total} AEDs`,
                inserted: result.inserted,
                updated: result.updated,
                unchanged: result.unchanged,
                total: result.total
            });
            
        } catch (error) {
            console.error('❌ Error syncing AEDs:', error);
            res.status(500).json({ 
                success: false, 
                message: 'Failed to sync AEDs',
                error: process.env.NODE_ENV === 'development' ? error.message : undefined
            });
        }
    });

    // ✅ Get cache file information
    router.get('/cache/info', async (req, res) => {
        try {
            const aedService = new AEDService(pool);
            const cacheInfo = await aedService.getCacheInfo();
            res.json({ success: true, cache: cacheInfo });
        } catch (error) {
            console.error('❌ Error getting cache info:', error);
            res.status(500).json({ 
                success: false, 
                message: 'Failed to get cache info' 
            });
        }
    });

    // ✅ Get AEDs near a location (within radius in kilometers)
    router.get('/near/:lat/:lng/:radius', async (req, res) => {
        const { lat, lng, radius } = req.params;
        const latitude = parseFloat(lat);
        const longitude = parseFloat(lng);
        const radiusKm = parseFloat(radius);

        if (isNaN(latitude) || isNaN(longitude) || isNaN(radiusKm)) {
            return res.status(400).json({ 
                success: false, 
                message: "Invalid coordinates or radius" 
            });
        }

        try {
            const result = await pool.query(`
                SELECT *,
                    (6371 * acos(
                        cos(radians($1)) * cos(radians(latitude)) * 
                        cos(radians(longitude) - radians($2)) + 
                        sin(radians($1)) * sin(radians(latitude))
                    )) AS distance
                FROM aed_locations
                WHERE (6371 * acos(
                    cos(radians($1)) * cos(radians(latitude)) * 
                    cos(radians(longitude) - radians($2)) + 
                    sin(radians($1)) * sin(radians(latitude))
                )) <= $3
                ORDER BY distance;
            `, [latitude, longitude, radiusKm]);

            return res.json({ 
                success: true, 
                count: result.rows.length,
                data: result.rows 
            });
        } catch (error) {
            console.error("❌ Error finding nearby AEDs:", error);
            res.status(500).json({ 
                success: false, 
                message: "Failed to find nearby AEDs.",
                ...(process.env.NODE_ENV === 'development' && { error: error.message })
            });
        }
    });

    return router;
};