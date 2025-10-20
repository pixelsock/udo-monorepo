# Table Wrapper Removal Scripts

This directory contains scripts to remove table wrapper structures that were previously added to tables in articles by the `enhanceTableStructure` function.

## Background

Previously, the input-rich-text-html extension automatically wrapped all tables with enhanced container structures that included:

- `.enhanced-table-container` - Main wrapper container
- `.table-toolbar` - Toolbar with title and fullscreen button  
- `.table-wrapper` - Inner wrapper for the table
- `.table-title-row` - Separate div for table titles

Since the table wrapper functionality has been removed from the extension, these existing wrappers need to be cleaned up from articles in the database.

## Available Scripts

### 1. Node.js Script (Recommended)

**File:** `remove-table-wrappers.js`

This is the most robust option that properly parses HTML and handles edge cases.

**Features:**
- Parses HTML using JSDOM for accurate processing
- Extracts table titles and converts them to proper title rows within tables
- Handles both `.table-wrapper` and `.enhanced-table-container` structures
- Provides detailed logging and dry-run mode
- Preserves table functionality while removing wrapper bloat

**Usage:**
```bash
# Dry run (preview changes)
node scripts/remove-table-wrappers.js --dry-run --verbose

# Apply changes
node scripts/remove-table-wrappers.js --verbose
```

### 2. Shell Script Wrapper (Easiest)

**File:** `remove-table-wrappers.sh`

Provides a user-friendly interface to the Node.js script with automatic dependency installation.

**Usage:**
```bash
# Dry run against local database
./scripts/remove-table-wrappers.sh dry-run local

# Apply changes to local database
./scripts/remove-table-wrappers.sh apply local

# Dry run against production (requires DATABASE_URL)
./scripts/remove-table-wrappers.sh dry-run production

# Apply to production (requires confirmation)
./scripts/remove-table-wrappers.sh apply production
```

### 3. SQL Script (Simple)

**File:** `remove-table-wrappers.sql`

A pure SQL approach using regex for simple cases.

**Usage:**
```bash
# Local database
psql -h localhost -U directus -d charlotte_udo -f scripts/remove-table-wrappers.sql

# Production (with DATABASE_URL)
psql "$DATABASE_URL" -f scripts/remove-table-wrappers.sql
```

**Note:** The SQL script is less sophisticated and may not handle all edge cases. Use the Node.js script for production environments.

## What Gets Removed

### Before (Old Structure)
```html
<div class="enhanced-table-container">
  <div class="table-toolbar">
    <div class="table-title-section">
      <span class="table-title-text">My Table Title</span>
    </div>
    <div class="table-controls">
      <button class="table-fullscreen-btn">...</button>
    </div>
  </div>
  <div class="table-wrapper">
    <table class="udo-table">
      <tr><td>Data</td></tr>
    </table>
  </div>
</div>
```

### After (Clean Structure)
```html
<table class="udo-table">
  <tr>
    <td colspan="1" class="ag-title-row">My Table Title</td>
  </tr>
  <tr><td>Data</td></tr>
</table>
```

## Environment Variables

### Local Database
```bash
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=charlotte_udo
DB_USER=directus
DB_PASSWORD=directus
```

### Production Database
```bash
DATABASE_URL=postgresql://user:password@host:port/database
```

## Prerequisites

### Node.js Script
- Node.js (v14 or higher)
- npm packages: `pg`, `jsdom` (auto-installed by shell script)

### SQL Script
- PostgreSQL client (`psql`)
- Database access credentials

## Safety Features

1. **Dry Run Mode**: All scripts support preview mode to see changes before applying
2. **Detailed Logging**: Shows exactly what changes will be made
3. **Production Confirmation**: Extra confirmation required for production changes
4. **Transaction Safety**: SQL operations use transactions where possible
5. **Backup Recommendation**: Always backup your database before running

## Recommended Workflow

1. **Test Locally First**
   ```bash
   ./scripts/remove-table-wrappers.sh dry-run local
   ```

2. **Apply to Local**
   ```bash
   ./scripts/remove-table-wrappers.sh apply local
   ```

3. **Test Your Application**
   - Verify tables display correctly
   - Check that functionality still works

4. **Backup Production**
   ```bash
   pg_dump "$DATABASE_URL" > backup-before-wrapper-removal.sql
   ```

5. **Preview Production Changes**
   ```bash
   ./scripts/remove-table-wrappers.sh dry-run production
   ```

6. **Apply to Production**
   ```bash
   ./scripts/remove-table-wrappers.sh apply production
   ```

## Troubleshooting

### Common Issues

1. **"pg module not found"**
   ```bash
   npm install pg
   ```

2. **"jsdom module not found"**
   ```bash
   npm install jsdom
   ```

3. **Database connection failed**
   - Check your environment variables
   - Verify database is running
   - Check network connectivity

4. **Permission denied on script**
   ```bash
   chmod +x scripts/remove-table-wrappers.sh
   ```

### Verification

After running the script, verify the results:

```sql
-- Check for remaining wrappers
SELECT id, title 
FROM articles 
WHERE content LIKE '%table-wrapper%' 
   OR content LIKE '%enhanced-table-container%'
   OR content LIKE '%table-toolbar%';

-- Should return no results if successful
```

## Support

If you encounter issues:

1. Run with `--verbose` flag for detailed output
2. Check the logs for specific error messages
3. Verify your database connection settings
4. Try the dry-run mode first to identify issues

## Files Modified

The scripts will update the `articles` table:
- **Column:** `content` 
- **Action:** Remove wrapper HTML structures
- **Timestamp:** Updates `updated_at` field