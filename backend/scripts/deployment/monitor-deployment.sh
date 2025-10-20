#!/bin/bash

# Deployment Monitoring Script for Directus Production
# Monitors deployment status and provides health insights

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
DEPLOYMENT_DIR=""
VERBOSE=false
WATCH_MODE=false
INTERVAL=30
OUTPUT_FORMAT="text"
ALERT_THRESHOLD=3

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Monitor Directus deployment status and health.

OPTIONS:
    --deployment-dir DIR  Directory to monitor (default: current directory)
    --watch              Watch mode - continuous monitoring
    --interval SECONDS   Check interval for watch mode (default: 30)
    --format FORMAT      Output format: text, json, csv (default: text)
    --verbose            Enable verbose output
    --alert-threshold N  Alert after N consecutive failures (default: 3)
    --help              Show this help message

EXAMPLES:
    $0 --deployment-dir /var/www/directus           # Single status check
    $0 --watch --interval 60                       # Watch with 60s interval
    $0 --format json                               # JSON output
    $0 --watch --verbose                          # Verbose watch mode

OUTPUT FORMATS:
    text - Human-readable text output
    json - Machine-readable JSON output
    csv  - Comma-separated values for logging

EOF
}

# Function for logging
log() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    fi
}

# Function for verbose logging
verbose_log() {
    if [[ "$VERBOSE" == "true" && "$OUTPUT_FORMAT" == "text" ]]; then
        log "VERBOSE: $1"
    fi
}

# Function for error logging
error_log() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    fi
}

# Function to check deployment directory health
check_deployment_health() {
    local health_status="healthy"
    local issues=()
    local metrics={}
    
    verbose_log "Checking deployment directory health..."
    
    # Check if deployment directory exists
    if [[ ! -d "$DEPLOYMENT_DIR" ]]; then
        health_status="critical"
        issues+=("Deployment directory does not exist")
        return 1
    fi
    
    # Check essential files
    local essential_files=("package.json")
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$DEPLOYMENT_DIR/$file" ]]; then
            health_status="degraded"
            issues+=("Missing essential file: $file")
        fi
    done
    
    # Check file permissions
    if [[ ! -r "$DEPLOYMENT_DIR" ]]; then
        health_status="critical"
        issues+=("Deployment directory not readable")
    fi
    
    if [[ ! -w "$DEPLOYMENT_DIR" ]]; then
        health_status="degraded"
        issues+=("Deployment directory not writable")
    fi
    
    # Check disk space
    local disk_usage
    disk_usage=$(df "$DEPLOYMENT_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [[ $disk_usage -gt 90 ]]; then
        health_status="critical"
        issues+=("High disk usage: ${disk_usage}%")
    elif [[ $disk_usage -gt 80 ]]; then
        if [[ "$health_status" == "healthy" ]]; then
            health_status="warning"
        fi
        issues+=("Disk usage warning: ${disk_usage}%")
    fi
    
    # Store metrics
    metrics="{\"disk_usage\": $disk_usage, \"issues_count\": ${#issues[@]}}"
    
    # Return status
    case "$health_status" in
        "healthy")
            return 0
            ;;
        "warning"|"degraded")
            return 1
            ;;
        "critical")
            return 2
            ;;
    esac
}

# Function to check API health
check_api_health() {
    local api_status="unknown"
    local response_time=0
    local status_code=0
    
    verbose_log "Checking API health..."
    
    # Load environment to get API URL
    local env_files=(".env.production" ".env")
    local api_url=""
    
    for env_file in "${env_files[@]}"; do
        local full_path="$DEPLOYMENT_DIR/$env_file"
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
    
    if [[ -z "$api_url" ]]; then
        verbose_log "No API URL found, skipping API health check"
        return 0
    fi
    
    if ! command -v curl &> /dev/null; then
        verbose_log "curl not available, skipping API health check"
        return 0
    fi
    
    # Test health endpoint
    local health_url="$api_url/server/health"
    verbose_log "Testing API endpoint: $health_url"
    
    local start_time
    start_time=$(date +%s%N)
    
    if curl -f -s --max-time 10 "$health_url" >/dev/null 2>&1; then
        local end_time
        end_time=$(date +%s%N)
        response_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
        status_code=200
        api_status="healthy"
        verbose_log "API health check passed (${response_time}ms)"
        return 0
    else
        api_status="unhealthy"
        status_code=0
        verbose_log "API health check failed"
        return 1
    fi
}

# Function to check database connectivity
check_database_health() {
    local db_status="unknown"
    
    verbose_log "Checking database health..."
    
    # Load environment
    local env_files=(".env.production" ".env")
    local db_loaded=false
    
    for env_file in "${env_files[@]}"; do
        local full_path="$DEPLOYMENT_DIR/$env_file"
        if [[ -f "$full_path" ]]; then
            set -a
            source "$full_path" 2>/dev/null || true
            set +a
            db_loaded=true
            break
        fi
    done
    
    if [[ "$db_loaded" != "true" ]]; then
        verbose_log "No environment file found, skipping database check"
        return 0
    fi
    
    # Check database connection if credentials are available
    if [[ -n "${DB_HOST:-}" && -n "${DB_DATABASE:-}" ]]; then
        if command -v pg_isready &> /dev/null; then
            export PGPASSWORD="${DB_PASSWORD:-}"
            
            if pg_isready -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER:-postgres}" -d "${DB_DATABASE}" &> /dev/null; then
                db_status="healthy"
                verbose_log "Database connection successful"
                return 0
            else
                db_status="unhealthy"
                verbose_log "Database connection failed"
                return 1
            fi
        else
            verbose_log "pg_isready not available, skipping database check"
            return 0
        fi
    else
        verbose_log "Database credentials not available, skipping database check"
        return 0
    fi
}

# Function to check recent deployment logs
check_deployment_logs() {
    local log_status="healthy"
    local recent_errors=0
    
    verbose_log "Checking deployment logs..."
    
    local log_dir="$PROJECT_ROOT/logs"
    if [[ ! -d "$log_dir" ]]; then
        verbose_log "No log directory found"
        return 0
    fi
    
    # Find recent deployment logs (last 24 hours)
    local recent_logs
    recent_logs=$(find "$log_dir" -name "deployment-*.log" -mtime -1 2>/dev/null || echo "")
    
    if [[ -z "$recent_logs" ]]; then
        verbose_log "No recent deployment logs found"
        return 0
    fi
    
    # Count errors in recent logs
    while IFS= read -r log_file; do
        if [[ -f "$log_file" ]]; then
            local error_count
            error_count=$(grep -c "ERROR:" "$log_file" 2>/dev/null || echo "0")
            recent_errors=$((recent_errors + error_count))
        fi
    done <<< "$recent_logs"
    
    verbose_log "Found $recent_errors recent deployment errors"
    
    if [[ $recent_errors -gt 5 ]]; then
        log_status="unhealthy"
        return 1
    elif [[ $recent_errors -gt 0 ]]; then
        log_status="warning"
        return 1
    fi
    
    return 0
}

# Function to get system metrics
get_system_metrics() {
    local metrics="{}"
    
    # Memory usage
    if command -v free &> /dev/null; then
        local mem_usage
        mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
        metrics=$(echo "$metrics" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
data['memory_usage_percent'] = $mem_usage
print(json.dumps(data))
")
    fi
    
    # Load average
    if command -v uptime &> /dev/null; then
        local load_avg
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        metrics=$(echo "$metrics" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
data['load_average'] = '$load_avg'
print(json.dumps(data))
")
    fi
    
    # Process count
    if command -v ps &> /dev/null; then
        local process_count
        process_count=$(ps aux | wc -l)
        metrics=$(echo "$metrics" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
data['process_count'] = $process_count
print(json.dumps(data))
")
    fi
    
    echo "$metrics"
}

# Function to output status in specified format
output_status() {
    local overall_status="$1"
    local deployment_status="$2"
    local api_status="$3"
    local db_status="$4"
    local log_status="$5"
    local metrics="$6"
    
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    case "$OUTPUT_FORMAT" in
        "json")
            cat << EOF
{
    "timestamp": "$timestamp",
    "deployment_dir": "$DEPLOYMENT_DIR",
    "overall_status": "$overall_status",
    "components": {
        "deployment": "$deployment_status",
        "api": "$api_status",
        "database": "$db_status",
        "logs": "$log_status"
    },
    "metrics": $metrics
}
EOF
            ;;
        "csv")
            echo "$timestamp,$DEPLOYMENT_DIR,$overall_status,$deployment_status,$api_status,$db_status,$log_status"
            ;;
        "text"|*)
            echo "=== Directus Deployment Status ==="
            echo "Time: $timestamp"
            echo "Deployment Directory: $DEPLOYMENT_DIR"
            echo ""
            echo "Overall Status: $overall_status"
            echo ""
            echo "Component Status:"
            echo "  Deployment: $deployment_status"
            echo "  API: $api_status"  
            echo "  Database: $db_status"
            echo "  Logs: $log_status"
            echo ""
            if [[ "$metrics" != "{}" ]]; then
                echo "System Metrics:"
                echo "$metrics" | python3 -c "
import json
import sys
try:
    data = json.load(sys.stdin)
    for key, value in data.items():
        print(f'  {key.replace(\"_\", \" \").title()}: {value}')
except:
    pass
" 2>/dev/null || echo "  (metrics unavailable)"
            fi
            echo ""
            ;;
    esac
}

# Function to determine overall status
determine_overall_status() {
    local deployment_status="$1"
    local api_status="$2"
    local db_status="$3"
    local log_status="$4"
    
    # Priority: critical > unhealthy > warning > degraded > healthy
    local statuses=("$deployment_status" "$api_status" "$db_status" "$log_status")
    
    for status in "${statuses[@]}"; do
        case "$status" in
            "critical"|"unhealthy")
                echo "critical"
                return
                ;;
        esac
    done
    
    for status in "${statuses[@]}"; do
        case "$status" in
            "warning"|"degraded")
                echo "warning"
                return
                ;;
        esac
    done
    
    echo "healthy"
}

# Function to perform single status check
perform_status_check() {
    local deployment_status="healthy"
    local api_status="healthy"
    local db_status="healthy" 
    local log_status="healthy"
    
    # Check deployment health
    if ! check_deployment_health; then
        case $? in
            1) deployment_status="warning" ;;
            2) deployment_status="critical" ;;
        esac
    fi
    
    # Check API health
    if ! check_api_health; then
        api_status="unhealthy"
    fi
    
    # Check database health
    if ! check_database_health; then
        db_status="unhealthy"
    fi
    
    # Check deployment logs
    if ! check_deployment_logs; then
        log_status="warning"
    fi
    
    # Get system metrics
    local metrics
    metrics=$(get_system_metrics)
    
    # Determine overall status
    local overall_status
    overall_status=$(determine_overall_status "$deployment_status" "$api_status" "$db_status" "$log_status")
    
    # Output status
    output_status "$overall_status" "$deployment_status" "$api_status" "$db_status" "$log_status" "$metrics"
    
    # Return exit code based on overall status
    case "$overall_status" in
        "healthy") return 0 ;;
        "warning") return 1 ;;
        "critical") return 2 ;;
    esac
}

# Function for watch mode
watch_deployment() {
    log "Starting deployment monitoring (watch mode)"
    log "Checking every $INTERVAL seconds..."
    log "Press Ctrl+C to stop"
    echo ""
    
    local consecutive_failures=0
    local alert_sent=false
    
    while true; do
        if perform_status_check; then
            consecutive_failures=0
            alert_sent=false
        else
            ((consecutive_failures++))
            
            if [[ $consecutive_failures -ge $ALERT_THRESHOLD && "$alert_sent" == "false" ]]; then
                log "ALERT: $consecutive_failures consecutive health check failures!"
                alert_sent=true
            fi
        fi
        
        if [[ "$OUTPUT_FORMAT" == "text" ]]; then
            echo "---"
        fi
        
        sleep "$INTERVAL"
    done
}

# Main monitoring function
main() {
    verbose_log "Starting deployment monitoring"
    
    # Set default deployment directory
    if [[ -z "$DEPLOYMENT_DIR" ]]; then
        DEPLOYMENT_DIR="$PROJECT_ROOT"
    fi
    
    # Validate deployment directory
    if [[ ! -d "$DEPLOYMENT_DIR" ]]; then
        error_log "Deployment directory does not exist: $DEPLOYMENT_DIR"
        exit 1
    fi
    
    verbose_log "Monitoring deployment directory: $DEPLOYMENT_DIR"
    
    # Output CSV header if needed
    if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
        echo "timestamp,deployment_dir,overall_status,deployment_status,api_status,database_status,log_status"
    fi
    
    # Run monitoring
    if [[ "$WATCH_MODE" == "true" ]]; then
        watch_deployment
    else
        perform_status_check
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment-dir)
            DEPLOYMENT_DIR="$2"
            shift 2
            ;;
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --alert-threshold)
            ALERT_THRESHOLD="$2"
            shift 2
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

# Validate output format
case "$OUTPUT_FORMAT" in
    "text"|"json"|"csv")
        ;;
    *)
        error_log "Invalid output format: $OUTPUT_FORMAT"
        exit 1
        ;;
esac

# Run main function
main