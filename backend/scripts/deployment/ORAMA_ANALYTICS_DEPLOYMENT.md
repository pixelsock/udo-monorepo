# Orama Search Analytics Deployment Guide

## Issue Description

The Orama search functionality requires analytics tables in the database to properly track search queries, user sessions, and maintain search indexes. These tables are missing in production, which may cause search indexing issues.

## Required Tables

The following 4 tables need to be created in production:

1. **orama_search_analytics** - Tracks individual search queries
2. **orama_search_queries** - Aggregates query statistics  
3. **orama_user_sessions** - Tracks user search sessions
4. **orama_index_snapshots** - Stores search index snapshots

## Deployment Options

### Option 1: Automated Script (Recommended)

SSH into your production server or run in your deployment pipeline:

```bash
# Set your database connection
export DATABASE_URL="your-production-database-url"

# Run the deployment script
./scripts/deployment/deploy-orama-analytics.sh
```

### Option 2: Manual SQL Execution

If you have direct database access, you can run the SQL directly:

```bash
# Using psql with connection string
psql "$DATABASE_URL" -f scripts/deployment/orama-analytics-tables.sql

# Or using individual parameters
psql -h your-host -U your-user -d your-database -f scripts/deployment/orama-analytics-tables.sql
```

### Option 3: Via Render Shell

If deploying on Render:

1. Open the Render dashboard
2. Go to your Directus service
3. Click on "Shell" tab
4. Run:
```bash
cd /directus
psql "$DATABASE_URL" -f scripts/deployment/orama-analytics-tables.sql
```

## Verification

After deployment, verify the tables were created:

```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name LIKE 'orama_%';
```

You should see all 4 tables listed.

## Testing

Once tables are created, test the search functionality:

1. Access your Directus admin panel
2. Try searching in any collection
3. Check if searches are being tracked:

```sql
SELECT COUNT(*) FROM orama_search_analytics;
```

## Rollback

If needed, you can remove the tables:

```sql
DROP TABLE IF EXISTS orama_index_snapshots CASCADE;
DROP TABLE IF EXISTS orama_user_sessions CASCADE;
DROP TABLE IF EXISTS orama_search_queries CASCADE;
DROP TABLE IF EXISTS orama_search_analytics CASCADE;
```

## Notes

- These tables are required for the Orama search bundle to function properly
- The tables will automatically start tracking search analytics once created
- No data migration is needed as these are new analytics tables
- The tables use PostgreSQL-specific features (gen_random_uuid())

## Files Included

- `orama-analytics-tables.sql` - SQL script to create tables
- `deploy-orama-analytics.sh` - Bash script for automated deployment
- This README file

## Support

If you encounter issues:
1. Check database connection permissions
2. Ensure PostgreSQL version is 12+ (for gen_random_uuid support)
3. Verify the user has CREATE TABLE permissions
4. Check Directus logs for any Orama-related errors