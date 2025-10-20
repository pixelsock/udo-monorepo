#!/bin/bash

# Deploy Orama Analytics Tables to Production
# This script creates the necessary database tables for Orama search analytics
#
# Usage:
#   ./scripts/deployment/deploy-orama-analytics.sh
#
# Environment Variables Required:
#   - DATABASE_URL: Production database connection string
#   OR
#   - DB_HOST, DB_PORT, DB_DATABASE, DB_USER, DB_PASSWORD

set -e

echo "========================================"
echo "Orama Analytics Tables Deployment"
echo "========================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running in production environment
if [ -z "$DATABASE_URL" ] && [ -z "$DB_HOST" ]; then
    echo -e "${YELLOW}⚠️  No database connection found. Using Render environment variables...${NC}"
    
    # Try to use Render's environment variables if available
    if [ -n "$DATABASE_URL_POOL" ]; then
        DATABASE_URL="$DATABASE_URL_POOL"
        echo -e "${GREEN}✓ Using Render DATABASE_URL_POOL${NC}"
    elif [ -n "$DATABASE_PRIVATE_URL" ]; then
        DATABASE_URL="$DATABASE_PRIVATE_URL"
        echo -e "${GREEN}✓ Using Render DATABASE_PRIVATE_URL${NC}"
    else
        echo -e "${RED}❌ No database connection available. Please set DATABASE_URL or DB_* environment variables.${NC}"
        exit 1
    fi
fi

# Function to execute SQL
execute_sql() {
    local sql_file=$1
    
    if [ -n "$DATABASE_URL" ]; then
        echo "Executing SQL using DATABASE_URL..."
        psql "$DATABASE_URL" -f "$sql_file" -v ON_ERROR_STOP=1
    else
        echo "Executing SQL using individual DB parameters..."
        PGPASSWORD="$DB_PASSWORD" psql \
            -h "$DB_HOST" \
            -p "${DB_PORT:-5432}" \
            -U "$DB_USER" \
            -d "$DB_DATABASE" \
            -f "$sql_file" \
            -v ON_ERROR_STOP=1
    fi
}

# Function to check table existence
check_tables() {
    local query="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('orama_search_analytics', 'orama_search_queries', 'orama_user_sessions', 'orama_index_snapshots');"
    
    if [ -n "$DATABASE_URL" ]; then
        count=$(psql "$DATABASE_URL" -t -c "$query" | tr -d ' ')
    else
        count=$(PGPASSWORD="$DB_PASSWORD" psql \
            -h "$DB_HOST" \
            -p "${DB_PORT:-5432}" \
            -U "$DB_USER" \
            -d "$DB_DATABASE" \
            -t -c "$query" | tr -d ' ')
    fi
    
    echo "$count"
}

# Main deployment process
main() {
    echo "1. Checking existing tables..."
    existing_tables=$(check_tables)
    echo "   Found $existing_tables of 4 required tables"
    echo ""
    
    if [ "$existing_tables" -eq "4" ]; then
        echo -e "${YELLOW}⚠️  All tables already exist. Do you want to recreate them? (y/N)${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 0
        fi
    fi
    
    echo "2. Creating Orama analytics tables..."
    SQL_FILE="$(dirname "$0")/orama-analytics-tables.sql"
    
    if [ ! -f "$SQL_FILE" ]; then
        echo -e "${RED}❌ SQL file not found: $SQL_FILE${NC}"
        exit 1
    fi
    
    if execute_sql "$SQL_FILE"; then
        echo -e "${GREEN}✓ SQL executed successfully${NC}"
    else
        echo -e "${RED}❌ SQL execution failed${NC}"
        exit 1
    fi
    
    echo ""
    echo "3. Verifying table creation..."
    final_count=$(check_tables)
    
    if [ "$final_count" -eq "4" ]; then
        echo -e "${GREEN}✅ Success! All 4 Orama analytics tables are now in place:${NC}"
        echo "   - orama_search_analytics"
        echo "   - orama_search_queries"
        echo "   - orama_user_sessions"
        echo "   - orama_index_snapshots"
    else
        echo -e "${RED}❌ Error: Only $final_count of 4 tables were created${NC}"
        exit 1
    fi
    
    echo ""
    echo "========================================"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo "========================================"
    echo ""
    echo "The Orama search analytics system is now ready."
    echo "Search queries will be tracked and analytics will be available."
}

# Run main function
main