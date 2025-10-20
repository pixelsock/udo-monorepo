#!/bin/bash

# Code-Only Sync Script for Directus Production
# Syncs only code changes while preserving all production data

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
USE_STAGING=true

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Sync code changes to production while preserving all data.

OPTIONS:
    --source DIR      Source directory (default: current directory)
    --target DIR      Target production directory (required)
    --dry-run         Show what would be synced without executing
    --verbose         Enable verbose output
    --force           Force sync even if target has uncommitted changes
    --no-staging      Skip staging directory (direct sync)
    --help           Show this help message

EXAMPLES:
    $0 --target /var/www/directus              # Sync to production
    $0 --dry-run --target /var/www/directus    # Show what would be synced
    $0 --source ./build --target /prod         # Sync from build directory

ENVIRONMENT:
    DIRECTUS_PROD_PATH    Default target directory
    DEPLOY_DRY_RUN       Set to 'true' for dry-run mode

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

# Function to load configuration
load_config() {
    verbose_log "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_log "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Verify JSON is valid
    if ! python3 -m json.tool "$CONFIG_FILE" >/dev/null 2>&1; then
        error_log "Invalid JSON in configuration file: $CONFIG_FILE"
        exit 1
    fi
    
    verbose_log "Configuration loaded successfully"
}

# Function to validate directories
validate_directories() {
    verbose_log "Validating source and target directories..."
    
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
        exit 1
    fi
    
    if [[ ! -r "$SOURCE_DIR" ]]; then
        error_log "Source directory is not readable: $SOURCE_DIR"
        exit 1
    fi
    
    verbose_log "Source directory validated: $SOURCE_DIR"
    
    # Target directory validation
    if [[ -z "$TARGET_DIR" ]]; then
        error_log "Target directory must be specified with --target or DIRECTUS_PROD_PATH"
        exit 1
    fi
    
    # Create target directory if it doesn't exist (in dry-run, just check parent)
    if [[ "$DRY_RUN" == "true" ]]; then
        local parent_dir
        parent_dir=$(dirname "$TARGET_DIR")
        if [[ ! -d "$parent_dir" ]]; then
            error_log "Target parent directory does not exist: $parent_dir"
            exit 1
        fi
    else
        if [[ ! -d "$TARGET_DIR" ]]; then
            log "Creating target directory: $TARGET_DIR"
            mkdir -p "$TARGET_DIR"
        fi
        
        if [[ ! -w "$TARGET_DIR" ]]; then
            error_log "Target directory is not writable: $TARGET_DIR"
            exit 1
        fi
    fi
    
    verbose_log "Target directory validated: $TARGET_DIR"
}

# Function to check prerequisites
check_prerequisites() {
    verbose_log "Checking prerequisites..."
    
    # Check for rsync
    if ! command -v rsync &> /dev/null; then
        error_log "rsync is required but not installed"
        exit 1
    fi
    verbose_log "rsync available: $(rsync --version | head -1)"
    
    # Check for python3 (for JSON parsing)
    if ! command -v python3 &> /dev/null; then
        error_log "python3 is required for configuration parsing"
        exit 1
    fi
    
    # Check for git (optional, for change detection)
    if command -v git &> /dev/null; then
        verbose_log "git available for change detection"
    else
        verbose_log "git not available - skipping change detection"
    fi
    
    verbose_log "Prerequisites check passed"
}

# Function to build rsync exclude patterns from config
build_exclude_patterns() {
    verbose_log "Building exclude patterns from configuration..."
    
    local exclude_args=""
    
    # Get exclude patterns from config
    local exclude_patterns
    exclude_patterns=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    patterns = config.get('exclude_patterns', [])
    for pattern in patterns:
        print(f'--exclude={pattern}')
" 2>/dev/null || echo "")
    
    if [[ -n "$exclude_patterns" ]]; then
        exclude_args="$exclude_patterns"
        verbose_log "Added exclude patterns from configuration"
    else
        # Fallback patterns if config parsing fails
        exclude_args="--exclude=data/ --exclude=uploads/ --exclude=backups/ --exclude=.env* --exclude=*.log --exclude=node_modules/"
        verbose_log "Using fallback exclude patterns"
    fi
    
    echo "$exclude_args"
}

# Function to build rsync include patterns
build_include_patterns() {
    verbose_log "Building include patterns from configuration..."
    
    # Get include patterns from config (optional - if specified, use include mode)
    local include_patterns
    include_patterns=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    patterns = config.get('include_patterns', [])
    if patterns:
        for pattern in patterns:
            print(f'--include={pattern}')
" 2>/dev/null || echo "")
    
    echo "$include_patterns"
}

# Function to get rsync options from config
get_rsync_options() {
    verbose_log "Getting rsync options from configuration..."
    
    local rsync_opts
    rsync_opts=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    opts = config.get('rsync_options', ['--archive', '--verbose'])
    print(' '.join(opts))
" 2>/dev/null || echo "--archive --verbose")
    
    verbose_log "Rsync options: $rsync_opts"
    echo "$rsync_opts"
}

# Function to create staging directory
create_staging_directory() {
    if [[ "$USE_STAGING" != "true" ]]; then
        echo "$TARGET_DIR"
        return
    fi
    
    local staging_dir
    staging_dir=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    staging = config.get('atomic_deployment', {}).get('staging_directory', './deployment-staging')
    print(staging)
" 2>/dev/null || echo "./deployment-staging")
    
    # Make staging directory absolute if relative
    if [[ "${staging_dir:0:1}" != "/" ]]; then
        staging_dir="$PROJECT_ROOT/$staging_dir"
    fi
    
    verbose_log "Using staging directory: $staging_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create staging directory: $staging_dir"
        echo "$staging_dir"
        return
    fi
    
    # Create staging directory
    if [[ -d "$staging_dir" ]]; then
        log "Cleaning existing staging directory"
        rm -rf "$staging_dir"
    fi
    
    mkdir -p "$staging_dir"
    log "Created staging directory: $staging_dir"
    
    echo "$staging_dir"
}

# Function to validate source changes
validate_source_changes() {
    verbose_log "Validating source changes..."
    
    # Check if source is a git repository
    if [[ -d "$SOURCE_DIR/.git" ]]; then
        cd "$SOURCE_DIR"
        
        # Check for uncommitted changes
        if [[ "$FORCE" != "true" ]] && ! git diff-index --quiet HEAD --; then
            error_log "Source directory has uncommitted changes. Use --force to override."
            exit 1
        fi
        
        # Get current commit info
        local commit_hash
        local commit_message
        commit_hash=$(git rev-parse HEAD)
        commit_message=$(git log -1 --pretty=%B | head -1)
        
        verbose_log "Source commit: $commit_hash"
        verbose_log "Commit message: $commit_message"
        
        cd - >/dev/null
    else
        verbose_log "Source is not a git repository - skipping git validation"
    fi
}

# Function to perform the sync
perform_sync() {
    local sync_target="$1"
    
    log "Starting code sync..."
    log "Source: $SOURCE_DIR"
    log "Target: $sync_target"
    
    # Build rsync command
    local rsync_cmd
    local exclude_patterns
    local include_patterns
    local rsync_options
    
    exclude_patterns=$(build_exclude_patterns)
    include_patterns=$(build_include_patterns)
    rsync_options=$(get_rsync_options)
    
    # Build complete rsync command
    rsync_cmd="rsync $rsync_options"
    
    # Add include patterns if specified
    if [[ -n "$include_patterns" ]]; then
        rsync_cmd="$rsync_cmd $include_patterns --exclude=*"
    fi
    
    # Add exclude patterns
    rsync_cmd="$rsync_cmd $exclude_patterns"
    
    # Add progress if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        rsync_cmd="$rsync_cmd --progress"
    fi
    
    # Add dry-run if needed
    if [[ "$DRY_RUN" == "true" ]]; then
        rsync_cmd="$rsync_cmd --dry-run"
    fi
    
    # Add source and target
    rsync_cmd="$rsync_cmd \"$SOURCE_DIR/\" \"$sync_target/\""
    
    verbose_log "Rsync command: $rsync_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would execute sync command:"
        echo "$rsync_cmd"
        return 0
    fi
    
    # Execute rsync
    eval "$rsync_cmd"
    
    log "Code sync completed successfully"
}

# Function to promote staging to production
promote_staging() {
    local staging_dir="$1"
    
    if [[ "$USE_STAGING" != "true" ]] || [[ "$staging_dir" == "$TARGET_DIR" ]]; then
        return 0
    fi
    
    log "Promoting staging to production..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would promote staging to production:"
        echo "  mv \"$staging_dir\" \"$TARGET_DIR.new\""
        echo "  mv \"$TARGET_DIR\" \"$TARGET_DIR.old\""
        echo "  mv \"$TARGET_DIR.new\" \"$TARGET_DIR\""
        return 0
    fi
    
    # Atomic promotion using directory moves
    local backup_dir="$TARGET_DIR.backup-$(date +%s)"
    
    # Copy staging to new location
    cp -r "$staging_dir" "$TARGET_DIR.new"
    
    # Backup current production
    if [[ -d "$TARGET_DIR" ]]; then
        mv "$TARGET_DIR" "$backup_dir"
    fi
    
    # Promote new version
    mv "$TARGET_DIR.new" "$TARGET_DIR"
    
    log "Production promoted successfully"
    log "Previous version backed up to: $backup_dir"
    
    # Clean up staging
    rm -rf "$staging_dir"
    verbose_log "Staging directory cleaned up"
}

# Function to set proper permissions
set_permissions() {
    local target_dir="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would set permissions on: $target_dir"
        return 0
    fi
    
    verbose_log "Setting proper permissions..."
    
    # Get permissions from config
    local file_mode
    local dir_mode
    
    file_mode=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    print(config.get('permissions', {}).get('file_mode', '644'))
" 2>/dev/null || echo "644")
    
    dir_mode=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    print(config.get('permissions', {}).get('directory_mode', '755'))
" 2>/dev/null || echo "755")
    
    # Set directory permissions
    find "$target_dir" -type d -exec chmod "$dir_mode" {} \; 2>/dev/null || true
    
    # Set file permissions
    find "$target_dir" -type f -exec chmod "$file_mode" {} \; 2>/dev/null || true
    
    # Set executable permissions for scripts
    find "$target_dir" -path "*/scripts/deployment/*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    verbose_log "Permissions set successfully"
}

# Main sync function
main() {
    log "Starting selective code deployment"
    
    # Environment variable overrides
    if [[ "${DEPLOY_DRY_RUN:-}" == "true" ]]; then
        DRY_RUN=true
    fi
    
    load_config
    check_prerequisites
    validate_directories
    validate_source_changes
    
    # Create staging directory
    local sync_target
    sync_target=$(create_staging_directory)
    
    # Perform the sync
    perform_sync "$sync_target"
    
    # Set permissions
    set_permissions "$sync_target"
    
    # Promote staging to production if using staging
    promote_staging "$sync_target"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Selective deployment completed successfully!"
        log "Production directory: $TARGET_DIR"
    else
        log "DRY RUN completed - no actual deployment performed"
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
        --no-staging)
            USE_STAGING=false
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