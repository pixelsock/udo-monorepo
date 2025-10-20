#!/bin/bash

# Rollback Script for Directus Production
# Safely rollback deployment to a previous backup

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
BACKUP_DIR=""
TARGET_DIR=""
DRY_RUN=false
VERBOSE=false
FORCE=false
VERIFY_ONLY=false
CHECK_HEALTH=false
SKIP_CONFIRMATION=false

# Rollback state tracking
ROLLBACK_ID=""
ROLLBACK_LOG=""
CURRENT_BACKUP=""

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rollback Directus deployment to a previous backup.

OPTIONS:
    --backup DIR       Backup directory to restore from (required)
    --target DIR       Target directory to restore to (required)
    --dry-run          Show what would be restored without executing
    --verbose          Enable verbose output
    --force            Skip confirmation prompts
    --verify-only      Only verify backup, don't perform rollback
    --check-health     Check target health and suggest rollback if needed
    --help            Show this help message

EXAMPLES:
    $0 --backup ./backups/backup-20240101 --target /var/www/directus
    $0 --dry-run --backup ./backups/backup-20240101 --target /prod
    $0 --verify-only --backup ./backups/backup-20240101

SAFETY:
    - Creates backup of current state before rollback
    - Requires confirmation unless --force is specified
    - Validates backup integrity before proceeding
    - Logs all rollback operations

EXIT CODES:
    0  - Rollback successful
    1  - Rollback failed
    2  - Invalid parameters or backup verification failed
    3  - User cancelled rollback

EOF
}

# Function for logging with timestamps
log() {
    local message="$1"
    local timestamp="[$(date +'%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $message"
    
    # Also log to file if rollback log is set
    if [[ -n "$ROLLBACK_LOG" ]]; then
        echo "$timestamp $message" >> "$ROLLBACK_LOG" 2>/dev/null || true
    fi
}

# Function for verbose logging
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "VERBOSE: $1"
    fi
}

# Function for error logging
error_log() {
    local message="$1"
    local timestamp="[$(date +'%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp ERROR: $message" >&2
    
    # Also log to file if rollback log is set
    if [[ -n "$ROLLBACK_LOG" ]]; then
        echo "$timestamp ERROR: $message" >> "$ROLLBACK_LOG" 2>/dev/null || true
    fi
}

# Function to generate rollback ID
generate_rollback_id() {
    ROLLBACK_ID="rollback-$(date +%Y%m%d-%H%M%S)-$$"
    verbose_log "Generated rollback ID: $ROLLBACK_ID"
}

# Function to setup rollback logging
setup_rollback_logging() {
    local log_dir="$PROJECT_ROOT/logs"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        verbose_log "DRY RUN: Would create rollback log"
        return 0
    fi
    
    mkdir -p "$log_dir"
    ROLLBACK_LOG="$log_dir/rollback-$ROLLBACK_ID.log"
    
    # Initialize log file
    cat > "$ROLLBACK_LOG" << EOF
# Directus Rollback Log
# Rollback ID: $ROLLBACK_ID
# Started: $(date)
# Backup: $BACKUP_DIR
# Target: $TARGET_DIR

EOF
    
    verbose_log "Rollback logging setup: $ROLLBACK_LOG"
}

# Function to validate parameters
validate_parameters() {
    verbose_log "Validating rollback parameters..."
    
    # Check required parameters
    if [[ -z "$BACKUP_DIR" ]]; then
        error_log "Backup directory must be specified with --backup"
        exit 2
    fi
    
    if [[ -z "$TARGET_DIR" && "$VERIFY_ONLY" != "true" ]]; then
        error_log "Target directory must be specified with --target (unless using --verify-only)"
        exit 2
    fi
    
    # Validate backup directory
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error_log "Backup directory does not exist: $BACKUP_DIR"
        exit 2
    fi
    
    if [[ ! -r "$BACKUP_DIR" ]]; then
        error_log "Backup directory is not readable: $BACKUP_DIR"
        exit 2
    fi
    
    verbose_log "Backup directory validated: $BACKUP_DIR"
    
    # Validate target directory if not verify-only
    if [[ "$VERIFY_ONLY" != "true" ]]; then
        if [[ ! -d "$TARGET_DIR" ]]; then
            error_log "Target directory does not exist: $TARGET_DIR"
            exit 2
        fi
        
        if [[ ! -w "$TARGET_DIR" ]]; then
            error_log "Target directory is not writable: $TARGET_DIR"
            exit 2
        fi
        
        verbose_log "Target directory validated: $TARGET_DIR"
    fi
    
    log "Parameter validation completed"
}

# Function to verify backup integrity
verify_backup_integrity() {
    log "Verifying backup integrity..."
    
    local issues=0
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would verify backup integrity"
        return 0
    fi
    
    # Check for backup metadata
    local metadata_file="$BACKUP_DIR/backup-metadata.json"
    if [[ ! -f "$metadata_file" ]]; then
        error_log "Backup metadata file not found: $metadata_file"
        ((issues++))
    else
        verbose_log "✓ Backup metadata found"
        
        # Validate JSON format
        if ! python3 -m json.tool "$metadata_file" >/dev/null 2>&1; then
            error_log "Invalid JSON in backup metadata"
            ((issues++))
        else
            verbose_log "✓ Backup metadata has valid JSON format"
            
            # Extract backup info
            local backup_type
            local backup_timestamp
            backup_type=$(python3 -c "import json; data=json.load(open('$metadata_file')); print(data.get('backup_type', 'unknown'))" 2>/dev/null || echo "unknown")
            backup_timestamp=$(python3 -c "import json; data=json.load(open('$metadata_file')); print(data.get('timestamp', 'unknown'))" 2>/dev/null || echo "unknown")
            
            verbose_log "Backup type: $backup_type"
            verbose_log "Backup timestamp: $backup_timestamp"
        fi
    fi
    
    # Check for essential backup files
    local essential_files=()
    
    # Check for database backup
    if [[ -f "$BACKUP_DIR/database.sql" ]]; then
        verbose_log "✓ Database backup found"
        
        # Check file size
        local db_size
        db_size=$(stat -f%z "$BACKUP_DIR/database.sql" 2>/dev/null || stat -c%s "$BACKUP_DIR/database.sql" 2>/dev/null || echo "0")
        if [[ "$db_size" -eq 0 ]]; then
            error_log "Database backup file is empty"
            ((issues++))
        else
            verbose_log "✓ Database backup file size: $(du -h "$BACKUP_DIR/database.sql" | cut -f1)"
        fi
    else
        verbose_log "No database backup found (may be external database)"
    fi
    
    # Check for files backup
    if [[ -d "$BACKUP_DIR/files" ]]; then
        verbose_log "✓ Files backup directory found"
        
        local file_count
        file_count=$(find "$BACKUP_DIR/files" -type f | wc -l | tr -d ' ')
        verbose_log "Files backup contains $file_count files"
    else
        verbose_log "No files backup found (may be new deployment or no uploads)"
    fi
    
    # Check backup is not too old (warn if > 30 days)
    if [[ -f "$metadata_file" ]]; then
        local backup_date
        backup_date=$(python3 -c "
import json
from datetime import datetime
try:
    data = json.load(open('$metadata_file'))
    timestamp = data.get('timestamp', '')
    if timestamp:
        # Parse timestamp and get days ago
        from datetime import datetime
        backup_time = datetime.fromisoformat(timestamp.replace('T', ' ').replace('-', '-'))
        days_ago = (datetime.now() - backup_time).days
        print(days_ago)
    else:
        print('999')
except:
    print('999')
" 2>/dev/null || echo "999")
        
        if [[ $backup_date -gt 30 ]]; then
            error_log "Backup is very old ($backup_date days) - are you sure you want to rollback to this?"
            ((issues++))
        else
            verbose_log "Backup age: $backup_date days"
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Backup integrity verification passed"
    else
        log "❌ Backup integrity verification failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check target health
check_target_health() {
    if [[ "$CHECK_HEALTH" != "true" ]]; then
        return 0
    fi
    
    log "Checking target health..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check target health"
        return 0
    fi
    
    local health_issues=0
    
    # Check if target directory exists and is accessible
    if [[ ! -d "$TARGET_DIR" ]] || [[ ! -r "$TARGET_DIR" ]]; then
        error_log "Target directory is not accessible"
        ((health_issues++))
    fi
    
    # Check for essential files
    if [[ ! -f "$TARGET_DIR/package.json" ]]; then
        error_log "Target is missing essential files"
        ((health_issues++))
    fi
    
    # Load environment and check API if possible
    local env_files=(".env.production" ".env")
    local api_url=""
    
    for env_file in "${env_files[@]}"; do
        local full_path="$TARGET_DIR/$env_file"
        if [[ -f "$full_path" ]]; then
            set -a
            source "$full_path" 2>/dev/null || true
            set +a
            
            if [[ -n "${PUBLIC_URL:-}" ]]; then
                api_url="$PUBLIC_URL"
                break
            fi
        fi
    done
    
    # Test API health if URL available
    if [[ -n "$api_url" ]] && command -v curl &> /dev/null; then
        verbose_log "Testing API health: $api_url"
        
        if ! curl -f -s --max-time 10 "$api_url/server/health" >/dev/null 2>&1; then
            error_log "API health check failed"
            ((health_issues++))
        else
            verbose_log "✓ API health check passed"
        fi
    fi
    
    if [[ $health_issues -gt 0 ]]; then
        log "❌ Target health check failed - rollback may be needed"
        return 1
    else
        log "✓ Target health check passed"
        return 0
    fi
}

# Function to get user confirmation
get_user_confirmation() {
    if [[ "$FORCE" == "true" || "$SKIP_CONFIRMATION" == "true" ]]; then
        log "Skipping confirmation (force mode enabled)"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would request user confirmation"
        return 0
    fi
    
    log "=== ROLLBACK CONFIRMATION ==="
    log "This will rollback the deployment to:"
    log "  Backup: $BACKUP_DIR"
    log "  Target: $TARGET_DIR"
    log ""
    log "WARNING: This will:"
    log "  - Replace current deployment with backup"
    log "  - Create backup of current state first"
    log "  - Potentially lose any changes made since backup"
    log ""
    
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r response
    
    case "$response" in
        yes|YES|y|Y)
            log "User confirmed rollback"
            return 0
            ;;
        *)
            log "User cancelled rollback"
            return 1
            ;;
    esac
}

# Function to backup current state
backup_current_state() {
    log "Creating backup of current state before rollback..."
    
    local current_backup_dir="$PROJECT_ROOT/backups/pre-rollback-$(date +%Y%m%d-%H%M%S)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would backup current state to: $current_backup_dir"
        CURRENT_BACKUP="$current_backup_dir"
        return 0
    fi
    
    mkdir -p "$current_backup_dir"
    
    # Backup current files
    verbose_log "Backing up current deployment..."
    if ! rsync -av --exclude="data/" --exclude="uploads/" --exclude="backups/" "$TARGET_DIR/" "$current_backup_dir/"; then
        error_log "Failed to backup current state"
        return 1
    fi
    
    # Create metadata for current backup
    cat > "$current_backup_dir/backup-metadata.json" << EOF
{
    "backup_type": "pre-rollback",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "rollback_id": "$ROLLBACK_ID",
    "original_target": "$TARGET_DIR",
    "rollback_source": "$BACKUP_DIR",
    "created_by": "rollback.sh"
}
EOF
    
    CURRENT_BACKUP="$current_backup_dir"
    log "Current state backed up to: $current_backup_dir"
}

# Function to perform rollback
perform_rollback() {
    log "Starting rollback process..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would perform rollback:"
        echo "  - Restore files from: $BACKUP_DIR"
        echo "  - Restore to: $TARGET_DIR"
        echo "  - Preserve data directories"
        echo "  - Update deployment metadata"
        return 0
    fi
    
    # Create staging directory for atomic rollback
    local staging_dir="$TARGET_DIR.rollback-staging"
    
    verbose_log "Creating staging directory: $staging_dir"
    mkdir -p "$staging_dir"
    
    # Restore files from backup (excluding data)
    log "Restoring files from backup..."
    
    # Determine what to restore based on backup structure
    if [[ -f "$BACKUP_DIR/package.json" ]]; then
        # Direct file backup
        verbose_log "Restoring from direct file backup"
        rsync -av --exclude="data/" --exclude="uploads/" "$BACKUP_DIR/" "$staging_dir/"
    elif [[ -d "$BACKUP_DIR/files" ]]; then
        # Files subdirectory backup
        verbose_log "Restoring from files subdirectory backup"
        rsync -av "$BACKUP_DIR/files/" "$staging_dir/"
    else
        error_log "Cannot determine backup structure"
        rm -rf "$staging_dir"
        return 1
    fi
    
    # Preserve current data directories
    log "Preserving current data directories..."
    
    local preserve_dirs=("data" "uploads")
    for dir in "${preserve_dirs[@]}"; do
        local source_path="$TARGET_DIR/$dir"
        local target_path="$staging_dir/$dir"
        
        if [[ -d "$source_path" ]]; then
            verbose_log "Preserving directory: $dir"
            cp -r "$source_path" "$target_path"
        else
            verbose_log "Directory not found (skipping): $dir"
        fi
    done
    
    # Atomic promotion: move current to backup, staging to current
    log "Performing atomic rollback promotion..."
    
    local temp_backup="$TARGET_DIR.pre-rollback-temp"
    mv "$TARGET_DIR" "$temp_backup"
    mv "$staging_dir" "$TARGET_DIR"
    
    # Clean up temp backup (kept for safety)
    verbose_log "Temporary backup available at: $temp_backup"
    
    log "Rollback process completed successfully"
}

# Function to restore database if included
restore_database() {
    local db_backup="$BACKUP_DIR/database.sql"
    
    if [[ ! -f "$db_backup" ]]; then
        verbose_log "No database backup found, skipping database restore"
        return 0
    fi
    
    log "Database backup found - manual restoration required"
    log "To restore database, run:"
    log "  psql -h HOST -p PORT -U USER -d DATABASE < \"$db_backup\""
    log ""
    log "WARNING: Database restoration will overwrite all current data!"
    log "Make sure to backup current database first if needed."
}

# Function to verify rollback
verify_rollback() {
    log "Verifying rollback..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would verify rollback success"
        return 0
    fi
    
    local issues=0
    
    # Check essential files exist
    if [[ ! -f "$TARGET_DIR/package.json" ]]; then
        error_log "Rollback verification failed: package.json missing"
        ((issues++))
    else
        verbose_log "✓ Essential files present after rollback"
    fi
    
    # Check that data directories are preserved
    local preserve_dirs=("uploads")
    for dir in "${preserve_dirs[@]}"; do
        local dir_path="$TARGET_DIR/$dir"
        if [[ -d "$dir_path" ]]; then
            verbose_log "✓ Data directory preserved: $dir"
        else
            verbose_log "Data directory not found (may not exist): $dir"
        fi
    done
    
    # Run deployment validation if available
    local validation_script="$SCRIPT_DIR/validate-deployment.sh"
    if [[ -f "$validation_script" ]]; then
        verbose_log "Running deployment validation..."
        if bash "$validation_script" --deployment-dir "$TARGET_DIR" --skip-api; then
            verbose_log "✓ Deployment validation passed"
        else
            error_log "Deployment validation failed after rollback"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Rollback verification passed"
    else
        log "❌ Rollback verification failed ($issues issues)"
    fi
    
    return $issues
}

# Function to generate rollback summary
generate_rollback_summary() {
    log "=== Rollback Summary ==="
    log "Rollback ID: $ROLLBACK_ID"
    log "Backup source: $BACKUP_DIR"
    log "Target: $TARGET_DIR"
    log "Completed: $(date)"
    
    if [[ -n "$CURRENT_BACKUP" ]]; then
        log "Pre-rollback backup: $CURRENT_BACKUP"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Mode: DRY RUN (no actual changes made)"
    else
        log "Mode: LIVE ROLLBACK"
    fi
    
    if [[ -n "$ROLLBACK_LOG" ]]; then
        log "Log file: $ROLLBACK_LOG"
    fi
}

# Main rollback function
main() {
    # Generate rollback ID and setup logging
    generate_rollback_id
    setup_rollback_logging
    
    log "Starting Directus deployment rollback"
    log "Rollback ID: $ROLLBACK_ID"
    
    # Validate parameters
    validate_parameters
    
    # Verify backup integrity
    if ! verify_backup_integrity; then
        error_log "Backup verification failed - aborting rollback"
        exit 2
    fi
    
    # If verify-only mode, exit after verification
    if [[ "$VERIFY_ONLY" == "true" ]]; then
        log "✓ Backup verification completed (verify-only mode)"
        exit 0
    fi
    
    # Check target health if requested
    if ! check_target_health; then
        log "Target health check suggests rollback may be needed"
    fi
    
    # Get user confirmation
    if ! get_user_confirmation; then
        log "Rollback cancelled by user"
        exit 3
    fi
    
    # Backup current state
    if ! backup_current_state; then
        error_log "Failed to backup current state - aborting rollback"
        exit 1
    fi
    
    # Perform rollback
    if ! perform_rollback; then
        error_log "Rollback process failed"
        exit 1
    fi
    
    # Restore database info
    restore_database
    
    # Verify rollback
    if ! verify_rollback; then
        error_log "Rollback verification failed"
        exit 1
    fi
    
    # Success
    log "🎉 Rollback completed successfully!"
    generate_rollback_summary
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --target)
            TARGET_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --check-health)
            CHECK_HEALTH=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 2
            ;;
    esac
done

# Run main function
main