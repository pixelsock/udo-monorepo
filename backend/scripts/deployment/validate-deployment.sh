#!/bin/bash

# Deployment Validation Script for Directus Production
# Validates that deployment was successful and data is preserved

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
DEPLOYMENT_DIR=""
VERBOSE=false
CHECK_DATABASE=true
CHECK_FILES=true
CHECK_EXTENSIONS=true
CHECK_SERVICES=true

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Directus deployment integrity and functionality.

OPTIONS:
    --deployment-dir DIR   Directory to validate (default: current directory)
    --verbose             Enable verbose output
    --skip-database       Skip database connectivity checks
    --skip-files          Skip file accessibility checks
    --skip-extensions     Skip extension validation
    --skip-services       Skip service health checks
    --help               Show this help message

EXAMPLES:
    $0                                    # Validate current directory
    $0 --deployment-dir /var/www/directus # Validate specific deployment
    $0 --verbose --skip-database          # Verbose validation without DB check

EXIT CODES:
    0 - Validation passed
    1 - Validation failed
    2 - Script error

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

# Function to validate deployment directory structure
validate_directory_structure() {
    log "Validating deployment directory structure..."
    
    local issues=0
    
    # Check if deployment directory exists
    if [[ ! -d "$DEPLOYMENT_DIR" ]]; then
        error_log "Deployment directory does not exist: $DEPLOYMENT_DIR"
        return 1
    fi
    
    verbose_log "Deployment directory: $DEPLOYMENT_DIR"
    
    # Check for essential Directus files
    local essential_files=(
        "package.json"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$DEPLOYMENT_DIR/$file" ]]; then
            error_log "Missing essential file: $file"
            ((issues++))
        else
            verbose_log "✓ Found essential file: $file"
        fi
    done
    
    # Check that data directories are preserved (should exist but not be empty if they had data)
    local data_dirs=("uploads" "data")
    
    for dir in "${data_dirs[@]}"; do
        local full_path="$DEPLOYMENT_DIR/$dir"
        if [[ -d "$full_path" ]]; then
            verbose_log "✓ Data directory preserved: $dir"
        else
            verbose_log "Note: Data directory not found: $dir (may not exist in this deployment)"
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Directory structure validation passed"
    else
        log "❌ Directory structure validation failed ($issues issues)"
    fi
    
    return $issues
}

# Function to validate file accessibility
validate_file_accessibility() {
    if [[ "$CHECK_FILES" != "true" ]]; then
        verbose_log "Skipping file accessibility checks"
        return 0
    fi
    
    log "Validating file accessibility..."
    
    local issues=0
    
    # Check uploads directory if it exists
    local uploads_dir="$DEPLOYMENT_DIR/uploads"
    if [[ -d "$uploads_dir" ]]; then
        verbose_log "Checking uploads directory accessibility..."
        
        # Check directory permissions
        if [[ ! -r "$uploads_dir" ]]; then
            error_log "Uploads directory is not readable"
            ((issues++))
        else
            verbose_log "✓ Uploads directory is readable"
        fi
        
        # Check for sample files and their accessibility
        local sample_files
        sample_files=$(find "$uploads_dir" -type f -name "*.jpg" -o -name "*.png" -o -name "*.pdf" | head -5)
        
        if [[ -n "$sample_files" ]]; then
            local accessible_count=0
            local total_count=0
            
            while IFS= read -r file; do
                ((total_count++))
                if [[ -r "$file" ]]; then
                    ((accessible_count++))
                fi
            done <<< "$sample_files"
            
            if [[ $accessible_count -eq $total_count ]]; then
                verbose_log "✓ Sample files are accessible ($accessible_count/$total_count)"
            else
                error_log "Some files are not accessible ($accessible_count/$total_count)"
                ((issues++))
            fi
        else
            verbose_log "No sample files found to test accessibility"
        fi
    else
        verbose_log "No uploads directory found"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ File accessibility validation passed"
    else
        log "❌ File accessibility validation failed ($issues issues)"
    fi
    
    return $issues
}

# Function to validate extensions
validate_extensions() {
    if [[ "$CHECK_EXTENSIONS" != "true" ]]; then
        verbose_log "Skipping extension validation"
        return 0
    fi
    
    log "Validating extensions..."
    
    local issues=0
    local extensions_dir="$DEPLOYMENT_DIR/extensions"
    
    if [[ ! -d "$extensions_dir" ]]; then
        verbose_log "No extensions directory found"
        return 0
    fi
    
    # Count extensions
    local extension_count
    extension_count=$(find "$extensions_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    
    verbose_log "Found $extension_count extensions"
    
    if [[ $extension_count -eq 0 ]]; then
        verbose_log "No extensions to validate"
        return 0
    fi
    
    # Validate each extension
    while IFS= read -r -d '' extension_dir; do
        local extension_name
        extension_name=$(basename "$extension_dir")
        
        verbose_log "Validating extension: $extension_name"
        
        # Check for package.json
        if [[ ! -f "$extension_dir/package.json" ]]; then
            error_log "Extension $extension_name missing package.json"
            ((issues++))
        else
            verbose_log "✓ Extension $extension_name has package.json"
        fi
        
        # Check for dist directory (if it should exist)
        if [[ -d "$extension_dir/src" && ! -d "$extension_dir/dist" ]]; then
            error_log "Extension $extension_name has src but no dist directory"
            ((issues++))
        fi
        
    done < <(find "$extensions_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Extension validation passed ($extension_count extensions)"
    else
        log "❌ Extension validation failed ($issues issues)"
    fi
    
    return $issues
}

# Function to validate database connectivity
validate_database_connectivity() {
    if [[ "$CHECK_DATABASE" != "true" ]]; then
        verbose_log "Skipping database connectivity checks"
        return 0
    fi
    
    log "Validating database connectivity..."
    
    local issues=0
    
    # Load environment variables if available
    local env_file="$DEPLOYMENT_DIR/.env.production"
    if [[ -f "$env_file" ]]; then
        # Source environment file safely
        set -a
        source "$env_file" 2>/dev/null || true
        set +a
        verbose_log "Loaded environment from: $env_file"
    else
        verbose_log "No production environment file found"
    fi
    
    # Check database connection if credentials are available
    if [[ -n "${DB_HOST:-}" && -n "${DB_DATABASE:-}" ]]; then
        verbose_log "Testing database connection to $DB_HOST..."
        
        if command -v pg_isready &> /dev/null; then
            export PGPASSWORD="${DB_PASSWORD:-}"
            
            if pg_isready -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER:-postgres}" -d "${DB_DATABASE}" &> /dev/null; then
                verbose_log "✓ Database connection successful"
            else
                error_log "Database connection failed"
                ((issues++))
            fi
        else
            verbose_log "pg_isready not available, skipping database connection test"
        fi
    else
        verbose_log "Database credentials not available, skipping connection test"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Database connectivity validation passed"
    else
        log "❌ Database connectivity validation failed ($issues issues)"
    fi
    
    return $issues
}

# Function to validate service health
validate_service_health() {
    if [[ "$CHECK_SERVICES" != "true" ]]; then
        verbose_log "Skipping service health checks"
        return 0
    fi
    
    log "Validating service health..."
    
    local issues=0
    
    # Check if this is running in a containerized environment
    if [[ -f "/.dockerenv" ]]; then
        verbose_log "Detected Docker environment"
        
        # In Docker, we might not be able to check external services
        verbose_log "Skipping external service checks in containerized environment"
    else
        verbose_log "Detected native environment"
        
        # Check for common service dependencies
        local services=("node" "npm")
        
        for service in "${services[@]}"; do
            if command -v "$service" &> /dev/null; then
                verbose_log "✓ Service available: $service"
            else
                error_log "Service not available: $service"
                ((issues++))
            fi
        done
    fi
    
    # Check Node.js version if available
    if command -v node &> /dev/null; then
        local node_version
        node_version=$(node --version)
        verbose_log "Node.js version: $node_version"
        
        # Extract major version number
        local major_version
        major_version=$(echo "$node_version" | sed 's/v\([0-9]*\).*/\1/')
        
        if [[ $major_version -ge 18 ]]; then
            verbose_log "✓ Node.js version is supported"
        else
            error_log "Node.js version may be too old: $node_version"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Service health validation passed"
    else
        log "❌ Service health validation failed ($issues issues)"
    fi
    
    return $issues
}

# Function to validate environment configuration
validate_environment() {
    log "Validating environment configuration..."
    
    local issues=0
    
    # Check for environment files
    local env_files=(".env.production" ".env")
    local found_env=false
    
    for env_file in "${env_files[@]}"; do
        local full_path="$DEPLOYMENT_DIR/$env_file"
        if [[ -f "$full_path" ]]; then
            verbose_log "✓ Found environment file: $env_file"
            found_env=true
            
            # Basic validation of environment file
            if [[ -r "$full_path" ]]; then
                verbose_log "✓ Environment file is readable"
                
                # Check for critical environment variables
                local critical_vars=("DB_CLIENT" "SECRET")
                for var in "${critical_vars[@]}"; do
                    if grep -q "^$var=" "$full_path" 2>/dev/null; then
                        verbose_log "✓ Found critical variable: $var"
                    else
                        error_log "Missing critical variable: $var"
                        ((issues++))
                    fi
                done
            else
                error_log "Environment file is not readable: $env_file"
                ((issues++))
            fi
        fi
    done
    
    if [[ "$found_env" != "true" ]]; then
        error_log "No environment file found"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Environment configuration validation passed"
    else
        log "❌ Environment configuration validation failed ($issues issues)"
    fi
    
    return $issues
}

# Main validation function
main() {
    log "Starting deployment validation"
    
    # Set default deployment directory
    if [[ -z "$DEPLOYMENT_DIR" ]]; then
        DEPLOYMENT_DIR="$PROJECT_ROOT"
    fi
    
    log "Validating deployment in: $DEPLOYMENT_DIR"
    
    local total_issues=0
    
    # Run validation checks
    validate_directory_structure || ((total_issues+=$?))
    validate_environment || ((total_issues+=$?))
    validate_file_accessibility || ((total_issues+=$?))
    validate_extensions || ((total_issues+=$?))
    validate_database_connectivity || ((total_issues+=$?))
    validate_service_health || ((total_issues+=$?))
    
    # Summary
    log "=== Deployment Validation Summary ==="
    
    if [[ $total_issues -eq 0 ]]; then
        log "🎉 Deployment validation PASSED - deployment appears to be successful"
        exit 0
    else
        log "❌ Deployment validation FAILED - found $total_issues issues"
        log "Please review the deployment and address any issues"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment-dir)
            DEPLOYMENT_DIR="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --skip-database)
            CHECK_DATABASE=false
            shift
            ;;
        --skip-files)
            CHECK_FILES=false
            shift
            ;;
        --skip-extensions)
            CHECK_EXTENSIONS=false
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