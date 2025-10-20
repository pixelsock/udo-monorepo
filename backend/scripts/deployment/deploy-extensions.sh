#!/bin/bash

# Extension Deployment Script for Directus Production
# Handles deployment of custom Directus extensions safely

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deploy-config.json"

# Default values
SOURCE_EXTENSIONS_DIR="$PROJECT_ROOT/extensions"
TARGET_EXTENSIONS_DIR=""
DRY_RUN=false
VERBOSE=false
BACKUP_EXISTING=true
INSTALL_DEPS=true

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Directus extensions to production safely.

OPTIONS:
    --source DIR         Source extensions directory (default: ./extensions)
    --target DIR         Target extensions directory (required)
    --dry-run           Show what would be deployed without executing
    --verbose           Enable verbose output
    --no-backup         Skip backing up existing extensions
    --no-install        Skip installing extension dependencies
    --help             Show this help message

EXAMPLES:
    $0 --target /var/www/directus/extensions     # Deploy to production
    $0 --dry-run --target /prod/extensions       # Show what would be deployed
    $0 --no-install --target /prod/extensions    # Deploy without npm install

ENVIRONMENT:
    DIRECTUS_EXTENSIONS_PATH    Default target directory

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
    verbose_log "Loading extension deployment configuration..."
    
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
    verbose_log "Validating extension directories..."
    
    # Check environment variable for target
    if [[ -z "$TARGET_EXTENSIONS_DIR" && -n "${DIRECTUS_EXTENSIONS_PATH:-}" ]]; then
        TARGET_EXTENSIONS_DIR="$DIRECTUS_EXTENSIONS_PATH"
    fi
    
    # Validate source directory
    if [[ ! -d "$SOURCE_EXTENSIONS_DIR" ]]; then
        error_log "Source extensions directory does not exist: $SOURCE_EXTENSIONS_DIR"
        exit 1
    fi
    
    verbose_log "Source extensions directory: $SOURCE_EXTENSIONS_DIR"
    
    # Target directory validation
    if [[ -z "$TARGET_EXTENSIONS_DIR" ]]; then
        error_log "Target extensions directory must be specified with --target or DIRECTUS_EXTENSIONS_PATH"
        exit 1
    fi
    
    # Create target directory if it doesn't exist
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ ! -d "$TARGET_EXTENSIONS_DIR" ]]; then
            log "Creating target extensions directory: $TARGET_EXTENSIONS_DIR"
            mkdir -p "$TARGET_EXTENSIONS_DIR"
        fi
        
        if [[ ! -w "$TARGET_EXTENSIONS_DIR" ]]; then
            error_log "Target extensions directory is not writable: $TARGET_EXTENSIONS_DIR"
            exit 1
        fi
    fi
    
    verbose_log "Target extensions directory: $TARGET_EXTENSIONS_DIR"
}

# Function to scan available extensions
scan_extensions() {
    verbose_log "Scanning available extensions..."
    
    local extensions=()
    
    # Find all extension directories (exclude hidden directories)
    while IFS= read -r -d '' extension_dir; do
        local extension_name
        extension_name=$(basename "$extension_dir")
        
        # Skip hidden directories (starting with .)
        if [[ "${extension_name:0:1}" == "." ]]; then
            verbose_log "Skipping hidden directory: $extension_name"
            continue
        fi
        
        extensions+=("$extension_name")
        verbose_log "Found extension: $extension_name"
    done < <(find "$SOURCE_EXTENSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
    
    if [[ ${#extensions[@]} -eq 0 ]]; then
        log "No extensions found in source directory"
        return 0
    fi
    
    log "Found ${#extensions[@]} extensions: ${extensions[*]}"
    
    # Store extensions list for later use
    printf '%s\n' "${extensions[@]}" > "/tmp/directus_extensions_list_$$"
}

# Function to backup existing extensions
backup_existing_extensions() {
    if [[ "$BACKUP_EXISTING" != "true" ]]; then
        verbose_log "Skipping backup of existing extensions"
        return 0
    fi
    
    if [[ ! -d "$TARGET_EXTENSIONS_DIR" ]]; then
        verbose_log "No existing extensions directory to backup"
        return 0
    fi
    
    local backup_dir="$TARGET_EXTENSIONS_DIR.backup-$(date +%Y%m%d-%H%M%S)"
    
    log "Backing up existing extensions..."
    verbose_log "Backup location: $backup_dir"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would backup existing extensions to: $backup_dir"
        return 0
    fi
    
    # Check if there are any extensions to backup
    if [[ -n "$(ls -A "$TARGET_EXTENSIONS_DIR" 2>/dev/null)" ]]; then
        cp -r "$TARGET_EXTENSIONS_DIR" "$backup_dir"
        log "Existing extensions backed up to: $backup_dir"
    else
        verbose_log "No existing extensions to backup"
    fi
}

# Function to get extension exclude patterns
get_extension_exclude_patterns() {
    verbose_log "Getting extension exclude patterns from configuration..."
    
    local exclude_patterns
    exclude_patterns=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    ext_config = config.get('extension_sync', {})
    patterns = ext_config.get('exclude_patterns', [])
    for pattern in patterns:
        print(f'--exclude={pattern}')
" 2>/dev/null || echo "")
    
    # Add default exclusions if config parsing fails
    if [[ -z "$exclude_patterns" ]]; then
        exclude_patterns="--exclude=node_modules/ --exclude=.git/ --exclude=*.log --exclude=.tmp/ --exclude=.cache/"
    fi
    
    verbose_log "Extension exclude patterns: $exclude_patterns"
    echo "$exclude_patterns"
}

# Function to validate extension structure
validate_extension() {
    local extension_dir="$1"
    local extension_name
    extension_name=$(basename "$extension_dir")
    
    verbose_log "Validating extension: $extension_name"
    
    # Check for package.json
    if [[ ! -f "$extension_dir/package.json" ]]; then
        error_log "Extension $extension_name missing package.json"
        return 1
    fi
    
    # Check if it's a valid Directus extension
    if ! grep -q "directus" "$extension_dir/package.json" 2>/dev/null; then
        verbose_log "Warning: Extension $extension_name may not be a Directus extension"
    fi
    
    # Check for dist directory if required
    local include_dist
    include_dist=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    ext_config = config.get('extension_sync', {})
    print('true' if ext_config.get('include_dist', True) else 'false')
" 2>/dev/null || echo "true")
    
    if [[ "$include_dist" == "true" && ! -d "$extension_dir/dist" ]]; then
        verbose_log "Warning: Extension $extension_name missing dist directory"
    fi
    
    verbose_log "Extension $extension_name validation completed"
    return 0
}

# Function to deploy single extension
deploy_extension() {
    local extension_name="$1"
    local source_ext_dir="$SOURCE_EXTENSIONS_DIR/$extension_name"
    local target_ext_dir="$TARGET_EXTENSIONS_DIR/$extension_name"
    
    log "Deploying extension: $extension_name"
    verbose_log "Source: $source_ext_dir"
    verbose_log "Target: $target_ext_dir"
    
    # Validate extension first
    if ! validate_extension "$source_ext_dir"; then
        error_log "Extension validation failed: $extension_name"
        return 1
    fi
    
    # Get exclude patterns
    local exclude_patterns
    exclude_patterns=$(get_extension_exclude_patterns)
    
    # Build rsync command for extension
    local rsync_cmd="rsync --archive --verbose --delete"
    
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
    rsync_cmd="$rsync_cmd \"$source_ext_dir/\" \"$target_ext_dir/\""
    
    verbose_log "Extension rsync command: $rsync_cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would deploy extension $extension_name:"
        echo "  $rsync_cmd"
        return 0
    fi
    
    # Create target directory
    mkdir -p "$target_ext_dir"
    
    # Execute rsync
    eval "$rsync_cmd"
    
    verbose_log "Extension $extension_name deployed successfully"
}

# Function to install extension dependencies
install_extension_dependencies() {
    local extension_name="$1"
    local target_ext_dir="$TARGET_EXTENSIONS_DIR/$extension_name"
    
    if [[ "$INSTALL_DEPS" != "true" ]]; then
        verbose_log "Skipping dependency installation for $extension_name"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would install dependencies for extension: $extension_name"
        return 0
    fi
    
    # Check if package.json exists
    if [[ ! -f "$target_ext_dir/package.json" ]]; then
        verbose_log "No package.json found for $extension_name, skipping dependency installation"
        return 0
    fi
    
    # Check if package.json has dependencies
    if ! grep -q '"dependencies"' "$target_ext_dir/package.json" 2>/dev/null; then
        verbose_log "No dependencies found for $extension_name"
        return 0
    fi
    
    log "Installing dependencies for extension: $extension_name"
    
    # Change to extension directory and install
    cd "$target_ext_dir"
    
    # Choose package manager
    if [[ -f "package-lock.json" ]]; then
        verbose_log "Using npm for $extension_name"
        npm install --production --no-audit --no-fund 2>/dev/null || {
            error_log "Failed to install npm dependencies for $extension_name"
            return 1
        }
    elif [[ -f "yarn.lock" ]]; then
        verbose_log "Using yarn for $extension_name"
        if command -v yarn &> /dev/null; then
            yarn install --production --silent 2>/dev/null || {
                error_log "Failed to install yarn dependencies for $extension_name"
                return 1
            }
        else
            verbose_log "Yarn not available, falling back to npm for $extension_name"
            npm install --production --no-audit --no-fund 2>/dev/null || {
                error_log "Failed to install npm dependencies for $extension_name"
                return 1
            }
        fi
    else
        verbose_log "Using npm for $extension_name (no lock file found)"
        npm install --production --no-audit --no-fund 2>/dev/null || {
            error_log "Failed to install npm dependencies for $extension_name"
            return 1
        }
    fi
    
    cd - >/dev/null
    verbose_log "Dependencies installed for $extension_name"
}

# Function to set extension permissions
set_extension_permissions() {
    local target_ext_dir="$TARGET_EXTENSIONS_DIR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would set permissions on extensions directory"
        return 0
    fi
    
    verbose_log "Setting extension permissions..."
    
    # Set directory permissions
    find "$target_ext_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Set file permissions
    find "$target_ext_dir" -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    # Set executable permissions for any scripts
    find "$target_ext_dir" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    verbose_log "Extension permissions set"
}

# Function to verify deployment
verify_deployment() {
    verbose_log "Verifying extension deployment..."
    
    if [[ ! -f "/tmp/directus_extensions_list_$$" ]]; then
        verbose_log "No extension list found, skipping verification"
        return 0
    fi
    
    local failed_extensions=()
    
    while IFS= read -r extension_name; do
        local target_ext_dir="$TARGET_EXTENSIONS_DIR/$extension_name"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "DRY RUN: Would verify extension: $extension_name"
            continue
        fi
        
        # Check if extension directory exists
        if [[ ! -d "$target_ext_dir" ]]; then
            failed_extensions+=("$extension_name")
            continue
        fi
        
        # Check if package.json exists
        if [[ ! -f "$target_ext_dir/package.json" ]]; then
            failed_extensions+=("$extension_name")
            continue
        fi
        
        verbose_log "Extension $extension_name verified successfully"
    done < "/tmp/directus_extensions_list_$$"
    
    # Clean up temp file
    rm -f "/tmp/directus_extensions_list_$$"
    
    if [[ ${#failed_extensions[@]} -gt 0 ]]; then
        error_log "Failed to deploy extensions: ${failed_extensions[*]}"
        return 1
    fi
    
    log "All extensions verified successfully"
    return 0
}

# Main deployment function
main() {
    log "Starting extension deployment"
    
    load_config
    validate_directories
    scan_extensions
    backup_existing_extensions
    
    # Deploy each extension
    local deployment_failed=false
    
    if [[ -f "/tmp/directus_extensions_list_$$" ]]; then
        while IFS= read -r extension_name; do
            if ! deploy_extension "$extension_name"; then
                error_log "Failed to deploy extension: $extension_name"
                deployment_failed=true
                continue
            fi
            
            # Install dependencies
            if ! install_extension_dependencies "$extension_name"; then
                error_log "Failed to install dependencies for: $extension_name"
                deployment_failed=true
            fi
        done < "/tmp/directus_extensions_list_$$"
    fi
    
    # Set permissions
    set_extension_permissions
    
    # Verify deployment
    if ! verify_deployment; then
        deployment_failed=true
    fi
    
    if [[ "$deployment_failed" == "true" ]]; then
        error_log "Extension deployment completed with errors"
        exit 1
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Extension deployment completed successfully!"
        log "Extensions directory: $TARGET_EXTENSIONS_DIR"
    else
        log "DRY RUN completed - no actual deployment performed"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            SOURCE_EXTENSIONS_DIR="$2"
            shift 2
            ;;
        --target)
            TARGET_EXTENSIONS_DIR="$2"
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
        --no-backup)
            BACKUP_EXISTING=false
            shift
            ;;
        --no-install)
            INSTALL_DEPS=false
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