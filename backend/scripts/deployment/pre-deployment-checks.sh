#!/bin/bash

# Pre-Deployment Checks Script for Directus Production
# Validates environment and prerequisites before deployment

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
SOURCE_DIR=""
TARGET_DIR=""
DRY_RUN=false
VERBOSE=false
CHECK_DATABASE=true
CHECK_DISK_SPACE=true
CHECK_PERMISSIONS=true
CHECK_SERVICES=true

# Minimum requirements
MIN_DISK_SPACE_MB=1024  # 1GB minimum free space
MIN_NODE_VERSION=18

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run comprehensive pre-deployment checks for Directus production deployment.

OPTIONS:
    --source DIR         Source directory (default: current directory)
    --target DIR         Target production directory (required)
    --dry-run           Show what checks would be performed
    --verbose           Enable verbose output
    --skip-database     Skip database connectivity checks
    --skip-disk         Skip disk space checks
    --skip-permissions  Skip file permissions checks
    --skip-services     Skip service availability checks
    --help             Show this help message

EXAMPLES:
    $0 --target /var/www/directus                    # Run all checks
    $0 --dry-run --target /var/www/directus          # Show what would be checked
    $0 --skip-database --target /var/www/directus    # Skip database checks

EXIT CODES:
    0 - All checks passed
    1 - One or more checks failed
    2 - Script error or invalid usage

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

# Function to validate directories
validate_directories() {
    verbose_log "Validating source and target directories..."
    
    # Set default source directory
    if [[ -z "$SOURCE_DIR" ]]; then
        SOURCE_DIR="$PROJECT_ROOT"
    fi
    
    # Validate source directory
    if [[ ! -d "$SOURCE_DIR" ]]; then
        error_log "Source directory does not exist: $SOURCE_DIR"
        return 1
    fi
    
    if [[ ! -r "$SOURCE_DIR" ]]; then
        error_log "Source directory is not readable: $SOURCE_DIR"
        return 1
    fi
    
    verbose_log "Source directory validated: $SOURCE_DIR"
    
    # Validate target directory (for dry-run, just check parent)
    if [[ -z "$TARGET_DIR" ]]; then
        error_log "Target directory must be specified"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        local parent_dir
        parent_dir=$(dirname "$TARGET_DIR")
        if [[ ! -d "$parent_dir" ]]; then
            error_log "Target parent directory does not exist: $parent_dir"
            return 1
        fi
        verbose_log "Target parent directory exists: $parent_dir"
    else
        if [[ -d "$TARGET_DIR" ]]; then
            if [[ ! -w "$TARGET_DIR" ]]; then
                error_log "Target directory is not writable: $TARGET_DIR"
                return 1
            fi
            verbose_log "Target directory is writable: $TARGET_DIR"
        else
            # Check if we can create it
            local parent_dir
            parent_dir=$(dirname "$TARGET_DIR")
            if [[ ! -d "$parent_dir" ]] || [[ ! -w "$parent_dir" ]]; then
                error_log "Cannot create target directory (parent not writable): $TARGET_DIR"
                return 1
            fi
            verbose_log "Target directory can be created: $TARGET_DIR"
        fi
    fi
    
    return 0
}

# Function to check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    local issues=0
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check system requirements"
        return 0
    fi
    
    # Check Node.js version
    if command -v node &> /dev/null; then
        local node_version
        node_version=$(node --version | sed 's/v//')
        local major_version
        major_version=$(echo "$node_version" | cut -d. -f1)
        
        if [[ $major_version -ge $MIN_NODE_VERSION ]]; then
            verbose_log "✓ Node.js version is supported: v$node_version"
        else
            error_log "Node.js version too old: v$node_version (minimum: v$MIN_NODE_VERSION)"
            ((issues++))
        fi
    else
        error_log "Node.js not found"
        ((issues++))
    fi
    
    # Check npm
    if command -v npm &> /dev/null; then
        local npm_version
        npm_version=$(npm --version)
        verbose_log "✓ npm available: v$npm_version"
    else
        error_log "npm not found"
        ((issues++))
    fi
    
    # Check rsync
    if command -v rsync &> /dev/null; then
        verbose_log "✓ rsync available: $(rsync --version | head -1)"
    else
        error_log "rsync not found (required for file sync)"
        ((issues++))
    fi
    
    # Check python3
    if command -v python3 &> /dev/null; then
        verbose_log "✓ python3 available: $(python3 --version)"
    else
        error_log "python3 not found (required for configuration parsing)"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ System requirements check passed"
    else
        log "❌ System requirements check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check disk space
check_disk_space() {
    if [[ "$CHECK_DISK_SPACE" != "true" ]]; then
        verbose_log "Skipping disk space checks"
        return 0
    fi
    
    log "Checking disk space requirements..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check disk space requirements"
        return 0
    fi
    
    local issues=0
    
    # Check available space in target directory
    local target_parent
    target_parent=$(dirname "$TARGET_DIR")
    
    if [[ -d "$target_parent" ]]; then
        local available_space_kb
        available_space_kb=$(df "$target_parent" | tail -1 | awk '{print $4}')
        local available_space_mb=$((available_space_kb / 1024))
        
        verbose_log "Available disk space: ${available_space_mb}MB"
        
        if [[ $available_space_mb -ge $MIN_DISK_SPACE_MB ]]; then
            verbose_log "✓ Sufficient disk space available"
        else
            error_log "Insufficient disk space: ${available_space_mb}MB available, ${MIN_DISK_SPACE_MB}MB required"
            ((issues++))
        fi
    else
        error_log "Cannot check disk space - target parent directory does not exist"
        ((issues++))
    fi
    
    # Check space in backup directory
    local backup_dir="$PROJECT_ROOT/backups"
    local backup_parent
    backup_parent=$(dirname "$backup_dir")
    
    if [[ -d "$backup_parent" ]]; then
        local backup_space_kb
        backup_space_kb=$(df "$backup_parent" | tail -1 | awk '{print $4}')
        local backup_space_mb=$((backup_space_kb / 1024))
        
        verbose_log "Backup directory space: ${backup_space_mb}MB"
        
        if [[ $backup_space_mb -ge $MIN_DISK_SPACE_MB ]]; then
            verbose_log "✓ Sufficient space for backups"
        else
            error_log "Insufficient space for backups: ${backup_space_mb}MB available"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Disk space check passed"
    else
        log "❌ Disk space check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check file permissions
check_permissions() {
    if [[ "$CHECK_PERMISSIONS" != "true" ]]; then
        verbose_log "Skipping file permissions checks"
        return 0
    fi
    
    log "Checking file permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check file permissions"
        return 0
    fi
    
    local issues=0
    
    # Check source directory permissions
    if [[ ! -r "$SOURCE_DIR" ]]; then
        error_log "Source directory not readable: $SOURCE_DIR"
        ((issues++))
    else
        verbose_log "✓ Source directory readable"
    fi
    
    # Check that source files are readable
    local unreadable_files
    unreadable_files=$(find "$SOURCE_DIR" -type f ! -readable 2>/dev/null | head -5)
    
    if [[ -n "$unreadable_files" ]]; then
        error_log "Found unreadable files in source directory:"
        echo "$unreadable_files" | while read -r file; do
            error_log "  $file"
        done
        ((issues++))
    else
        verbose_log "✓ Source files are readable"
    fi
    
    # Check target directory permissions
    if [[ -d "$TARGET_DIR" ]]; then
        if [[ ! -w "$TARGET_DIR" ]]; then
            error_log "Target directory not writable: $TARGET_DIR"
            ((issues++))
        else
            verbose_log "✓ Target directory writable"
        fi
    else
        # Check if parent is writable for creation
        local parent_dir
        parent_dir=$(dirname "$TARGET_DIR")
        if [[ ! -w "$parent_dir" ]]; then
            error_log "Cannot create target directory - parent not writable: $parent_dir"
            ((issues++))
        else
            verbose_log "✓ Can create target directory"
        fi
    fi
    
    # Check deployment scripts are executable
    local script_files=("$SCRIPT_DIR"/*.sh)
    for script in "${script_files[@]}"; do
        if [[ -f "$script" && ! -x "$script" ]]; then
            error_log "Deployment script not executable: $(basename "$script")"
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        verbose_log "✓ All deployment scripts are executable"
        log "✓ File permissions check passed"
    else
        log "❌ File permissions check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check database connectivity
check_database() {
    if [[ "$CHECK_DATABASE" != "true" ]]; then
        verbose_log "Skipping database connectivity checks"
        return 0
    fi
    
    log "Checking database connectivity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check database connectivity"
        return 0
    fi
    
    local issues=0
    
    # Load environment variables if available
    local env_files=(".env.production" ".env")
    local env_loaded=false
    
    for env_file in "${env_files[@]}"; do
        local full_path="$PROJECT_ROOT/$env_file"
        if [[ -f "$full_path" ]]; then
            verbose_log "Loading environment from: $env_file"
            set -a
            source "$full_path" 2>/dev/null || true
            set +a
            env_loaded=true
            break
        fi
    done
    
    if [[ "$env_loaded" != "true" ]]; then
        error_log "No environment file found - cannot test database connectivity"
        ((issues++))
    else
        # Check database connection if credentials are available
        if [[ -n "${DB_HOST:-}" && -n "${DB_DATABASE:-}" ]]; then
            verbose_log "Testing database connection to ${DB_HOST}:${DB_PORT:-5432}..."
            
            if command -v pg_isready &> /dev/null; then
                export PGPASSWORD="${DB_PASSWORD:-}"
                
                if pg_isready -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER:-postgres}" -d "${DB_DATABASE}" &> /dev/null; then
                    verbose_log "✓ Database connection successful"
                else
                    error_log "Database connection failed"
                    ((issues++))
                fi
            else
                verbose_log "pg_isready not available - skipping database connection test"
            fi
        else
            error_log "Database credentials not found in environment"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Database connectivity check passed"
    else
        log "❌ Database connectivity check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check service availability
check_services() {
    if [[ "$CHECK_SERVICES" != "true" ]]; then
        verbose_log "Skipping service availability checks"
        return 0
    fi
    
    log "Checking service availability..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check service availability"
        return 0
    fi
    
    local issues=0
    
    # Check if we're in a container environment
    if [[ -f "/.dockerenv" ]]; then
        verbose_log "Detected containerized environment"
        # In containers, external service checks might not be meaningful
        return 0
    fi
    
    # Check critical services
    local services=("systemd" "cron")
    
    for service in "${services[@]}"; do
        if command -v "$service" &> /dev/null; then
            verbose_log "✓ Service available: $service"
        else
            verbose_log "Service not available: $service (may not be required)"
        fi
    done
    
    # Check process manager (pm2, systemd, etc.)
    if command -v pm2 &> /dev/null; then
        verbose_log "✓ PM2 process manager available"
    elif command -v systemctl &> /dev/null; then
        verbose_log "✓ systemd available"
    else
        verbose_log "No process manager detected (manual service management required)"
    fi
    
    # Check web server (nginx, apache)
    if command -v nginx &> /dev/null; then
        verbose_log "✓ nginx available"
        
        # Check if nginx is running
        if pgrep nginx &> /dev/null; then
            verbose_log "✓ nginx is running"
        else
            verbose_log "nginx is installed but not running"
        fi
    elif command -v apache2 &> /dev/null || command -v httpd &> /dev/null; then
        verbose_log "✓ Apache web server available"
    else
        verbose_log "No web server detected (direct access or reverse proxy required)"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Service availability check passed"
    else
        log "❌ Service availability check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check deployment configuration
check_deployment_config() {
    log "Checking deployment configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check deployment configuration"
        return 0
    fi
    
    local issues=0
    local config_file="$SCRIPT_DIR/deploy-config.json"
    
    # Check if configuration file exists
    if [[ ! -f "$config_file" ]]; then
        error_log "Deployment configuration file not found: $config_file"
        ((issues++))
    else
        verbose_log "✓ Deployment configuration file found"
        
        # Validate JSON format
        if python3 -m json.tool "$config_file" >/dev/null 2>&1; then
            verbose_log "✓ Configuration file has valid JSON format"
        else
            error_log "Invalid JSON in configuration file"
            ((issues++))
        fi
        
        # Check for required configuration sections
        local required_sections=("exclude_patterns" "preserve_directories")
        for section in "${required_sections[@]}"; do
            if python3 -c "import json; data=json.load(open('$config_file')); exit(0 if '$section' in data else 1)" 2>/dev/null; then
                verbose_log "✓ Configuration has required section: $section"
            else
                error_log "Configuration missing required section: $section"
                ((issues++))
            fi
        done
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Deployment configuration check passed"
    else
        log "❌ Deployment configuration check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to generate pre-deployment report
generate_report() {
    log "=== PRE-DEPLOYMENT CHECKS SUMMARY ==="
    log "Source directory: $SOURCE_DIR"
    log "Target directory: $TARGET_DIR"
    log "Check time: $(date)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Mode: DRY RUN (no actual checks performed)"
    else
        log "Mode: LIVE CHECKS"
    fi
}

# Main function
main() {
    log "Starting pre-deployment checks"
    
    local total_issues=0
    
    # Validate basic parameters
    validate_directories || ((total_issues+=$?))
    
    # Run all checks
    check_system_requirements || ((total_issues+=$?))
    check_disk_space || ((total_issues+=$?))
    check_permissions || ((total_issues+=$?))
    check_database || ((total_issues+=$?))
    check_services || ((total_issues+=$?))
    check_deployment_config || ((total_issues+=$?))
    
    # Generate report
    generate_report
    
    # Final result
    if [[ $total_issues -eq 0 ]]; then
        log "🎉 All pre-deployment checks PASSED - ready for deployment"
        exit 0
    else
        log "❌ Pre-deployment checks FAILED - found $total_issues issues"
        log "Please resolve all issues before proceeding with deployment"
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --skip-database)
            CHECK_DATABASE=false
            shift
            ;;
        --skip-disk)
            CHECK_DISK_SPACE=false
            shift
            ;;
        --skip-permissions)
            CHECK_PERMISSIONS=false
            shift
            ;;
        --skip-services)
            CHECK_SERVICES=false
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