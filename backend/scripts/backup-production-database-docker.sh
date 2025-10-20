#!/bin/bash

# Backup Production Database using Docker PostgreSQL client
# This avoids version mismatch issues

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
BACKUP_FILE="production-backup-$TIMESTAMP.sql"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

log "Starting production database backup using Docker..."
log "Host: $PROD_DB_HOST"
log "Database: $PROD_DB_DATABASE"
echo ""

# Use Docker container's pg_dump to avoid version mismatch
log "Using Docker PostgreSQL client (matches production version)..."

docker exec directus-postgres-local pg_dump \
    -h "$PROD_DB_HOST" \
    -p "$PROD_DB_PORT" \
    -U "$PROD_DB_USER" \
    -d "$PROD_DB_DATABASE" \
    --clean \
    --if-exists \
    > "$BACKUP_DIR/$BACKUP_FILE" <<EOF
$PROD_DB_PASSWORD
EOF

if [ $? -eq 0 ] && [ -s "$BACKUP_DIR/$BACKUP_FILE" ]; then
    echo ""
    log_success "Backup completed successfully!"
    log "Backup file: $BACKUP_DIR/$BACKUP_FILE"
    log "Backup size: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"
    echo ""
else
    echo ""
    log_error "Backup failed or file is empty!"
    exit 1
fi
