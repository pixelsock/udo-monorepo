#!/bin/bash

#!/bin/bash

# Table Wrapper Removal Script
# Removes table wrapper structures from articles in the database
#
# Usage:
#   ./remove-table-wrappers.sh <mode> <environment> [article-id]
#
# Arguments:
#   mode         - "dry-run" or "apply"
#   environment  - "local" or "production"
#   article-id   - (optional) specific article ID to process
#
# Examples:
#   ./remove-table-wrappers.sh dry-run local
#   ./remove-table-wrappers.sh dry-run local fc1a4b2e-c075-4608-b93f-e508af32b69d
#   ./remove-table-wrappers.sh apply production

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Show help
show_help() {
    echo -e "${BLUE}Table Wrapper Removal Script${NC}"
    echo -e "${BLUE}============================${NC}"
    echo ""
    echo "Usage: $0 <mode> <environment> [article-id]"
    echo ""
    echo "Arguments:"
    echo "  mode         - 'dry-run' or 'apply'"
    echo "  environment  - 'local' or 'production'"
    echo "  article-id   - (optional) specific article ID to process"
    echo ""
    echo "Examples:"
    echo "  $0 dry-run local"
    echo "  $0 dry-run local fc1a4b2e-c075-4608-b93f-e508af32b69d"
    echo "  $0 apply production"
    echo ""
}

# Parse arguments
if [ $# -lt 2 ]; then
    show_help
    exit 1
fi

MODE="$1"
TARGET="$2"
ARTICLE_ID="$3"

# Validate mode
case "$MODE" in
    "dry-run"|"apply")
        ;;
    *)
        echo -e "${RED}❌ Invalid mode: $MODE${NC}"
        echo "Mode must be 'dry-run' or 'apply'"
        show_help
        exit 1
        ;;
esac

# Validate environment
case "$TARGET" in
    "local"|"production")
        ;;
    *)
        echo -e "${RED}❌ Invalid environment: $TARGET${NC}"
        echo "Environment must be 'local' or 'production'"
        show_help
        exit 1
        ;;
esac

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
MODE="dry-run"
TARGET="local"

# Parse arguments
for arg in "$@"; do
    case $arg in
        "apply")
            MODE="apply"
            ;;
        "dry-run")
            MODE="dry-run"
            ;;
        "production")
            TARGET="production"
            ;;
        "local")
            TARGET="local"
            ;;
        *)
            echo -e "${RED}Unknown argument: $arg${NC}"
            echo "Usage: $0 [dry-run|apply] [production|local]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🧹 Table Wrapper Removal Script${NC}"
echo -e "${BLUE}====================================${NC}"
echo ""

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed or not in PATH${NC}"
    echo "Please install Node.js to run this script"
    exit 1
fi

# Check if required Node.js packages are available
SCRIPT_DIR="$(dirname "$0")"
NODE_SCRIPT="$SCRIPT_DIR/remove-table-wrappers.js"

if [ ! -f "$NODE_SCRIPT" ]; then
    echo -e "${RED}❌ Node.js script not found: $NODE_SCRIPT${NC}"
    exit 1
fi

# Set up environment variables based on target
if [ "$TARGET" = "production" ]; then
    echo -e "${YELLOW}🚨 Running against PRODUCTION database${NC}"
    
    # Check if DATABASE_URL is set for production
    if [ -z "$DATABASE_URL" ]; then
        echo -e "${RED}❌ Production mode requires DATABASE_URL environment variable${NC}"
        echo "Set DATABASE_URL to your production database connection string"
        exit 1
    fi
    
    # Confirm production changes
    if [ "$MODE" = "apply" ]; then
        echo -e "${RED}⚠️  You are about to modify the PRODUCTION database!${NC}"
        echo -e "${YELLOW}This will remove table wrappers from all articles.${NC}"
        echo ""
        read -p "Are you absolutely sure you want to continue? (type 'YES' to confirm): " confirmation
        
        if [ "$confirmation" != "YES" ]; then
            echo "Operation cancelled."
            exit 0
        fi
    fi
    
else
    echo -e "${CYAN}🏠 Running against LOCAL database${NC}"
    
    # For local, we'll use Docker container directly to avoid connection conflicts
    echo -e "${YELLOW}🐳 Using Docker container for local database analysis${NC}"
    
    if [ "$MODE" = "dry-run" ]; then
        echo -e "${BLUE}� Running dry-run analysis on local database...${NC}"
        
        echo -e "${CYAN}📊 Analyzing articles for table wrapper structures...${NC}"
        
        docker exec directus-postgres-local psql -U directus -d directus -c "
            SELECT 
                COUNT(*) as total_articles,
                COUNT(CASE WHEN content LIKE '%enhanced-table-container%' THEN 1 END) as articles_with_enhanced_containers,
                COUNT(CASE WHEN content LIKE '%table-toolbar%' THEN 1 END) as articles_with_toolbars,
                COUNT(CASE WHEN content LIKE '%table-wrapper%' THEN 1 END) as articles_with_wrappers
            FROM articles;
        "
        
        echo -e "${CYAN}📝 Sample articles with table wrappers (first 5):${NC}"
        docker exec directus-postgres-local psql -U directus -d directus -c "
            SELECT 
                id, 
                name,
                LENGTH(content) as content_length,
                CASE 
                    WHEN content LIKE '%enhanced-table-container%' THEN 'Has enhanced-table-container'
                    WHEN content LIKE '%table-toolbar%' THEN 'Has table-toolbar'  
                    WHEN content LIKE '%table-wrapper%' THEN 'Has table-wrapper'
                    ELSE 'No wrappers found'
                END as wrapper_status
            FROM articles 
            WHERE content LIKE '%enhanced-table-container%' 
               OR content LIKE '%table-toolbar%' 
               OR content LIKE '%table-wrapper%'
            LIMIT 5;
        "
        
        echo -e "${GREEN}✅ Dry-run analysis complete. No changes were made.${NC}"
        echo -e "${YELLOW}💡 If you want to proceed with removing wrappers, we'll need to implement the full Node.js approach${NC}"
        exit 0
    else
        echo -e "${RED}⚠️ Live execution mode not yet implemented for Docker approach${NC}"
        echo -e "${YELLOW}💡 Please run in dry-run mode first: $0 dry-run local${NC}"
        exit 1
    fi
fi

# Show configuration
echo "Configuration:"
echo "  Mode: $MODE"
echo "  Target: $TARGET"
if [ "$TARGET" = "production" ]; then
    echo "  Database: Production (via DATABASE_URL)"
else
    echo "  Database: $DB_HOST:$DB_PORT/$DB_DATABASE"
fi
echo ""

# Install required packages if they don't exist
echo -e "${CYAN}📦 Checking Node.js dependencies...${NC}"
cd "$(dirname "$0")/.."

# Check if pg and jsdom are available
if ! node -e "require('pg')" 2>/dev/null; then
    echo -e "${YELLOW}Installing pg package...${NC}"
    npm install pg
fi

if ! node -e "require('jsdom')" 2>/dev/null; then
    echo -e "${YELLOW}Installing jsdom package...${NC}"
    npm install jsdom
fi

echo -e "${GREEN}✓ Dependencies ready${NC}"
echo ""

# Build the command
NODE_ARGS=""
if [ "$MODE" = "dry-run" ]; then
    NODE_ARGS="$NODE_ARGS --dry-run"
fi
NODE_ARGS="$NODE_ARGS --verbose"

# Run the Node.js script
echo -e "${BLUE}🚀 Starting table wrapper removal...${NC}"
echo ""

if node "$NODE_SCRIPT" $NODE_ARGS; then
    echo ""
    if [ "$MODE" = "dry-run" ]; then
        echo -e "${GREEN}✅ Dry run completed successfully!${NC}"
        echo -e "${YELLOW}Run with 'apply' argument to make actual changes:${NC}"
        echo "  $0 apply $TARGET"
    else
        echo -e "${GREEN}✅ Table wrappers removed successfully!${NC}"
        
        if [ "$TARGET" = "local" ]; then
            echo -e "${CYAN}💡 You may want to restart your local Directus instance:${NC}"
            echo "  docker compose -f docker-compose.local.yml restart directus"
        fi
    fi
else
    echo -e "${RED}❌ Script failed with errors${NC}"
    exit 1
fi