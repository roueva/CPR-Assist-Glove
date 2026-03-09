const { spawn } = require('child_process');
const fs = require('fs').promises;
const path = require('path');

class AvailabilityParser {
    constructor(pool) {
    this.pool = pool;
    this.scriptPath = path.join(__dirname, '../scripts/parse_aed_data.py');
    this.cacheFile = path.join(__dirname, '../data/parsed_availability_map.json');
    this.inputFile = path.join(__dirname, '../data/aed_greece_current.json');
    this.isRunning = false;

}

    /**
     * Extract unique availability strings from AED data
     */
    async extractAvailabilityStrings(aeds) {
        const uniqueStrings = new Set();
        
        for (const aed of aeds) {
            if (aed.availability && aed.availability.trim()) {
                const decoded = aed.availability.trim()
                    .replace(/&amp;/g, '&')
                    .replace(/&lt;/g, '<')
                    .replace(/&gt;/g, '>');
                uniqueStrings.add(decoded);
            }
        }
        
        return Array.from(uniqueStrings);
    }

    /**
     * Load existing parsed cache
     */
    async loadCache() {
    // Try database first
    if (this.pool) {
        try {
            const result = await this.pool.query(
                'SELECT availability_text, parsed_data FROM availability_cache'
            );
            if (result.rows.length > 0) {
                const cache = {};
                for (const row of result.rows) {
                    cache[row.availability_text] = row.parsed_data;
                }
                console.log(`📦 Loaded existing cache: ${result.rows.length} entries (from database)`);
                return cache;
            }
        } catch (error) {
            console.warn('⚠️ Could not load from database, falling back to file:', error.message);
        }
    }

    // Fallback to file
    try {
        const data = await fs.readFile(this.cacheFile, 'utf8');
        const cache = JSON.parse(data);
        console.log(`📦 Loaded existing cache: ${Object.keys(cache).length} entries (from file)`);
        return cache;
    } catch (error) {
        if (error.code === 'ENOENT') {
            console.log('📦 No existing cache found - starting fresh');
        } else {
            console.warn('⚠️ Error loading cache:', error.message);
        }
        return {};
    }
}


async saveToDatabase(cache) {
    if (!this.pool) return;
    
    try {
        const entries = Object.entries(cache);
        let saved = 0;

        for (const [text, data] of entries) {
            await this.pool.query(
                `INSERT INTO availability_cache (availability_text, parsed_data)
                 VALUES ($1, $2)
                 ON CONFLICT (availability_text) 
                 DO UPDATE SET parsed_data = $2, parsed_at = NOW()`,
                [text, JSON.stringify(data)]
            );
            saved++;
        }
        console.log(`💾 Saved ${saved} entries to database`);
    } catch (error) {
        console.error('❌ Error saving cache to database:', error.message);
    }
}

    /**
     * Compare current strings with cached strings
     * Returns: { new, changed, unchanged }
     */
    async analyzeChanges(currentStrings, cache) {
        const analysis = {
            new: [],
            changed: [],
            unchanged: []
        };

        for (const str of currentStrings) {
            if (!cache[str]) {
                // String doesn't exist in cache
                analysis.new.push(str);
            } else if (cache[str].status === 'parsed') {
                // String exists and was successfully parsed
                analysis.unchanged.push(str);
            } else if (cache[str].status === 'error' || cache[str].status === 'pending') {
                // String exists but parsing failed or is pending - retry
                analysis.changed.push({
                    string: str,
                    oldStatus: cache[str].status,
                    reason: 'Previous parse failed or incomplete'
                });
            } else {
                // String exists but might need re-parsing
                analysis.unchanged.push(str);
            }
        }

        return analysis;
    }

    /**
     * Print detailed change analysis
     */
    printAnalysis(analysis, oldCache) {
        const totalStrings = analysis.new.length + analysis.changed.length + analysis.unchanged.length;
        const needsParsing = analysis.new.length + analysis.changed.length;

        console.log(`📊 Availability: ${totalStrings} unique strings, ${analysis.unchanged.length} cached, ${needsParsing} need parsing`);

        if (needsParsing === 0) {
            console.log('✅ All availability strings already parsed - no API calls needed');
        } else {
            console.log(`🐍 Will parse ${needsParsing} strings (~${Math.ceil(needsParsing * 10 / 60)} min estimated)`);
        }
    }

    /**
     * Create filtered input file with only strings that need parsing
     */
    async createFilteredInputFile(aeds, stringsToProcess) {
        const stringSet = new Set(stringsToProcess);
        
        // Only include AEDs with availability strings that need processing
        const filteredAEDs = aeds.filter(aed => 
            aed.availability && stringSet.has(aed.availability.trim())
        );

        const data = filteredAEDs.map(aed => ({
            AED_ID: aed.id.toString(),
            foundation: aed.foundation || '',
            address: aed.address || '',
            latitude: aed.latitude,
            longitude: aed.longitude,
            availability: aed.availability || '',
            aed_webpage: aed.aed_webpage || ''
        }));
        
        const dataDir = path.dirname(this.inputFile);
        await fs.mkdir(dataDir, { recursive: true });
        await fs.writeFile(this.inputFile, JSON.stringify(data, null, 2));
        
        console.log(`💾 Created input file with ${data.length} AEDs (${stringsToProcess.length} unique strings)`);
    }

    /**
     * Run Python parser
     */
    async runPythonParser() {
        return new Promise((resolve, reject) => {
            console.log('\n🐍 Starting Python availability parser...\n');
            
            const candidates = process.platform === 'win32'
                ? ['python']
                : ['python3.11', 'python3', 'python'];

            let pythonCmd = null;
            for (const cmd of candidates) {
                try {
                    const test = require('child_process').spawnSync(cmd, ['--version']);
                    if (test.status === 0) {
                        pythonCmd = cmd;
                        break;
                    }
                } catch (e) { /* try next */ }
            }

            if (!pythonCmd) {
                reject(new Error('No Python interpreter found. Tried: python3.11, python3, python'));
                return;
            }

            console.log(`🐍 Using Python command: ${pythonCmd}`);
            const pythonProcess = spawn(pythonCmd, [this.scriptPath], {
                env: process.env
            });
            
            let stdout = '';
            let stderr = '';
            
            pythonProcess.stdout.on('data', (data) => {
                const output = data.toString();
                stdout += output;

                // Only log milestones and errors, nothing else
                if (output.includes('Process Complete') ||
                    output.includes('ERROR') ||
                    output.includes('>>>') ||
                    output.includes('DB connection') ||
                    output.includes('FAILED')) {
                    console.log(output.trim());
                }

                const match = output.match(/\[(\d+)\/(\d+)\]/);
                if (match) {
                    const current = parseInt(match[1]);
                    const total = parseInt(match[2]);
                    if (current % 100 === 0 || current === total) {
                        console.log(`🐍 Python progress: [${current}/${total}]`);
                    }
                }
            });
            
            pythonProcess.stderr.on('data', (data) => {
                const msg = data.toString();
                stderr += msg;
                // Print stderr immediately so it's not lost if process is killed
                if (msg.trim()) console.error('🐍 Python stderr:', msg.trim());
            });
            
            pythonProcess.on('close', (code) => {
                if (code === 0) {
                    console.log('\n✅ Python parser completed successfully\n');
                    resolve(stdout);
                } else {
                    console.error('\n❌ Python parser failed:', stderr);
                    reject(new Error(`Python script exited with code ${code}: ${stderr}`));
                }
            });
            
            pythonProcess.on('error', (error) => {
                console.error('❌ Failed to start Python script:', error);
                reject(error);
            });
        });
    }

    /**
     * Print before/after comparison for newly parsed strings
     */
    async printBeforeAfter(stringsToProcess, oldCache, newCache) {
        let successCount = 0;
        let errorCount = 0;

        for (const str of stringsToProcess) {
            const after = newCache[str];
            if (after && after.status === 'parsed') successCount++;
            else errorCount++;
        }

        console.log(`📝 Parsing results: ${successCount}/${stringsToProcess.length} successful, ${errorCount} failed`);
        console.log(`📦 Total cache entries: ${Object.keys(newCache).length}`);
    }


    /**
     * Main parsing method with change detection
     */
    async parseAvailability(aeds) {
        if (this.isRunning) {
            console.log('⚠️ Parser already running - skipping this invocation');
            return await this.loadCache();
        }
        this.isRunning = true;
        try {
            // Step 1: Extract current availability strings
            const currentStrings = await this.extractAvailabilityStrings(aeds);
            
            if (currentStrings.length === 0) {
                console.log('⚠️ No availability strings found in AED data');
                return {};
            }

            // Step 2: Load existing cache
            const oldCache = await this.loadCache();

            // Step 3: Analyze what needs to be parsed
            const analysis = await this.analyzeChanges(currentStrings, oldCache);
            
            // Step 4: Print analysis
            this.printAnalysis(analysis, oldCache);

            // Step 5: Determine what needs parsing
            const stringsToProcess = [
                ...analysis.new,
                ...analysis.changed.map(item => item.string)
            ];

            // Step 6: If nothing needs parsing, return existing cache
            if (stringsToProcess.length === 0) {
                console.log('✅ Cache is up to date - no parsing needed!\n');
                return oldCache;
            }

            // Step 7: Create filtered input file with only AEDs that need parsing
            await this.createFilteredInputFile(aeds, stringsToProcess);

            // Step 8: Run Python parser
            await this.runPythonParser();

            // Step 9: Load updated cache
const newCache = await this.loadCache(); // this already reads from DB first

            // Step 10: Print before/after comparison
            await this.printBeforeAfter(stringsToProcess, oldCache, newCache);

            return newCache;

        } catch (error) {
            console.error('❌ Error in availability parsing:', error);
            return await this.loadCache();
        } finally {
            this.isRunning = false;
        }
    }

    /**
     * Get availability for a specific string
     */
    async getAvailability(availabilityString) {
        const cache = await this.loadCache();
        return cache[availabilityString] || null;
    }
}

module.exports = AvailabilityParser;