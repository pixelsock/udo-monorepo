#!/bin/bash

# Backup Production Database
# Creates a timestamped backup of the production PostgreSQL database

set -euo pipefail

# Production database configuration
PROD_DB_HOST="dpg-d1gsdjjipnbc73b509f0-a.oregon-postgres.render.com"
PROD_DB_PORT="5432"
PROD_DB_DATABASE="cltudo_postgres"
PROD_DB_USER="admin"
PROD_DB_PASSWORD="00N0rXxlwSL25CoLxxwcW6r6jTFdrkeB"

# Backup configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_ROOT/backups/production"
TIMESTAMP=$(date +"%Y-%m-%dT%H-%M-%S")
BACKUP_FILE="$BACKUP_DIR/production-backup-$TIMESTAMP.sql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function for logging
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Check if pg_dump is available
if ! command -v pg_dump &> /dev/null; then
    log_error "pg_dump not found. Please install PostgreSQL client tools."
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Starting production database backup..."
log "Host: $PROD_DB_HOST"
log "Database: $PROD_DB_DATABASE"
log "Backup file: $BACKUP_FILE"
echo ""

# Test connection
log "Testing database connection..."
export PGPASSWORD="$PROD_DB_PASSWORD"

if ! pg_isready -h "$PROD_DB_HOST" -p "$PROD_DB_PORT" -U "$PROD_DB_USER" -d "$PROD_DB_DATABASE" &> /dev/null; then
    log_error "Cannot connect to production database"
    log_error "Host: $PROD_DB_HOST:$PROD_DB_PORT"
    exit 1
fi

log_success "Database connection successful"
echo ""

# Create backup
log "Creating backup (this may take a few minutes)..."
echo ""

pg_dump \
    -h "$PROD_DB_HOST" \
    -p "$PROD_DB_PORT" \
    -U "$PROD_DB_USER" \
    -d "$PROD_DB_DATABASE" \
    --clean \
    --if-exists \
    --verbose \
    > "$BACKUP_FILE" 2>&1

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo ""
    log_success "Backup completed successfully!"
    log "Backup file: $BACKUP_FILE"
    log "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
    echo ""

    # Show backup file details
    log "Backup details:"
    log "  Created: $(date -r "$BACKUP_FILE" +'%Y-%m-%d %H:%M:%S')"
    log "  Location: $BACKUP_FILE"
    echo ""

    # List recent backups
    log "Recent backups:"
    ls -lht "$BACKUP_DIR" | head -n 6
    echo ""

    log_success "You can now safely proceed with the schema migration!"
    echo ""
    log "To restore this backup if needed:"
    echo "  PGPASSWORD=\"\$PROD_DB_PASSWORD\" psql -h \"$PROD_DB_HOST\" -p $PROD_DB_PORT -U $PROD_DB_USER -d $PROD_DB_DATABASE < $BACKUP_FILE"
else
    echo ""
    log_error "Backup failed!"
    exit 1
fi
