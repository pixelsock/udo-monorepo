#!/bin/bash

# Post-Deployment Validation Script for Directus Production
# Validates deployment success and data integrity after deployment

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
DEPLOYMENT_DIR=""
DRY_RUN=false
VERBOSE=false
CHECK_DATA_INTEGRITY=true
CHECK_API_ENDPOINTS=true
CHECK_FILE_ACCESS=true
CHECK_EXTENSIONS=true
TIMEOUT=30

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Directus deployment success and data integrity.

OPTIONS:
    --deployment-dir DIR  Directory to validate (default: current directory)
    --dry-run            Show what validations would be performed
    --verbose            Enable verbose output
    --skip-data          Skip data integrity checks
    --skip-api           Skip API endpoint checks
    --skip-files         Skip file accessibility checks
    --skip-extensions    Skip extension validation
    --timeout SECONDS    API timeout in seconds (default: 30)
    --help              Show this help message

EXAMPLES:
    $0 --deployment-dir /var/www/directus        # Validate specific deployment
    $0 --dry-run --verbose                       # Show validation plan
    $0 --skip-api --deployment-dir /prod         # Skip API checks

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

# Function to validate deployment directory
validate_deployment_directory() {
    log "Validating deployment directory structure..."
    
    local issues=0
    
    if [[ -z "$DEPLOYMENT_DIR" ]]; then
        DEPLOYMENT_DIR="$PROJECT_ROOT"
    fi
    
    verbose_log "Deployment directory: $DEPLOYMENT_DIR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would validate deployment directory: $DEPLOYMENT_DIR"
        return 0
    fi
    
    # Check if deployment directory exists
    if [[ ! -d "$DEPLOYMENT_DIR" ]]; then
        error_log "Deployment directory does not exist: $DEPLOYMENT_DIR"
        return 1
    fi
    
    # Check for essential files
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
    
    # Validate package.json content
    if [[ -f "$DEPLOYMENT_DIR/package.json" ]]; then
        if python3 -m json.tool "$DEPLOYMENT_DIR/package.json" >/dev/null 2>&1; then
            verbose_log "✓ package.json has valid JSON format"
        else
            error_log "package.json has invalid JSON format"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Deployment directory validation passed"
    else
        log "❌ Deployment directory validation failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check data integrity
check_data_integrity() {
    if [[ "$CHECK_DATA_INTEGRITY" != "true" ]]; then
        verbose_log "Skipping data integrity checks"
        return 0
    fi
    
    log "Checking data integrity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check data integrity"
        return 0
    fi
    
    local issues=0
    
    # Check if uploads directory exists and is accessible
    local uploads_dir="$DEPLOYMENT_DIR/uploads"
    if [[ -d "$uploads_dir" ]]; then
        verbose_log "✓ Uploads directory exists"
        
        # Check directory permissions
        if [[ -r "$uploads_dir" && -w "$uploads_dir" ]]; then
            verbose_log "✓ Uploads directory has correct permissions"
        else
            error_log "Uploads directory has incorrect permissions"
            ((issues++))
        fi
        
        # Count files in uploads
        local file_count
        file_count=$(find "$uploads_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
        verbose_log "Uploads directory contains $file_count files"
        
        # Check for accessibility of sample files
        if [[ $file_count -gt 0 ]]; then
            local sample_files
            sample_files=$(find "$uploads_dir" -type f | head -3)
            local accessible_count=0
            
            while IFS= read -r file; do
                if [[ -r "$file" ]]; then
                    ((accessible_count++))
                fi
            done <<< "$sample_files"
            
            if [[ $accessible_count -eq $(echo "$sample_files" | wc -l | tr -d ' ') ]]; then
                verbose_log "✓ Sample upload files are accessible"
            else
                error_log "Some upload files are not accessible"
                ((issues++))
            fi
        fi
    else
        verbose_log "No uploads directory found (may be new deployment)"
    fi
    
    # Check data directory if it exists
    local data_dir="$DEPLOYMENT_DIR/data"
    if [[ -d "$data_dir" ]]; then
        verbose_log "✓ Data directory exists"
        
        if [[ -r "$data_dir" ]]; then
            verbose_log "✓ Data directory is readable"
        else
            error_log "Data directory is not readable"
            ((issues++))
        fi
    else
        verbose_log "No data directory found (may be using external database)"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Data integrity check passed"
    else
        log "❌ Data integrity check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check API endpoints
check_api_endpoints() {
    if [[ "$CHECK_API_ENDPOINTS" != "true" ]]; then
        verbose_log "Skipping API endpoint checks"
        return 0
    fi
    
    log "Checking API endpoints..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check API endpoints"
        return 0
    fi
    
    local issues=0
    
    # Load environment to get API URL
    local env_files=(".env.production" ".env")
    local api_url=""
    
    for env_file in "${env_files[@]}"; do
        local full_path="$DEPLOYMENT_DIR/$env_file"
        if [[ -f "$full_path" ]]; then
            verbose_log "Loading environment from: $env_file"
            set -a
            source "$full_path" 2>/dev/null || true
            set +a
            
            if [[ -n "${PUBLIC_URL:-}" ]]; then
                api_url="$PUBLIC_URL"
                break
            fi
        fi
    done
    
    if [[ -z "$api_url" ]]; then
        verbose_log "No API URL found in environment - skipping API checks"
        return 0
    fi
    
    verbose_log "Testing API endpoints for: $api_url"
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        verbose_log "curl not available - skipping API endpoint checks"
        return 0
    fi
    
    # Test health endpoint
    local health_url="$api_url/server/health"
    verbose_log "Testing health endpoint: $health_url"
    
    if curl -f -s --max-time "$TIMEOUT" "$health_url" >/dev/null 2>&1; then
        verbose_log "✓ Health endpoint accessible"
    else
        error_log "Health endpoint not accessible: $health_url"
        ((issues++))
    fi
    
    # Test server info endpoint
    local info_url="$api_url/server/info"
    verbose_log "Testing server info endpoint: $info_url"
    
    if curl -f -s --max-time "$TIMEOUT" "$info_url" >/dev/null 2>&1; then
        verbose_log "✓ Server info endpoint accessible"
    else
        error_log "Server info endpoint not accessible: $info_url"
        ((issues++))
    fi
    
    # Test admin login page (should return HTML)
    local admin_url="$api_url/admin"
    verbose_log "Testing admin interface: $admin_url"
    
    local admin_response
    admin_response=$(curl -s --max-time "$TIMEOUT" "$admin_url" 2>/dev/null || echo "")
    
    if [[ -n "$admin_response" ]] && echo "$admin_response" | grep -qi "directus\|admin\|login"; then
        verbose_log "✓ Admin interface accessible"
    else
        error_log "Admin interface not accessible or not returning expected content"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ API endpoints check passed"
    else
        log "❌ API endpoints check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check file accessibility
check_file_accessibility() {
    if [[ "$CHECK_FILE_ACCESS" != "true" ]]; then
        verbose_log "Skipping file accessibility checks"
        return 0
    fi
    
    log "Checking file accessibility..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check file accessibility"
        return 0
    fi
    
    local issues=0
    
    # Check that deployment files have correct permissions
    local deployment_files=(
        "package.json"
    )
    
    for file in "${deployment_files[@]}"; do
        local full_path="$DEPLOYMENT_DIR/$file"
        if [[ -f "$full_path" ]]; then
            if [[ -r "$full_path" ]]; then
                verbose_log "✓ File is readable: $file"
            else
                error_log "File is not readable: $file"
                ((issues++))
            fi
        fi
    done
    
    # Check deployment scripts are executable
    local script_dir="$DEPLOYMENT_DIR/scripts/deployment"
    if [[ -d "$script_dir" ]]; then
        local script_count=0
        local executable_count=0
        
        while IFS= read -r -d '' script; do
            ((script_count++))
            if [[ -x "$script" ]]; then
                ((executable_count++))
            else
                error_log "Script not executable: $(basename "$script")"
                ((issues++))
            fi
        done < <(find "$script_dir" -name "*.sh" -type f -print0 2>/dev/null)
        
        if [[ $script_count -gt 0 ]]; then
            verbose_log "Deployment scripts: $executable_count/$script_count executable"
        fi
    else
        verbose_log "No deployment scripts directory found"
    fi
    
    # Check uploaded files accessibility (sample)
    local uploads_dir="$DEPLOYMENT_DIR/uploads"
    if [[ -d "$uploads_dir" ]]; then
        local sample_files
        sample_files=$(find "$uploads_dir" -type f -name "*.jpg" -o -name "*.png" -o -name "*.pdf" | head -3)
        
        if [[ -n "$sample_files" ]]; then
            local accessible_uploads=0
            local total_uploads=0
            
            while IFS= read -r file; do
                ((total_uploads++))
                if [[ -r "$file" ]]; then
                    ((accessible_uploads++))
                fi
            done <<< "$sample_files"
            
            if [[ $total_uploads -gt 0 ]]; then
                if [[ $accessible_uploads -eq $total_uploads ]]; then
                    verbose_log "✓ Sample upload files accessible ($accessible_uploads/$total_uploads)"
                else
                    error_log "Some upload files not accessible ($accessible_uploads/$total_uploads)"
                    ((issues++))
                fi
            fi
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ File accessibility check passed"
    else
        log "❌ File accessibility check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check extensions
check_extensions() {
    if [[ "$CHECK_EXTENSIONS" != "true" ]]; then
        verbose_log "Skipping extension checks"
        return 0
    fi
    
    log "Checking extensions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check extensions"
        return 0
    fi
    
    local issues=0
    local extensions_dir="$DEPLOYMENT_DIR/extensions"
    
    if [[ ! -d "$extensions_dir" ]]; then
        verbose_log "No extensions directory found"
        return 0
    fi
    
    # Count extensions
    local extension_count
    extension_count=$(find "$extensions_dir" -mindepth 1 -maxdepth 1 -type d -not -name ".*" | wc -l | tr -d ' ')
    
    verbose_log "Found $extension_count extensions"
    
    if [[ $extension_count -eq 0 ]]; then
        verbose_log "No extensions to validate"
        return 0
    fi
    
    # Validate each extension
    while IFS= read -r -d '' extension_dir; do
        local extension_name
        extension_name=$(basename "$extension_dir")
        
        # Skip hidden directories
        if [[ "${extension_name:0:1}" == "." ]]; then
            continue
        fi
        
        verbose_log "Validating extension: $extension_name"
        
        # Check for package.json
        if [[ ! -f "$extension_dir/package.json" ]]; then
            error_log "Extension $extension_name missing package.json"
            ((issues++))
        else
            verbose_log "✓ Extension $extension_name has package.json"
            
            # Validate package.json format
            if ! python3 -m json.tool "$extension_dir/package.json" >/dev/null 2>&1; then
                error_log "Extension $extension_name has invalid package.json"
                ((issues++))
            fi
        fi
        
        # Check for dist directory (if source exists)
        if [[ -d "$extension_dir/src" && ! -d "$extension_dir/dist" ]]; then
            error_log "Extension $extension_name has src but no dist directory"
            ((issues++))
        fi
        
        # Check extension permissions
        if [[ ! -r "$extension_dir" ]]; then
            error_log "Extension $extension_name directory not readable"
            ((issues++))
        fi
        
    done < <(find "$extensions_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Extensions check passed ($extension_count extensions)"
    else
        log "❌ Extensions check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to check environment configuration
check_environment() {
    log "Checking environment configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would check environment configuration"
        return 0
    fi
    
    local issues=0
    
    # Check for environment files
    local env_files=(".env.production" ".env")
    local found_env=false
    
    for env_file in "${env_files[@]}"; do
        local full_path="$DEPLOYMENT_DIR/$env_file"
        if [[ -f "$full_path" ]]; then
            verbose_log "✓ Found environment file: $env_file"
            found_env=true
            
            # Check file permissions
            if [[ ! -r "$full_path" ]]; then
                error_log "Environment file not readable: $env_file"
                ((issues++))
            fi
            
            # Check for critical variables
            local critical_vars=("DB_CLIENT" "SECRET")
            for var in "${critical_vars[@]}"; do
                if grep -q "^$var=" "$full_path" 2>/dev/null; then
                    verbose_log "✓ Found critical variable: $var"
                else
                    error_log "Missing critical variable: $var"
                    ((issues++))
                fi
            done
            
            break
        fi
    done
    
    if [[ "$found_env" != "true" ]]; then
        error_log "No environment file found"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Environment configuration check passed"
    else
        log "❌ Environment configuration check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to perform performance check
check_performance() {
    log "Performing basic performance check..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would perform performance check"
        return 0
    fi
    
    local issues=0
    
    # Check system load
    if command -v uptime &> /dev/null; then
        local load_avg
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        verbose_log "System load average: $load_avg"
        
        # Simple load check (basic threshold)
        if (( $(echo "$load_avg > 5.0" | bc -l 2>/dev/null || echo "0") )); then
            error_log "High system load detected: $load_avg"
            ((issues++))
        else
            verbose_log "✓ System load is acceptable"
        fi
    fi
    
    # Check memory usage
    if command -v free &> /dev/null; then
        local mem_usage
        mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
        verbose_log "Memory usage: ${mem_usage}%"
        
        if (( $(echo "$mem_usage > 90.0" | bc -l 2>/dev/null || echo "0") )); then
            error_log "High memory usage detected: ${mem_usage}%"
            ((issues++))
        else
            verbose_log "✓ Memory usage is acceptable"
        fi
    fi
    
    # Check disk usage
    if command -v df &> /dev/null; then
        local disk_usage
        disk_usage=$(df "$DEPLOYMENT_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
        verbose_log "Disk usage: ${disk_usage}%"
        
        if [[ $disk_usage -gt 90 ]]; then
            error_log "High disk usage detected: ${disk_usage}%"
            ((issues++))
        else
            verbose_log "✓ Disk usage is acceptable"
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "✓ Performance check passed"
    else
        log "❌ Performance check failed ($issues issues)"
    fi
    
    return $issues
}

# Function to generate validation report
generate_validation_report() {
    log "=== POST-DEPLOYMENT VALIDATION SUMMARY ==="
    log "Deployment directory: $DEPLOYMENT_DIR"
    log "Validation time: $(date)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Mode: DRY RUN (no actual validations performed)"
    else
        log "Mode: LIVE VALIDATION"
    fi
    
    # Basic deployment info
    if [[ -f "$DEPLOYMENT_DIR/package.json" && "$DRY_RUN" != "true" ]]; then
        local app_name
        app_name=$(python3 -c "import json; data=json.load(open('$DEPLOYMENT_DIR/package.json')); print(data.get('name', 'unknown'))" 2>/dev/null || echo "unknown")
        log "Application: $app_name"
    fi
}

# Main function
main() {
    log "Starting post-deployment validation"
    
    local total_issues=0
    
    # Run all validation checks
    validate_deployment_directory || ((total_issues+=$?))
    check_environment || ((total_issues+=$?))
    check_data_integrity || ((total_issues+=$?))
    check_file_accessibility || ((total_issues+=$?))
    check_extensions || ((total_issues+=$?))
    check_api_endpoints || ((total_issues+=$?))
    check_performance || ((total_issues+=$?))
    
    # Generate report
    generate_validation_report
    
    # Final result
    if [[ $total_issues -eq 0 ]]; then
        log "🎉 Post-deployment validation PASSED - deployment is successful"
        exit 0
    else
        log "❌ Post-deployment validation FAILED - found $total_issues issues"
        log "Please review and address any issues"
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --skip-data)
            CHECK_DATA_INTEGRITY=false
            shift
            ;;
        --skip-api)
            CHECK_API_ENDPOINTS=false
            shift
            ;;
        --skip-files)
            CHECK_FILE_ACCESS=false
            shift
            ;;
        --skip-extensions)
            CHECK_EXTENSIONS=false
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
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