#!/bin/bash

# Main Deployment Script for Directus Production
# Orchestrates the complete safe deployment workflow

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deploy-config.json"

# Default values
SOURCE_DIR=""
TARGET_DIR=""
DRY_RUN=false
VERBOSE=false
FORCE=false
SKIP_BACKUP=false
SKIP_CHECKS=false
ROLLBACK_ON_FAILURE=true

# Deployment state tracking
DEPLOYMENT_ID=""
DEPLOYMENT_LOG=""
BACKUP_CREATED=""
DEPLOYMENT_STARTED=false

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Orchestrate a complete safe deployment of Directus to production.

OPTIONS:
    --source DIR       Source directory to deploy from (default: current directory)
    --target DIR       Target production directory (required)
    --config FILE      Configuration file (default: deploy-config.json)
    --dry-run          Show what would be deployed without executing
    --verbose          Enable verbose output
    --force            Force deployment even with warnings
    --skip-backup      Skip creating backup (NOT RECOMMENDED)
    --skip-checks      Skip pre-deployment checks (NOT RECOMMENDED)
    --no-rollback      Disable rollback on failure
    --help            Show this help message

EXAMPLES:
    $0 --target /var/www/directus                    # Deploy to production
    $0 --dry-run --target /var/www/directus          # Show deployment plan
    $0 --verbose --target /var/www/directus          # Verbose deployment
    
ENVIRONMENT:
    DIRECTUS_PROD_PATH     Default target directory
    DEPLOY_DRY_RUN        Set to 'true' for dry-run mode
    DEPLOY_FORCE          Set to 'true' to force deployment

EXIT CODES:
    0  - Deployment successful
    1  - Deployment failed
    2  - Pre-deployment checks failed
    3  - Backup creation failed
    4  - Post-deployment validation failed

EOF
}

# Function for logging with timestamps
log() {
    local message="$1"
    local timestamp="[$(date +'%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $message"
    
    # Also log to file if deployment log is set
    if [[ -n "$DEPLOYMENT_LOG" ]]; then
        echo "$timestamp $message" >> "$DEPLOYMENT_LOG" 2>/dev/null || true
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
    
    # Also log to file if deployment log is set
    if [[ -n "$DEPLOYMENT_LOG" ]]; then
        echo "$timestamp ERROR: $message" >> "$DEPLOYMENT_LOG" 2>/dev/null || true
    fi
}

# Function to generate deployment ID
generate_deployment_id() {
    DEPLOYMENT_ID="deploy-$(date +%Y%m%d-%H%M%S)-$$"
    verbose_log "Generated deployment ID: $DEPLOYMENT_ID"
}

# Function to setup deployment logging
setup_deployment_logging() {
    local log_dir="$PROJECT_ROOT/logs"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        verbose_log "DRY RUN: Would create deployment log"
        return 0
    fi
    
    mkdir -p "$log_dir"
    DEPLOYMENT_LOG="$log_dir/deployment-$DEPLOYMENT_ID.log"
    
    # Initialize log file
    cat > "$DEPLOYMENT_LOG" << EOF
# Directus Deployment Log
# Deployment ID: $DEPLOYMENT_ID
# Started: $(date)
# Source: $SOURCE_DIR
# Target: $TARGET_DIR
# Configuration: $CONFIG_FILE

EOF
    
    verbose_log "Deployment logging setup: $DEPLOYMENT_LOG"
}

# Function to load and validate configuration
load_configuration() {
    verbose_log "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_log "Configuration file not found: $CONFIG_FILE"
        exit 2
    fi
    
    # Validate JSON format
    if ! python3 -m json.tool "$CONFIG_FILE" >/dev/null 2>&1; then
        error_log "Invalid JSON in configuration file: $CONFIG_FILE"
        exit 2
    fi
    
    verbose_log "Configuration loaded successfully from: $CONFIG_FILE"
}

# Function to validate deployment prerequisites
validate_prerequisites() {
    verbose_log "Validating deployment prerequisites..."
    
    # Check required tools
    local required_tools=("rsync" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_log "Required tool not found: $tool"
            exit 2
        fi
        verbose_log "Required tool available: $tool"
    done
    
    # Set default source directory
    if [[ -z "$SOURCE_DIR" ]]; then
        SOURCE_DIR="$PROJECT_ROOT"
    fi
    
    # Check environment variable for target
    if [[ -z "$TARGET_DIR" && -n "${DIRECTUS_PROD_PATH:-}" ]]; then
        TARGET_DIR="$DIRECTUS_PROD_PATH"
    fi
    
    # Validate source directory
    if [[ ! -d "$SOURCE_DIR" ]]; then
        error_log "Source directory does not exist: $SOURCE_DIR"
        exit 2
    fi
    
    if [[ ! -r "$SOURCE_DIR" ]]; then
        error_log "Source directory is not readable: $SOURCE_DIR"
        exit 2
    fi
    
    verbose_log "Source directory validated: $SOURCE_DIR"
    
    # Validate target directory
    if [[ -z "$TARGET_DIR" ]]; then
        error_log "Target directory must be specified with --target or DIRECTUS_PROD_PATH"
        exit 2
    fi
    
    # For dry-run, just check parent directory exists
    if [[ "$DRY_RUN" == "true" ]]; then
        local parent_dir
        parent_dir=$(dirname "$TARGET_DIR")
        if [[ ! -d "$parent_dir" ]]; then
            error_log "Target parent directory does not exist: $parent_dir"
            exit 2
        fi
    else
        # Create target directory if it doesn't exist
        if [[ ! -d "$TARGET_DIR" ]]; then
            log "Creating target directory: $TARGET_DIR"
            mkdir -p "$TARGET_DIR"
        fi
        
        if [[ ! -w "$TARGET_DIR" ]]; then
            error_log "Target directory is not writable: $TARGET_DIR"
            exit 2
        fi
    fi
    
    verbose_log "Target directory validated: $TARGET_DIR"
    
    log "Prerequisites validation completed"
}

# Function to run pre-deployment checks
run_pre_deployment_checks() {
    if [[ "$SKIP_CHECKS" == "true" ]]; then
        log "Skipping pre-deployment checks (--skip-checks specified)"
        return 0
    fi
    
    log "Running pre-deployment checks..."
    
    local pre_check_script="$SCRIPT_DIR/pre-deployment-checks.sh"
    local check_args=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        check_args="$check_args --dry-run"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        check_args="$check_args --verbose"
    fi
    
    # Add source and target arguments
    check_args="$check_args --source \"$SOURCE_DIR\" --target \"$TARGET_DIR\""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would run pre-deployment checks:"
        echo "  bash $pre_check_script $check_args"
        return 0
    fi
    
    if ! eval "bash \"$pre_check_script\" $check_args"; then
        error_log "Pre-deployment checks failed"
        exit 2
    fi
    
    log "Pre-deployment checks completed successfully"
}

# Function to create backup
create_backup() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log "Skipping backup creation (--skip-backup specified)"
        return 0
    fi
    
    log "Creating deployment backup..."
    
    local backup_db_script="$SCRIPT_DIR/backup-database.sh"
    local backup_files_script="$SCRIPT_DIR/backup-files.sh"
    
    local backup_args=""
    if [[ "$DRY_RUN" == "true" ]]; then
        backup_args="--dry-run"
    fi
    if [[ "$VERBOSE" == "true" ]]; then
        backup_args="$backup_args --verbose"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create database backup:"
        echo "  bash $backup_db_script $backup_args"
        echo "DRY RUN: Would create files backup:"
        echo "  bash $backup_files_script $backup_args --source \"$TARGET_DIR/uploads\""
        BACKUP_CREATED="dry-run-backup"
        return 0
    fi
    
    # Create database backup
    if ! bash "$backup_db_script" $backup_args; then
        error_log "Database backup failed"
        exit 3
    fi
    
    # Create files backup
    if [[ -d "$TARGET_DIR/uploads" ]]; then
        if ! bash "$backup_files_script" $backup_args --source "$TARGET_DIR/uploads"; then
            error_log "Files backup failed"
            exit 3
        fi
    else
        verbose_log "No uploads directory found, skipping files backup"
    fi
    
    # Find the latest backup directory
    local backup_base_dir="$PROJECT_ROOT/backups"
    if [[ -d "$backup_base_dir" ]]; then
        BACKUP_CREATED=$(find "$backup_base_dir" -maxdepth 1 -type d -name "*backup*" | sort | tail -1)
        verbose_log "Backup created: $BACKUP_CREATED"
    fi
    
    log "Backup creation completed successfully"
}

# Function to perform deployment
perform_deployment() {
    log "Starting deployment process..."
    DEPLOYMENT_STARTED=true
    
    local sync_script="$SCRIPT_DIR/sync-code.sh"
    local extension_script="$SCRIPT_DIR/deploy-extensions.sh"
    
    local deploy_args=""
    if [[ "$DRY_RUN" == "true" ]]; then
        deploy_args="$deploy_args --dry-run"
    fi
    if [[ "$VERBOSE" == "true" ]]; then
        deploy_args="$deploy_args --verbose"
    fi
    if [[ "$FORCE" == "true" ]]; then
        deploy_args="$deploy_args --force"
    fi
    
    # Add source and target
    deploy_args="$deploy_args --source \"$SOURCE_DIR\" --target \"$TARGET_DIR\""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would perform code sync:"
        echo "  bash $sync_script $deploy_args"
        echo "DRY RUN: Would deploy extensions:"
        echo "  bash $extension_script --dry-run --target \"$TARGET_DIR/extensions\""
        return 0
    fi
    
    # Perform code sync
    log "Syncing code changes..."
    if ! eval "bash \"$sync_script\" $deploy_args"; then
        error_log "Code sync failed"
        return 1
    fi
    
    # Deploy extensions
    log "Deploying extensions..."
    local ext_target="$TARGET_DIR/extensions"
    if ! bash "$extension_script" $deploy_args --target "$ext_target"; then
        error_log "Extension deployment failed"
        return 1
    fi
    
    log "Deployment process completed successfully"
}

# Function to run post-deployment validation
run_post_deployment_validation() {
    log "Running post-deployment validation..."
    
    local post_validate_script="$SCRIPT_DIR/post-deployment-validation.sh"
    local validation_args=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        validation_args="$validation_args --dry-run"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        validation_args="$validation_args --verbose"
    fi
    
    # Add deployment directory
    validation_args="$validation_args --deployment-dir \"$TARGET_DIR\""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would run post-deployment validation:"
        echo "  bash $post_validate_script $validation_args"
        return 0
    fi
    
    if ! eval "bash \"$post_validate_script\" $validation_args"; then
        error_log "Post-deployment validation failed"
        return 1
    fi
    
    log "Post-deployment validation completed successfully"
}

# Function to handle deployment failure
handle_deployment_failure() {
    local failure_reason="$1"
    
    error_log "Deployment failed: $failure_reason"
    
    if [[ "$ROLLBACK_ON_FAILURE" == "true" && -n "$BACKUP_CREATED" && "$BACKUP_CREATED" != "dry-run-backup" ]]; then
        log "Attempting automatic rollback..."
        
        # Attempt rollback (this would be implemented in a rollback script)
        local rollback_script="$SCRIPT_DIR/rollback.sh"
        if [[ -f "$rollback_script" ]]; then
            if bash "$rollback_script" --backup "$BACKUP_CREATED" --target "$TARGET_DIR"; then
                log "Rollback completed successfully"
            else
                error_log "Rollback failed - manual intervention required"
            fi
        else
            error_log "Rollback script not found - manual intervention required"
        fi
    else
        error_log "Rollback disabled or no backup available - manual intervention required"
    fi
    
    log "Deployment failure handling completed"
}

# Function to cleanup deployment artifacts
cleanup_deployment() {
    verbose_log "Cleaning up deployment artifacts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would cleanup deployment artifacts"
        return 0
    fi
    
    # Clean up temporary files
    rm -f "/tmp/directus_extensions_list_$$" 2>/dev/null || true
    
    verbose_log "Deployment cleanup completed"
}

# Function to generate deployment summary
generate_deployment_summary() {
    log "=== Deployment Summary ==="
    log "Deployment ID: $DEPLOYMENT_ID"
    log "Source: $SOURCE_DIR"
    log "Target: $TARGET_DIR"
    log "Started: $(date)"
    
    if [[ -n "$BACKUP_CREATED" ]]; then
        log "Backup: $BACKUP_CREATED"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Mode: DRY RUN (no actual changes made)"
    else
        log "Mode: LIVE DEPLOYMENT"
    fi
    
    if [[ -n "$DEPLOYMENT_LOG" ]]; then
        log "Log file: $DEPLOYMENT_LOG"
    fi
}

# Signal handler for cleanup
trap_cleanup() {
    log "Deployment interrupted - cleaning up..."
    
    if [[ "$DEPLOYMENT_STARTED" == "true" && "$ROLLBACK_ON_FAILURE" == "true" ]]; then
        handle_deployment_failure "deployment interrupted"
    fi
    
    cleanup_deployment
    exit 1
}

# Set up signal handlers
trap trap_cleanup INT TERM

# Main deployment function
main() {
    # Environment variable overrides
    if [[ "${DEPLOY_DRY_RUN:-}" == "true" ]]; then
        DRY_RUN=true
    fi
    
    if [[ "${DEPLOY_FORCE:-}" == "true" ]]; then
        FORCE=true
    fi
    
    # Generate deployment ID and setup logging
    generate_deployment_id
    setup_deployment_logging
    
    log "Starting Directus production deployment"
    log "Deployment ID: $DEPLOYMENT_ID"
    
    # Main deployment workflow
    load_configuration
    validate_prerequisites
    run_pre_deployment_checks
    create_backup
    
    # Perform the actual deployment
    if perform_deployment; then
        if run_post_deployment_validation; then
            log "🎉 Deployment completed successfully!"
            generate_deployment_summary
            cleanup_deployment
            exit 0
        else
            handle_deployment_failure "post-deployment validation failed"
            exit 4
        fi
    else
        handle_deployment_failure "deployment process failed"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --target)
            TARGET_DIR="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
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
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --skip-checks)
            SKIP_CHECKS=true
            shift
            ;;
        --no-rollback)
            ROLLBACK_ON_FAILURE=false
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