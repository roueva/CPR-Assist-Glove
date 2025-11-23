const { spawn } = require('child_process');
const fs = require('fs').promises;
const path = require('path');

class AvailabilityParser {
    constructor() {
        this.scriptPath = path.join(__dirname, '../scripts/parse_aed_data.py');
        this.cacheFile = path.join(__dirname, '../data/parsed_availability_map.json');
        this.inputFile = path.join(__dirname, '../data/aed_greece_current.json');
    }

    /**
     * Extract unique availability strings from AED data
     */
    async extractAvailabilityStrings(aeds) {
        const uniqueStrings = new Set();
        
        for (const aed of aeds) {
            if (aed.availability && aed.availability.trim()) {
                uniqueStrings.add(aed.availability.trim());
            }
        }
        
        return Array.from(uniqueStrings);
    }

    /**
     * Load existing parsed cache
     */
    async loadCache() {
        try {
            const data = await fs.readFile(this.cacheFile, 'utf8');
            const cache = JSON.parse(data);
            console.log(`📦 Loaded existing cache: ${Object.keys(cache).length} entries`);
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
    printAnalysis(analysis, cache) {
        console.log('\n' + '='.repeat(70));
        console.log('📊 AVAILABILITY STRINGS ANALYSIS');
        console.log('='.repeat(70));
        
        const totalStrings = analysis.new.length + analysis.changed.length + analysis.unchanged.length;
        const needsParsing = analysis.new.length + analysis.changed.length;
        
        console.log(`📈 Total unique strings: ${totalStrings}`);
        console.log(`✅ Already parsed: ${analysis.unchanged.length}`);
        console.log(`🆕 New strings: ${analysis.new.length}`);
        console.log(`🔄 Changed/retry: ${analysis.changed.length}`);
        console.log(`🐍 Need parsing: ${needsParsing}`);
        
        if (analysis.new.length > 0) {
            console.log('\n' + '─'.repeat(70));
            console.log('🆕 NEW AVAILABILITY STRINGS:');
            console.log('─'.repeat(70));
            analysis.new.forEach((str, idx) => {
                console.log(`[${idx + 1}/${analysis.new.length}] "${str}"`);
            });
        }

        if (analysis.changed.length > 0) {
            console.log('\n' + '─'.repeat(70));
            console.log('🔄 STRINGS TO RETRY:');
            console.log('─'.repeat(70));
            analysis.changed.forEach((item, idx) => {
                console.log(`[${idx + 1}/${analysis.changed.length}] "${item.string}"`);
                console.log(`   └─ Previous status: ${item.oldStatus}`);
                console.log(`   └─ Reason: ${item.reason}`);
            });
        }

        if (needsParsing === 0) {
            console.log('\n✅ All availability strings are already parsed!');
            console.log('   No API calls needed.');
        } else {
            console.log(`\n🐍 Will parse ${needsParsing} strings (estimated time: ~${Math.ceil(needsParsing * 10 / 60)} minutes)`);
        }
        
        console.log('='.repeat(70) + '\n');
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
            
            const pythonCmd = process.platform === 'win32' ? 'python' : 'python3';
            const pythonProcess = spawn(pythonCmd, [this.scriptPath]);
            
            let stdout = '';
            let stderr = '';
            
            pythonProcess.stdout.on('data', (data) => {
                const output = data.toString();
                stdout += output;
                // Print important lines
                if (output.includes('>>>') || 
                    output.includes('Process Complete') || 
                    output.includes('ERROR') ||
                    output.includes('[') && output.includes(']')) {
                    console.log(output.trim());
                }
            });
            
            pythonProcess.stderr.on('data', (data) => {
                stderr += data.toString();
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
        console.log('\n' + '='.repeat(70));
        console.log('📝 PARSING RESULTS');
        console.log('='.repeat(70));

        let successCount = 0;
        let errorCount = 0;

        for (const str of stringsToProcess) {
            const before = oldCache[str];
            const after = newCache[str];

            console.log(`\n${'─'.repeat(70)}`);
            console.log(`📄 Original Text: "${str}"`);
            console.log(`${'─'.repeat(70)}`);

            // Before state
            if (!before) {
                console.log('📥 BEFORE: Not in cache (NEW)');
            } else {
                console.log(`📥 BEFORE: Status = ${before.status}`);
                if (before.status === 'error' && before.error) {
                    console.log(`   └─ Error: ${before.error}`);
                }
            }

            // After state
            if (after && after.status === 'parsed') {
                successCount++;
                console.log('📤 AFTER: Successfully parsed ✅');
                console.log(`   ├─ 24/7: ${after.is_24_7 ? 'Yes' : 'No'}`);
                
                if (after.rules && after.rules.length > 0) {
                    console.log(`   └─ Rules (${after.rules.length}):`);
                    after.rules.forEach((rule, idx) => {
                        const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        const days = rule.days.map(d => dayNames[d - 1]).join(', ');
                        console.log(`      [${idx + 1}] Days: ${days}`);
                        console.log(`          Time: ${rule.open_time} - ${rule.close_time}`);
                    });
                } else if (after.is_24_7) {
                    console.log('   └─ Rules: Open 24/7');
                } else {
                    console.log('   └─ Rules: None (closed or unavailable)');
                }
            } else if (after && after.status === 'error') {
                errorCount++;
                console.log('📤 AFTER: Parsing failed ❌');
                console.log(`   └─ Error: ${after.error || 'Unknown error'}`);
            } else {
                errorCount++;
                console.log('📤 AFTER: Not found in updated cache ❌');
            }
        }

        console.log('\n' + '='.repeat(70));
        console.log('📊 SUMMARY');
        console.log('='.repeat(70));
        console.log(`✅ Successfully parsed: ${successCount}/${stringsToProcess.length}`);
        console.log(`❌ Failed to parse: ${errorCount}/${stringsToProcess.length}`);
        console.log(`📦 Total cache entries: ${Object.keys(newCache).length}`);
        console.log('='.repeat(70) + '\n');
    }

    /**
     * Main parsing method with change detection
     */
    async parseAvailability(aeds) {
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
            const newCache = await this.loadCache();

            // Step 10: Print before/after comparison
            await this.printBeforeAfter(stringsToProcess, oldCache, newCache);

            return newCache;

        } catch (error) {
            console.error('❌ Error in availability parsing:', error);
            // Return existing cache as fallback
            return await this.loadCache();
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