#!/usr/bin/env node

/**
 * Remove Table Wrappers Script
 * 
 * This script removes the table wrapper structures that were previously added
 * to tables in articles. It finds all articles with wrapped tables and removes:
 * - .table-wrapper divs
 * - .table-title-row divs (converts them to title rows within tables)
 * - .enhanced-table-container divs
 * - .table-toolbar divs
 * 
 * Usage:
 *   node scripts/remove-table-wrappers.js [--dry-run] [--verbose]
 * 
 * Options:
 *   --dry-run    Show what would be changed without making changes
 *   --verbose    Show detailed output
 */

const { Client } = require('pg');
const { JSDOM } = require('jsdom');

// Configuration
const isDryRun = process.argv.includes('--dry-run');
const isVerbose = process.argv.includes('--verbose') || isDryRun;

// Parse article ID argument
let articleId = null;
const articleIdIndex = process.argv.indexOf('--article-id');
if (articleIdIndex !== -1 && articleIdIndex + 1 < process.argv.length) {
    articleId = process.argv[articleIdIndex + 1];
}

// Database connection configuration
const dbConfig = {
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_DATABASE || 'directus',
    user: process.env.DB_USER || 'directus',
    password: process.env.DB_PASSWORD || 'directus',
    // If DATABASE_URL is provided, use that instead
    connectionString: process.env.DATABASE_URL,
};

// Color codes for output
const colors = {
    reset: '\x1b[0m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m',
};

function log(message, color = 'reset') {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

function verbose(message, color = 'cyan') {
    if (isVerbose) {
        log(`  ${message}`, color);
    }
}

/**
 * Remove table wrapper structures from HTML content
 */
function removeTableWrappers(htmlContent) {
    if (!htmlContent || typeof htmlContent !== 'string') {
        return { content: htmlContent, changed: false, changes: [] };
    }

    const dom = new JSDOM(htmlContent);
    const document = dom.window.document;
    const changes = [];
    let hasChanges = false;

    // Find all table wrappers
    const tableWrappers = document.querySelectorAll('.table-wrapper');
    
    for (const wrapper of tableWrappers) {
        const table = wrapper.querySelector('table');
        const titleRow = wrapper.querySelector('.table-title-row');
        
        if (table) {
            let titleText = '';
            
            // Extract title text if present
            if (titleRow && titleRow.textContent.trim()) {
                titleText = titleRow.textContent.trim();
                changes.push(`Extracted title: "${titleText}"`);
            }
            
            // Move table out of wrapper
            wrapper.parentNode.insertBefore(table, wrapper);
            
            // If we have a title, create a title row within the table
            if (titleText) {
                // Count columns in the table
                const firstRow = table.querySelector('tr');
                let colCount = 1;
                if (firstRow) {
                    colCount = 0;
                    firstRow.querySelectorAll('td, th').forEach(cell => {
                        colCount += parseInt(cell.getAttribute('colspan') || '1');
                    });
                }
                
                // Create title row
                const titleRowElement = document.createElement('tr');
                const titleCell = document.createElement('td');
                titleCell.setAttribute('colspan', colCount.toString());
                titleCell.className = 'ag-title-row';
                titleCell.textContent = titleText;
                titleRowElement.appendChild(titleCell);
                
                // Insert at the beginning of the table
                const tbody = table.querySelector('tbody') || table;
                tbody.insertBefore(titleRowElement, tbody.firstChild);
                
                changes.push(`Created title row with colspan ${colCount}`);
            }
            
            // Remove the wrapper
            wrapper.remove();
            hasChanges = true;
            changes.push('Removed table wrapper');
        }
    }

    // Also remove enhanced table containers and toolbars
    const enhancedContainers = document.querySelectorAll('.enhanced-table-container');
    for (const container of enhancedContainers) {
        const table = container.querySelector('table');
        const toolbar = container.querySelector('.table-toolbar');
        
        if (table) {
            let titleText = '';
            
            // Extract title from toolbar
            if (toolbar) {
                const titleElement = toolbar.querySelector('.table-title-text');
                if (titleElement && titleElement.textContent.trim()) {
                    titleText = titleElement.textContent.trim();
                    changes.push(`Extracted toolbar title: "${titleText}"`);
                }
            }
            
            // Move table out of container
            container.parentNode.insertBefore(table, container);
            
            // Add title row if we have a title
            if (titleText) {
                const firstRow = table.querySelector('tr');
                let colCount = 1;
                if (firstRow) {
                    colCount = 0;
                    firstRow.querySelectorAll('td, th').forEach(cell => {
                        colCount += parseInt(cell.getAttribute('colspan') || '1');
                    });
                }
                
                const titleRowElement = document.createElement('tr');
                const titleCell = document.createElement('td');
                titleCell.setAttribute('colspan', colCount.toString());
                titleCell.className = 'ag-title-row';
                titleCell.textContent = titleText;
                titleRowElement.appendChild(titleCell);
                
                const tbody = table.querySelector('tbody') || table;
                tbody.insertBefore(titleRowElement, tbody.firstChild);
                
                changes.push(`Created title row from toolbar with colspan ${colCount}`);
            }
            
            // Remove the container
            container.remove();
            hasChanges = true;
            changes.push('Removed enhanced table container');
        }
    }

    return {
        content: hasChanges ? dom.serialize() : htmlContent,
        changed: hasChanges,
        changes: changes
    };
}

/**
 * Process all articles in the database
 */
async function processArticles() {
    const client = new Client(dbConfig);
    
    try {
        await client.connect();
        log('Connected to database', 'green');
        
        // Get all articles with content (or specific article if ID provided)
        let query, queryParams;
        
        if (articleId) {
            query = `
                SELECT id, name, content 
                FROM articles 
                WHERE id = $1 
                AND content IS NOT NULL 
                AND content != ''
            `;
            queryParams = [articleId];
        } else {
            query = `
                SELECT id, name, content 
                FROM articles 
                WHERE content IS NOT NULL 
                AND content != ''
                ORDER BY id
            `;
            queryParams = [];
        }
        
        const result = await client.query(query, queryParams);
        
        if (articleId) {
            log(`Found article ${articleId} to process`, 'blue');
        } else {
            log(`Found ${result.rows.length} articles to process`, 'blue');
        }
        
        let processedCount = 0;
        let changedCount = 0;
        let totalChanges = 0;
        
        for (const article of result.rows) {
            verbose(`Processing article ${article.id}: "${article.name}"`);
            
            const processed = removeTableWrappers(article.content);
            
            if (processed.changed) {
                changedCount++;
                totalChanges += processed.changes.length;
                
                log(`\n📝 Article ${article.id}: "${article.name}"`, 'yellow');
                processed.changes.forEach(change => {
                    verbose(`  ✓ ${change}`, 'green');
                });
                
                if (!isDryRun) {
                    // Update the article in the database
                    const updateQuery = 'UPDATE articles SET content = $1, updated_at = NOW() WHERE id = $2';
                    await client.query(updateQuery, [processed.content, article.id]);
                    verbose('  💾 Updated in database', 'green');
                } else {
                    verbose('  🔍 Would update in database (dry run)', 'yellow');
                }
            }
            
            processedCount++;
            
            // Show progress for large datasets (only if processing multiple articles)
            if (!articleId && processedCount % 10 === 0) {
                log(`Progress: ${processedCount}/${result.rows.length} articles processed`, 'cyan');
            }
        }
        
        // Summary
        log('\n' + '='.repeat(60), 'blue');
        log('📊 SUMMARY', 'blue');
        log('='.repeat(60), 'blue');
        log(`Total articles processed: ${processedCount}`, 'cyan');
        log(`Articles with changes: ${changedCount}`, 'green');
        log(`Total changes made: ${totalChanges}`, 'green');
        
        if (isDryRun) {
            log('\n🔍 This was a dry run - no changes were made to the database', 'yellow');
            log('Run without --dry-run to apply changes', 'yellow');
        } else {
            log('\n✅ All changes have been applied to the database', 'green');
        }
        
    } catch (error) {
        log(`❌ Error: ${error.message}`, 'red');
        console.error(error);
        process.exit(1);
    } finally {
        await client.end();
        log('Database connection closed', 'cyan');
    }
}

// Main execution
async function main() {
    log('🧹 Table Wrapper Removal Script', 'blue');
    log('=====================================', 'blue');
    
    if (isDryRun) {
        log('🔍 Running in DRY RUN mode - no changes will be made', 'yellow');
    }
    
    if (articleId) {
        log(`🎯 Targeting single article: ${articleId}`, 'cyan');
    }
    
    await processArticles();
}

// Run the script
main().catch(error => {
    log(`❌ Fatal error: ${error.message}`, 'red');
    console.error(error);
    process.exit(1);
});