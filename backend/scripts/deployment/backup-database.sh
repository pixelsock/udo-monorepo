#!/bin/bash

# Database Backup Script for Directus Production
# Backs up PostgreSQL database with timestamped directory structure

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_BASE_DIR="$PROJECT_ROOT/backups"

# Load environment variables
if [[ -f "$PROJECT_ROOT/.env.production" ]]; then
    source "$PROJECT_ROOT/.env.production"
else
    echo "Error: .env.production file not found"
    exit 1
fi

# Database configuration from environment
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_DATABASE="${DB_DATABASE:-directus}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-}"

# Script options
DRY_RUN=false
VERBOSE=false
TIMESTAMP=$(date +"%Y-%m-%dT%H-%M-%S")
BACKUP_NAME="directus-db-backup-$TIMESTAMP"

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create a timestamped backup of the Directus PostgreSQL database.

OPTIONS:
    --dry-run       Show what would be backed up without executing
    --verbose       Enable verbose output
    --help         Show this help message

ENVIRONMENT VARIABLES:
    DB_HOST        Database host (default: localhost)
    DB_PORT        Database port (default: 5432) 
    DB_DATABASE    Database name (required)
    DB_USER        Database user (required)
    DB_PASSWORD    Database password (required)

EXAMPLES:
    $0                 # Create backup with current timestamp
    $0 --dry-run       # Show backup commands without executing
    $0 --verbose       # Enable detailed output

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
    
    # Check required environment variables
    if [[ -z "$DB_DATABASE" ]]; then
        echo "Error: DB_DATABASE environment variable is required"
        exit 1
    fi
    
    if [[ -z "$DB_USER" ]]; then
        echo "Error: DB_USER environment variable is required"
        exit 1
    fi
    
    verbose_log "Prerequisites check passed"
}

# Function to test database connection
test_connection() {
    if [[ "$DRY_RUN" == "true" ]]; then
        verbose_log "Skipping database connection test in dry-run mode"
        return 0
    fi
    
    verbose_log "Testing database connection..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_DATABASE" &> /dev/null; then
        echo "Error: Cannot connect to database $DB_DATABASE on $DB_HOST:$DB_PORT"
        echo "Please verify your database connection settings."
        exit 1
    fi
    
    verbose_log "Database connection successful"
}

# Function to create backup directory
create_backup_directory() {
    local backup_dir="$BACKUP_BASE_DIR/$BACKUP_NAME"
    
    verbose_log "Creating backup directory: $backup_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create directory: $backup_dir"
        return
    fi
    
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Function to create database dump
create_database_dump() {
    local backup_dir="$1"
    local dump_file="$backup_dir/database.sql"
    local metadata_file="$backup_dir/backup-metadata.json"
    
    verbose_log "Creating database dump..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create database dump:"
        echo "  Command: pg_dump -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_DATABASE"
        echo "  Output: $dump_file"
        echo "  Metadata: $metadata_file"
        return
    fi
    
    # Create the database dump
    pg_dump \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --username="$DB_USER" \
        --dbname="$DB_DATABASE" \
        --verbose \
        --clean \
        --if-exists \
        --create \
        --format=plain \
        --file="$dump_file"
    
    # Create metadata file
    cat > "$metadata_file" << EOF
{
    "backup_type": "database",
    "timestamp": "$TIMESTAMP",
    "database_host": "$DB_HOST",
    "database_port": "$DB_PORT",
    "database_name": "$DB_DATABASE",
    "database_user": "$DB_USER",
    "dump_file": "database.sql",
    "backup_size_bytes": $(stat -f%z "$dump_file" 2>/dev/null || stat -c%s "$dump_file" 2>/dev/null || echo "unknown"),
    "created_by": "backup-database.sh",
    "git_commit": "$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo 'unknown')"
}
EOF
    
    log "Database backup completed: $dump_file"
    log "Backup size: $(du -h "$dump_file" | cut -f1)"
}

# Function to create backup summary
create_backup_summary() {
    local backup_dir="$1"
    local summary_file="$backup_dir/README.md"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create backup summary: $summary_file"
        return
    fi
    
    cat > "$summary_file" << EOF
# Database Backup: $BACKUP_NAME

Created on: $(date)
Database: $DB_DATABASE on $DB_HOST:$DB_PORT

## Files in this backup:

- \`database.sql\` - Complete PostgreSQL dump
- \`backup-metadata.json\` - Backup metadata and information
- \`README.md\` - This summary file

## Restore Instructions:

1. Ensure you have PostgreSQL client tools installed
2. Set environment variables for target database
3. Run the restore command:

\`\`\`bash
psql -h TARGET_HOST -p TARGET_PORT -U TARGET_USER -d TARGET_DATABASE < database.sql
\`\`\`

## Backup Verification:

To verify this backup, check that:
- The database.sql file exists and is not empty
- The backup-metadata.json contains valid information
- The file sizes match expected database size

Generated by: backup-database.sh
EOF
    
    verbose_log "Backup summary created: $summary_file"
}

# Main backup function
main() {
    log "Starting database backup: $BACKUP_NAME"
    
    check_prerequisites
    test_connection
    
    local backup_dir
    backup_dir=$(create_backup_directory)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        create_database_dump "$backup_dir"
        create_backup_summary "$backup_dir"
        
        log "Database backup completed successfully!"
        log "Backup location: $backup_dir"
    else
        log "DRY RUN completed - no actual backup created"
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