#!/bin/bash

# Sync Production Database to Local Development
# Safely pulls production data and restores to local Docker database

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DUMP_FILE="$PROJECT_ROOT/production-dump.sql"
BACKUP_DIR="$PROJECT_ROOT/backups/local"

# Production database configuration (from docker-compose.yml)
PROD_DB_HOST="dpg-d1gsdjjipnbc73b509f0-a"
PROD_DB_PORT="5432"
PROD_DB_DATABASE="cltudo_postgres"
PROD_DB_USER="admin"
PROD_DB_PASSWORD="00N0rXxlwSL25CoLxxwcW6r6jTFdrkeB"

# Local database configuration (from docker-compose.local.yml)
LOCAL_CONTAINER="directus-postgres-local"
LOCAL_DB_USER="directus"
LOCAL_DB_NAME="directus"

# Script options
DRY_RUN=false
VERBOSE=false
SKIP_BACKUP=false
SKIP_DUMP=false

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Sync production database to local development environment.

OPTIONS:
    --dry-run           Show what would be done without executing
    --verbose           Enable verbose output
    --skip-backup       Skip backing up local database
    --skip-dump         Use existing production-dump.sql (don't create new)
    --help              Show this help message

EXAMPLES:
    $0                      # Full sync: dump production, backup local, restore
    $0 --skip-dump          # Use existing dump file
    $0 --dry-run            # Preview what would happen
    $0 --verbose            # Show detailed progress

PREREQUISITES:
    - Docker running with local Directus stack
    - PostgreSQL client tools (pg_dump, psql)
    - Network access to production database

EOF
}

# Function for logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function for verbose logging
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "VERBOSE: $1"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    verbose_log "Checking prerequisites..."

    # Check if pg_dump is available
    if ! command -v pg_dump &> /dev/null; then
        echo "Error: pg_dump not found. Please install PostgreSQL client tools."
        exit 1
    fi

    # Check if psql is available
    if ! command -v psql &> /dev/null; then
        echo "Error: psql not found. Please install PostgreSQL client tools."
        exit 1
    fi

    # Check if Docker is running
    if ! docker info &> /dev/null; then
        echo "Error: Docker is not running. Please start Docker."
        exit 1
    fi

    # Check if local database container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${LOCAL_CONTAINER}$"; then
        echo "Error: Local database container '${LOCAL_CONTAINER}' is not running."
        echo "Start it with: docker compose -f docker-compose.local.yml up -d postgres"
        exit 1
    fi

    verbose_log "Prerequisites check passed"
}

# Function to backup local database
backup_local_database() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        verbose_log "Skipping local database backup"
        return
    fi

    log "Backing up local database..."

    local timestamp=$(date +"%Y-%m-%dT%H-%M-%S")
    local backup_file="$BACKUP_DIR/local-backup-$timestamp.sql"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would backup local database to: $backup_file"
        return
    fi

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Create backup
    docker exec "$LOCAL_CONTAINER" pg_dump \
        -U "$LOCAL_DB_USER" \
        -d "$LOCAL_DB_NAME" \
        --clean \
        --if-exists \
        > "$backup_file"

    log "Local database backed up to: $backup_file"
    log "Backup size: $(du -h "$backup_file" | cut -f1)"
}

# Function to dump production database
dump_production_database() {
    if [[ "$SKIP_DUMP" == "true" ]]; then
        log "Using existing dump file: $DUMP_FILE"

        if [[ ! -f "$DUMP_FILE" ]]; then
            echo "Error: Dump file not found: $DUMP_FILE"
            echo "Run without --skip-dump to create a new dump."
            exit 1
        fi

        log "Existing dump size: $(du -h "$DUMP_FILE" | cut -f1)"
        log "Dump created: $(date -r "$DUMP_FILE" +'%Y-%m-%d %H:%M:%S')"
        return
    fi

    log "Dumping production database..."
    verbose_log "Production host: $PROD_DB_HOST"
    verbose_log "Production database: $PROD_DB_DATABASE"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would dump production database:"
        echo "  Host: $PROD_DB_HOST"
        echo "  Database: $PROD_DB_DATABASE"
        echo "  Output: $DUMP_FILE"
        return
    fi

    # Test production connection
    verbose_log "Testing production database connection..."
    export PGPASSWORD="$PROD_DB_PASSWORD"

    if ! pg_isready -h "$PROD_DB_HOST" -p "$PROD_DB_PORT" -U "$PROD_DB_USER" -d "$PROD_DB_DATABASE" &> /dev/null; then
        echo "Error: Cannot connect to production database"
        echo "Host: $PROD_DB_HOST:$PROD_DB_PORT"
        exit 1
    fi

    verbose_log "Production connection successful"

    # Create production dump
    log "Dumping database (this may take a few minutes)..."

    pg_dump \
        -h "$PROD_DB_HOST" \
        -p "$PROD_DB_PORT" \
        -U "$PROD_DB_USER" \
        -d "$PROD_DB_DATABASE" \
        --clean \
        --if-exists \
        > "$DUMP_FILE"

    log "Production database dumped to: $DUMP_FILE"
    log "Dump size: $(du -h "$DUMP_FILE" | cut -f1)"
}

# Function to restore to local database
restore_to_local() {
    log "Restoring to local database..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would restore $DUMP_FILE to local database"
        echo "  Container: $LOCAL_CONTAINER"
        echo "  Database: $LOCAL_DB_NAME"
        return
    fi

    # Restore the dump
    verbose_log "Restoring database dump..."
    docker exec -i "$LOCAL_CONTAINER" psql \
        -U "$LOCAL_DB_USER" \
        -d "$LOCAL_DB_NAME" \
        < "$DUMP_FILE" 2>&1 | grep -v "^ERROR:" | grep -v "^NOTICE:" || true

    log "Database restored successfully"
}

# Function to verify restoration
verify_restoration() {
    if [[ "$DRY_RUN" == "true" ]]; then
        verbose_log "Skipping verification in dry-run mode"
        return
    fi

    verbose_log "Verifying restoration..."

    # Count tables
    local table_count
    table_count=$(docker exec "$LOCAL_CONTAINER" psql \
        -U "$LOCAL_DB_USER" \
        -d "$LOCAL_DB_NAME" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" \
        | tr -d ' ')

    log "Verification: Found $table_count tables in local database"

    # Check if Directus core tables exist
    local directus_tables
    directus_tables=$(docker exec "$LOCAL_CONTAINER" psql \
        -U "$LOCAL_DB_USER" \
        -d "$LOCAL_DB_NAME" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'directus_%';" \
        | tr -d ' ')

    log "Verification: Found $directus_tables Directus tables"

    if [[ "$directus_tables" -eq 0 ]]; then
        echo "Warning: No Directus tables found. Restoration may have failed."
        return 1
    fi

    log "Verification: Restoration appears successful"
}

# Function to show next steps
show_next_steps() {
    cat << EOF

✅ Sync completed successfully!

Next steps:
  1. Restart Directus to use the new database:
     docker compose -f docker-compose.local.yml restart directus

  2. Access your local Directus:
     http://localhost:8056

  3. Login with production credentials:
     Email: nick@stump.works
     Password: (production password)

Note: Your local data was backed up to:
  $BACKUP_DIR/

EOF
}

# Main sync function
main() {
    log "Starting production to local sync"

    check_prerequisites
    backup_local_database
    dump_production_database
    restore_to_local
    verify_restoration

    if [[ "$DRY_RUN" != "true" ]]; then
        log "Sync completed successfully!"
        show_next_steps
    else
        log "DRY RUN completed - no changes made"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --skip-dump)
            SKIP_DUMP=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main
