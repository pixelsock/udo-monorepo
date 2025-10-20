#!/bin/bash

# Simple Directus Schema Migration Script
# Migrates schema from local to production using Directus CLI

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_DIR="$PROJECT_ROOT/schema-snapshots"
LOCAL_SNAPSHOT="$SNAPSHOT_DIR/local-schema-$(date +%Y%m%d-%H%M%S).yaml"
PROD_SNAPSHOT="$SNAPSHOT_DIR/prod-schema-$(date +%Y%m%d-%H%M%S).yaml"

# Parse arguments
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Functions
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_header() {
    echo -e "\n${MAGENTA}$1${NC}"
}

# Create snapshot directory
mkdir -p "$SNAPSHOT_DIR"

log_header "============================================================"
log_header "DIRECTUS SCHEMA MIGRATION"
log_header "Local → Production"
log_header "============================================================"

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - Showing what would happen without applying changes"
    echo ""
fi

# Step 1: Take local snapshot
log_header "\n📸 Step 1: Taking snapshot of LOCAL schema..."

# Temporarily rename .env to prevent it from being loaded
if [ -f "$PROJECT_ROOT/.env" ]; then
    mv "$PROJECT_ROOT/.env" "$PROJECT_ROOT/.env.backup.$$"
    ENV_BACKED_UP=true
else
    ENV_BACKED_UP=false
fi

# Create temporary local .env
cat > "$PROJECT_ROOT/.env" << EOF
DB_CLIENT=pg
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=directus
DB_USER=directus
DB_PASSWORD=directus
PUBLIC_URL=http://localhost:8056
EOF

if ! npx directus schema snapshot --yes "$LOCAL_SNAPSHOT" 2>&1; then
    # Restore original .env on error
    rm -f "$PROJECT_ROOT/.env"
    if [ "$ENV_BACKED_UP" = true ]; then
        mv "$PROJECT_ROOT/.env.backup.$$" "$PROJECT_ROOT/.env"
    fi
    log_error "Failed to create local schema snapshot"
    log_error "Make sure local Directus is running on http://localhost:8056"
    exit 1
fi

# Remove temporary .env and restore original
rm -f "$PROJECT_ROOT/.env"
if [ "$ENV_BACKED_UP" = true ]; then
    mv "$PROJECT_ROOT/.env.backup.$$" "$PROJECT_ROOT/.env"
fi

log_success "Local schema snapshot saved to: $LOCAL_SNAPSHOT"
log "Snapshot size: $(du -h "$LOCAL_SNAPSHOT" | cut -f1)"

# Step 2: Take production snapshot (for comparison)
log_header "\n📸 Step 2: Taking snapshot of PRODUCTION schema..."
log_warning "Switching to production environment..."

# Backup .env again if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    mv "$PROJECT_ROOT/.env" "$PROJECT_ROOT/.env.backup.$$"
    ENV_BACKED_UP=true
else
    ENV_BACKED_UP=false
fi

# Create temporary production .env
cat > "$PROJECT_ROOT/.env" << EOF
DB_CLIENT=pg
DB_HOST=dpg-d1gsdjjipnbc73b509f0-a.oregon-postgres.render.com
DB_PORT=5432
DB_DATABASE=cltudo_postgres
DB_USER=admin
DB_PASSWORD=00N0rXxlwSL25CoLxxwcW6r6jTFdrkeB
PUBLIC_URL=https://udo-backend-y1w0.onrender.com
EOF

if ! npx directus schema snapshot --yes "$PROD_SNAPSHOT" 2>&1; then
    # Restore original .env on error
    rm -f "$PROJECT_ROOT/.env"
    if [ "$ENV_BACKED_UP" = true ]; then
        mv "$PROJECT_ROOT/.env.backup.$$" "$PROJECT_ROOT/.env"
    fi
    log_error "Failed to create production schema snapshot"
    log_error "Make sure you can connect to production database"
    exit 1
fi

# Remove temporary .env and restore original
rm -f "$PROJECT_ROOT/.env"
if [ "$ENV_BACKED_UP" = true ]; then
    mv "$PROJECT_ROOT/.env.backup.$$" "$PROJECT_ROOT/.env"
fi

log_success "Production schema snapshot saved to: $PROD_SNAPSHOT"
log "Snapshot size: $(du -h "$PROD_SNAPSHOT" | cut -f1)"

# Step 3: Show diff summary
log_header "\n🔍 Step 3: Analyzing differences..."

# Count differences in collections
local_collections=$(grep -c "^  - collection:" "$LOCAL_SNAPSHOT" || echo 0)
prod_collections=$(grep -c "^  - collection:" "$PROD_SNAPSHOT" || echo 0)
diff_collections=$((local_collections - prod_collections))

echo ""
log "Collections in local: $local_collections"
log "Collections in production: $prod_collections"

if [ $diff_collections -gt 0 ]; then
    log_success "New collections to create: $diff_collections"
elif [ $diff_collections -lt 0 ]; then
    log_warning "Collections to remove: ${diff_collections#-}"
else
    log "No collection count changes"
fi

# Show new collections
echo ""
log "Analyzing schema differences..."
echo ""
log_header "NEW COLLECTIONS IN LOCAL (will be created in production):"
comm -13 \
    <(grep "^  - collection:" "$PROD_SNAPSHOT" | sed 's/^  - collection: //' | sort) \
    <(grep "^  - collection:" "$LOCAL_SNAPSHOT" | sed 's/^  - collection: //' | sort) | \
    while read -r collection; do
        echo -e "  ${GREEN}➕ $collection${NC}"
    done

log_header "\nREMOVED COLLECTIONS (exist in prod but not in local):"
comm -23 \
    <(grep "^  - collection:" "$PROD_SNAPSHOT" | sed 's/^  - collection: //' | sort) \
    <(grep "^  - collection:" "$LOCAL_SNAPSHOT" | sed 's/^  - collection: //' | sort) | \
    while read -r collection; do
        echo -e "  ${RED}❌ $collection${NC}"
    done

# Step 4: Apply or show dry run
if [ "$DRY_RUN" = true ]; then
    log_header "\n🔍 DRY RUN COMPLETE"
    log "No changes were applied to production"
    log "To apply these changes, run without --dry-run flag"
    log ""
    log "Full schema files saved:"
    log "  Local: $LOCAL_SNAPSHOT"
    log "  Production: $PROD_SNAPSHOT"
    exit 0
fi

# Step 5: Confirm before applying
if [ "$FORCE" != true ]; then
    echo ""
    log_warning "IMPORTANT: This will modify your PRODUCTION database!"
    log_warning ""
    log_warning "Safety checks:"
    log_warning "  1. Have you backed up production? (./scripts/backup-production-database.sh)"
    log_warning "  2. Have you reviewed the changes above?"
    log_warning "  3. Are you ready to proceed?"
    echo ""
    read -p "$(echo -e ${YELLOW}"Type 'yes' to apply changes to production: "${NC})" confirm

    if [ "$confirm" != "yes" ]; then
        log_error "Migration cancelled"
        exit 0
    fi
fi

# Step 6: Apply schema
log_header "\n🚀 Step 4: Applying schema to PRODUCTION..."
log "This may take a few minutes..."

if npx directus schema apply --yes "$LOCAL_SNAPSHOT" 2>&1; then
    echo ""
    log_success "Schema migration completed successfully!"
    echo ""
    log "Verification steps:"
    log "  1. Visit https://admin.charlotteudo.org"
    log "  2. Go to Settings → Data Model"
    log "  3. Verify all collections and fields are present"
    log "  4. Test your application"
    echo ""
else
    echo ""
    log_error "Schema migration failed!"
    log_error "Your production database was NOT modified"
    log_error "Check the error messages above for details"
    exit 1
fi
