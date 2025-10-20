#!/bin/bash

# Backup Verification Script for Directus Production
# Verifies the integrity and completeness of database and file backups

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_BASE_DIR="$PROJECT_ROOT/backups"

# Script options
VERBOSE=false
BACKUP_DIR=""
CHECK_DATABASE=true
CHECK_FILES=true
QUICK_CHECK=false

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [BACKUP_DIRECTORY]

Verify the integrity and completeness of Directus backups.

OPTIONS:
    --backup-dir DIR   Directory containing backup to verify
    --database-only    Only verify database backup
    --files-only       Only verify file backup  
    --quick           Perform quick verification (skip deep file checks)
    --verbose         Enable verbose output
    --help           Show this help message

EXAMPLES:
    $0                                           # Verify latest backup
    $0 --backup-dir ./backups/backup-2024-01-01 # Verify specific backup
    $0 --database-only --verbose                 # Verify only database with details
    $0 --quick                                   # Quick verification

EXIT CODES:
    0  - Backup verification passed
    1  - Backup verification failed
    2  - Script error or invalid usage

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

# Function for error logging
error_log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Function to find latest backup
find_latest_backup() {
    verbose_log "Looking for latest backup in: $BACKUP_BASE_DIR"
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        error_log "Backup directory does not exist: $BACKUP_BASE_DIR"
        return 1
    fi
    
    local latest_backup
    latest_backup=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "*backup*" | sort | tail -1)
    
    if [[ -z "$latest_backup" ]]; then
        error_log "No backup directories found in: $BACKUP_BASE_DIR"
        return 1
    fi
    
    verbose_log "Latest backup found: $latest_backup"
    echo "$latest_backup"
}

# Function to verify backup directory structure
verify_backup_structure() {
    local backup_dir="$1"
    local issues=0
    
    log "Verifying backup structure: $(basename "$backup_dir")"
    verbose_log "Backup directory: $backup_dir"
    
    # Check if backup directory exists
    if [[ ! -d "$backup_dir" ]]; then
        error_log "Backup directory does not exist: $backup_dir"
        return 1
    fi
    
    # Check for metadata file
    if [[ ! -f "$backup_dir/backup-metadata.json" ]]; then
        error_log "Missing backup metadata file"
        ((issues++))
    else
        verbose_log "✓ Backup metadata file found"
        
        # Validate JSON format
        if ! python3 -m json.tool "$backup_dir/backup-metadata.json" >/dev/null 2>&1; then
            error_log "Invalid JSON in metadata file"
            ((issues++))
        else
            verbose_log "✓ Backup metadata JSON is valid"
        fi
    fi
    
    # Check for README
    if [[ ! -f "$backup_dir/README.md" ]]; then
        error_log "Missing backup README file"
        ((issues++))
    else
        verbose_log "✓ Backup README found"
    fi
    
    return $issues
}

# Function to verify database backup
verify_database_backup() {
    local backup_dir="$1"
    local issues=0
    
    log "Verifying database backup..."
    
    local db_file="$backup_dir/database.sql"
    
    # Check if database file exists
    if [[ ! -f "$db_file" ]]; then
        error_log "Database backup file not found: $db_file"
        return 1
    fi
    
    verbose_log "✓ Database backup file found"
    
    # Check file size
    local file_size
    file_size=$(stat -f%z "$db_file" 2>/dev/null || stat -c%s "$db_file" 2>/dev/null || echo "0")
    
    if [[ "$file_size" -eq 0 ]]; then
        error_log "Database backup file is empty"
        ((issues++))
    else
        verbose_log "✓ Database backup file size: $(du -h "$db_file" | cut -f1)"
    fi
    
    # Check for SQL content
    if [[ "$file_size" -gt 0 ]]; then
        if grep -q "PostgreSQL database dump" "$db_file" 2>/dev/null; then
            verbose_log "✓ Database backup contains PostgreSQL dump header"
        else
            error_log "Database backup does not appear to be a PostgreSQL dump"
            ((issues++))
        fi
        
        # Check for basic SQL structure
        local sql_patterns=("CREATE" "INSERT" "COPY")
        for pattern in "${sql_patterns[@]}"; do
            if grep -q "$pattern" "$db_file" 2>/dev/null; then
                verbose_log "✓ Found $pattern statements in database backup"
            else
                error_log "Missing $pattern statements in database backup (may be empty database)"
                ((issues++))
            fi
        done
    fi
    
    # Validate SQL syntax (basic check)
    if command -v psql &> /dev/null && [[ "$QUICK_CHECK" == "false" ]]; then
        verbose_log "Performing SQL syntax validation..."
        
        # Create temporary database to test restore
        local temp_db="directus_backup_test_$$"
        
        # Note: This would require database credentials and is optional
        verbose_log "SQL syntax validation skipped (requires database connection)"
    else
        verbose_log "SQL syntax validation skipped (psql not available or quick check mode)"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Database backup verification passed"
    else
        log "❌ Database backup verification failed ($issues issues)"
    fi
    
    return $issues
}

# Function to verify file backup
verify_file_backup() {
    local backup_dir="$1"
    local issues=0
    
    log "Verifying file backup..."
    
    local files_dir="$backup_dir/files"
    
    # Check if files directory exists
    if [[ ! -d "$files_dir" ]]; then
        error_log "Files backup directory not found: $files_dir"
        return 1
    fi
    
    verbose_log "✓ Files backup directory found"
    
    # Count files in backup
    local backup_file_count
    backup_file_count=$(find "$files_dir" -type f | wc -l | tr -d ' ')
    verbose_log "Files in backup: $backup_file_count"
    
    if [[ "$backup_file_count" -eq 0 ]]; then
        error_log "No files found in backup (empty backup)"
        ((issues++))
    else
        verbose_log "✓ Backup contains $backup_file_count files"
    fi
    
    # Check for common file types (if not empty)
    if [[ "$backup_file_count" -gt 0 && "$QUICK_CHECK" == "false" ]]; then
        verbose_log "Checking for common file types..."
        
        local image_count
        local doc_count
        
        image_count=$(find "$files_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) | wc -l | tr -d ' ')
        doc_count=$(find "$files_dir" -type f \( -iname "*.pdf" -o -iname "*.doc" -o -iname "*.docx" -o -iname "*.txt" \) | wc -l | tr -d ' ')
        
        verbose_log "Image files: $image_count"
        verbose_log "Document files: $doc_count"
    fi
    
    # Check for suspicious files or patterns
    if [[ "$QUICK_CHECK" == "false" ]]; then
        verbose_log "Checking for suspicious files..."
        
        # Check for zero-byte files
        local zero_byte_files
        zero_byte_files=$(find "$files_dir" -type f -size 0 | wc -l | tr -d ' ')
        
        if [[ "$zero_byte_files" -gt 0 ]]; then
            error_log "Found $zero_byte_files zero-byte files in backup"
            ((issues++))
        else
            verbose_log "✓ No zero-byte files found"
        fi
        
        # Check for very large files (>100MB) that might indicate issues
        local large_files
        large_files=$(find "$files_dir" -type f -size +100M | wc -l | tr -d ' ')
        
        if [[ "$large_files" -gt 10 ]]; then
            error_log "Found $large_files very large files (>100MB) - verify this is expected"
            ((issues++))
        else
            verbose_log "✓ Large file count within expected range"
        fi
    fi
    
    # Calculate total size
    local backup_size
    backup_size=$(du -sh "$files_dir" 2>/dev/null | cut -f1 || echo "unknown")
    verbose_log "Total backup size: $backup_size"
    
    if [[ $issues -eq 0 ]]; then
        log "✓ File backup verification passed"
    else
        log "❌ File backup verification failed ($issues issues)"
    fi
    
    return $issues
}

# Function to verify backup metadata consistency
verify_metadata_consistency() {
    local backup_dir="$1"
    local issues=0
    
    if [[ ! -f "$backup_dir/backup-metadata.json" ]]; then
        return 0  # Already reported in structure check
    fi
    
    log "Verifying metadata consistency..."
    
    # Extract metadata using JSON parsing
    if command -v python3 &> /dev/null; then
        local backup_type
        local timestamp
        local file_count_meta
        
        backup_type=$(python3 -c "import json; data=json.load(open('$backup_dir/backup-metadata.json')); print(data.get('backup_type', 'unknown'))" 2>/dev/null || echo "unknown")
        timestamp=$(python3 -c "import json; data=json.load(open('$backup_dir/backup-metadata.json')); print(data.get('timestamp', 'unknown'))" 2>/dev/null || echo "unknown")
        
        verbose_log "Backup type from metadata: $backup_type"
        verbose_log "Timestamp from metadata: $timestamp"
        
        # Verify timestamp format
        if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
            verbose_log "✓ Timestamp format is valid"
        else
            error_log "Invalid timestamp format in metadata: $timestamp"
            ((issues++))
        fi
        
        # For file backups, verify file count
        if [[ "$backup_type" == "files" ]] && [[ -d "$backup_dir/files" ]]; then
            file_count_meta=$(python3 -c "import json; data=json.load(open('$backup_dir/backup-metadata.json')); print(data.get('file_count', 0))" 2>/dev/null || echo "0")
            
            local actual_file_count
            actual_file_count=$(find "$backup_dir/files" -type f | wc -l | tr -d ' ')
            
            if [[ "$file_count_meta" -eq "$actual_file_count" ]]; then
                verbose_log "✓ File count matches metadata ($actual_file_count files)"
            else
                error_log "File count mismatch - metadata: $file_count_meta, actual: $actual_file_count"
                ((issues++))
            fi
        fi
    else
        verbose_log "Python3 not available, skipping detailed metadata verification"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Metadata consistency verification passed"
    else
        log "❌ Metadata consistency verification failed ($issues issues)"
    fi
    
    return $issues
}

# Main verification function
main() {
    local total_issues=0
    
    # Determine backup directory
    if [[ -z "$BACKUP_DIR" ]]; then
        BACKUP_DIR=$(find_latest_backup) || exit 2
    fi
    
    log "Starting backup verification"
    log "Backup directory: $BACKUP_DIR"
    
    if [[ "$QUICK_CHECK" == "true" ]]; then
        log "Quick verification mode enabled"
    fi
    
    # Verify backup structure
    verify_backup_structure "$BACKUP_DIR" || ((total_issues+=$?))
    
    # Verify components based on options
    if [[ "$CHECK_DATABASE" == "true" ]]; then
        verify_database_backup "$BACKUP_DIR" || ((total_issues+=$?))
    fi
    
    if [[ "$CHECK_FILES" == "true" ]]; then
        verify_file_backup "$BACKUP_DIR" || ((total_issues+=$?))
    fi
    
    # Verify metadata consistency
    verify_metadata_consistency "$BACKUP_DIR" || ((total_issues+=$?))
    
    # Summary
    log "=== Verification Summary ==="
    
    if [[ $total_issues -eq 0 ]]; then
        log "🎉 Backup verification PASSED - backup appears to be complete and valid"
        exit 0
    else
        log "❌ Backup verification FAILED - found $total_issues issues"
        log "Please review the backup and address any issues before relying on it for restore"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --database-only)
            CHECK_DATABASE=true
            CHECK_FILES=false
            shift
            ;;
        --files-only)
            CHECK_DATABASE=false
            CHECK_FILES=true
            shift
            ;;
        --quick)
            QUICK_CHECK=true
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
        -*)
            echo "Unknown option: $1"
            usage
            exit 2
            ;;
        *)
            # Positional argument - backup directory
            BACKUP_DIR="$1"
            shift
            ;;
    esac
done

# Run main function
main