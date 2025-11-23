const express = require('express');
const router = express.Router();
const AEDService = require('../services/aedService');

module.exports = (pool) => {
    // ✅ Fetch all AED locations
    router.get('/', async (req, res) => {
        try {
            const result = await pool.query(`
                SELECT 
                    id,
                    foundation,
                    address,
                    latitude,
                    longitude,
                    availability,
                    aed_webpage,
                    last_updated
                FROM aed_locations 
                ORDER BY id
            `);
            
            // ✅ Add metadata headers
            if (result.rows.length > 0) {
                // Find most recent update
                const mostRecentUpdate = new Date(
                    Math.max(...result.rows.map(row => new Date(row.last_updated)))
                );
                
                res.set('X-Data-Last-Updated', mostRecentUpdate.toISOString());
                res.set('X-Total-AEDs', result.rows.length.toString());
                res.set('X-Data-Source', 'database');
            }
            
            // ✅ Return array directly (not wrapped in object)
            return res.json(result.rows);
            
        } catch (error) {
            console.error("❌ Error fetching AED locations:", error);
            res.status(500).json({ 
                error: "Failed to fetch AED locations.",
                ...(process.env.NODE_ENV === 'development' && { details: error.message })
            });
        }
    });

    // ✅ Manual sync from iSaveLives API
    router.post('/sync', async (req, res) => {
        try {
            const aedService = new AEDService(pool);
            
            console.log('🔄 Starting manual AED sync...');
            const startTime = Date.now();
            
            const externalAEDs = await aedService.fetchFromExternalAPI();
            
            if (externalAEDs.length === 0) {
                return res.json({ 
                    success: true, 
                    message: 'No AEDs found to sync',
                    inserted: 0,
                    updated: 0,
                    total: 0,
                    duration: `${Date.now() - startTime}ms`
                });
            }
            
            const result = await aedService.syncAEDs(externalAEDs);
            
            res.json({ 
                success: true, 
                message: `Successfully synced ${result.total} AEDs`,
                inserted: result.inserted,
                updated: result.updated,
                total: result.total,
                duration: `${Date.now() - startTime}ms`,
                timestamp: new Date().toISOString()
            });
            
        } catch (error) {
            console.error('❌ Error syncing AEDs:', error);
            res.status(500).json({ 
                success: false, 
                error: 'Failed to sync AEDs',
                ...(process.env.NODE_ENV === 'development' && { details: error.message })
            });
        }
    });

    // ✅ One-time bootstrap cache endpoint (protected)
router.post('/bootstrap-cache', async (req, res) => {
    try {
        const BOOTSTRAP_SECRET = process.env.BOOTSTRAP_SECRET || 'change-me-in-production';
        
        // Simple authentication
        const providedSecret = req.headers['x-bootstrap-secret'] || req.body.secret;
        
        if (providedSecret !== BOOTSTRAP_SECRET) {
            console.warn('⚠️ Bootstrap attempt with invalid secret');
            return res.status(401).json({ error: 'Unauthorized - Invalid secret' });
        }
        
        const { cache } = req.body;
        
        if (!cache || typeof cache !== 'object') {
            return res.status(400).json({ error: 'Invalid cache data - must provide "cache" object' });
        }
        
        const fs = require('fs').promises;
        const path = require('path');
        const cacheFile = path.join(__dirname, '../data/parsed_availability_map.json');
        
        // Ensure directory exists
        const dataDir = path.dirname(cacheFile);
        await fs.mkdir(dataDir, { recursive: true });
        
        // Write cache file
        await fs.writeFile(cacheFile, JSON.stringify(cache, null, 2));
        
        const entryCount = Object.keys(cache).length;
        console.log(`✅ Bootstrap cache uploaded: ${entryCount} entries`);
        
        // Verify file was written correctly
        const verify = await fs.readFile(cacheFile, 'utf8');
        const verifyCache = JSON.parse(verify);
        
        res.json({ 
            success: true, 
            message: `Cache initialized successfully`,
            entries: entryCount,
            verified: Object.keys(verifyCache).length === entryCount,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('❌ Bootstrap cache failed:', error);
        res.status(500).json({ 
            error: 'Failed to bootstrap cache',
            details: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
});

    // ✅ Get parsed availability map - MOVED BEFORE /:id
    router.get('/availability', async (req, res) => {
        try {
            const fs = require('fs').promises;
            const path = require('path');
            const filePath = path.join(__dirname, '../data/parsed_availability_map.json');
            
            // Check if file exists
            try {
                await fs.access(filePath);
            } catch (error) {
                console.log('⚠️ Availability cache file not found, returning empty map');
                return res.json({});
            }
            
            const data = await fs.readFile(filePath, 'utf8');
            const parsedMap = JSON.parse(data);
            
            // Add metadata
            const stats = await fs.stat(filePath);
            
            res.set('X-Availability-Count', Object.keys(parsedMap).length.toString());
            res.set('X-Last-Updated', stats.mtime.toISOString());
            res.set('Cache-Control', 'public, max-age=86400'); // Cache for 24 hours
            
            console.log(`📤 Served availability map: ${Object.keys(parsedMap).length} entries`);
            return res.json(parsedMap);
            
        } catch (error) {
            console.error("❌ Error fetching availability map:", error);
            res.status(500).json({ 
                error: "Failed to fetch availability map.",
                ...(process.env.NODE_ENV === 'development' && { details: error.message })
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

            // ✅ Add metadata header
            res.set('X-Result-Count', result.rows.length.toString());

            // ✅ Return array directly
            return res.json(result.rows);
        } catch (error) {
            console.error("❌ Error finding nearby AEDs:", error);
            res.status(500).json({ 
                success: false, 
                message: "Failed to find nearby AEDs.",
                ...(process.env.NODE_ENV === 'development' && { error: error.message })
            });
        }
    });

    // ✅ Get single AED by ID - MUST BE LAST
    router.get('/:id', async (req, res) => {
        const { id } = req.params;
        
        // ✅ Validate ID is a number
        if (isNaN(parseInt(id))) {
            return res.status(400).json({ error: "Invalid AED ID" });
        }
        
        try {
            const result = await pool.query(`
                SELECT 
                    id, foundation, address, latitude, longitude,
                    availability, aed_webpage, last_updated
                FROM aed_locations 
                WHERE id = $1
            `, [id]);
            
            if (result.rows.length === 0) {
                return res.status(404).json({ error: "AED not found" });
            }
            
            // ✅ Return object directly (no wrapping)
            return res.json(result.rows[0]);
            
        } catch (error) {
            console.error("❌ Error fetching AED:", error);
            res.status(500).json({ 
                error: "Failed to fetch AED.",
                ...(process.env.NODE_ENV === 'development' && { details: error.message })
            });
        }
    });

    return router;
};