#!/bin/bash

# Deployment Version Management Script for Directus
# Manages deployment versions and backup history

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_BACKUP_DIR="$PROJECT_ROOT/backups"

# Default values
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
VERBOSE=false
ACTION=""

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [ACTION]

Manage Directus deployment versions and backup history.

ACTIONS:
    --list              List all available backup versions
    --info VERSION      Show detailed information about a version
    --cleanup           Clean up old backups (keeps recent versions)
    --tag VERSION TAG   Add a tag to a backup version
    --latest            Show the latest backup version

OPTIONS:
    --backup-dir DIR    Backup directory (default: ./backups)
    --verbose           Enable verbose output
    --help             Show this help message

EXAMPLES:
    $0 --list                                      # List all versions
    $0 --info backup-20240101-120000               # Show version details
    $0 --cleanup                                   # Clean up old backups
    $0 --tag backup-20240101-120000 "stable"      # Tag a version
    $0 --latest                                    # Show latest version

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

# Function to validate backup directory
validate_backup_directory() {
    verbose_log "Validating backup directory: $BACKUP_DIR"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "Backup directory does not exist: $BACKUP_DIR"
        log "Creating backup directory..."
        mkdir -p "$BACKUP_DIR"
    fi
    
    if [[ ! -r "$BACKUP_DIR" ]]; then
        error_log "Backup directory is not readable: $BACKUP_DIR"
        return 1
    fi
    
    verbose_log "Backup directory validated"
    return 0
}

# Function to get backup metadata
get_backup_metadata() {
    local backup_path="$1"
    local metadata_file="$backup_path/backup-metadata.json"
    
    if [[ ! -f "$metadata_file" ]]; then
        echo "No metadata available"
        return 1
    fi
    
    if ! python3 -m json.tool "$metadata_file" >/dev/null 2>&1; then
        echo "Invalid metadata format"
        return 1
    fi
    
    # Extract key information
    local backup_type timestamp size
    
    backup_type=$(python3 -c "import json; data=json.load(open('$metadata_file')); print(data.get('backup_type', 'unknown'))" 2>/dev/null || echo "unknown")
    timestamp=$(python3 -c "import json; data=json.load(open('$metadata_file')); print(data.get('timestamp', 'unknown'))" 2>/dev/null || echo "unknown")
    
    # Calculate size
    size=$(du -sh "$backup_path" 2>/dev/null | cut -f1 || echo "unknown")
    
    echo "Type: $backup_type | Timestamp: $timestamp | Size: $size"
}

# Function to get backup tags
get_backup_tags() {
    local backup_path="$1"
    local tags_file="$backup_path/.backup-tags"
    
    if [[ -f "$tags_file" ]]; then
        cat "$tags_file" | tr '\n' ' ' | sed 's/ $//'
    else
        echo ""
    fi
}

# Function to list all backup versions
list_versions() {
    log "Listing deployment backup versions..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "No backup directory found: $BACKUP_DIR"
        return 0
    fi
    
    # Find all backup directories
    local backup_dirs=()
    while IFS= read -r -d '' backup_dir; do
        backup_dirs+=("$backup_dir")
    done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name "*backup*" -print0 | sort -z)
    
    if [[ ${#backup_dirs[@]} -eq 0 ]]; then
        log "No backup versions found in: $BACKUP_DIR"
        return 0
    fi
    
    log "Found ${#backup_dirs[@]} backup versions:"
    echo ""
    
    printf "%-35s %-12s %-15s %-8s %s\n" "VERSION" "TYPE" "DATE" "SIZE" "TAGS"
    printf "%-35s %-12s %-15s %-8s %s\n" "$(printf '%*s' 35 | tr ' ' '-')" "$(printf '%*s' 12 | tr ' ' '-')" "$(printf '%*s' 15 | tr ' ' '-')" "$(printf '%*s' 8 | tr ' ' '-')" "$(printf '%*s' 20 | tr ' ' '-')"
    
    for backup_dir in "${backup_dirs[@]}"; do
        local version_name
        version_name=$(basename "$backup_dir")
        
        # Get backup metadata
        local metadata
        metadata=$(get_backup_metadata "$backup_dir" 2>/dev/null || echo "Type: unknown | Timestamp: unknown | Size: unknown")
        
        # Parse metadata
        local type timestamp size
        type=$(echo "$metadata" | sed -n 's/.*Type: \([^|]*\).*/\1/p' | tr -d ' ')
        timestamp=$(echo "$metadata" | sed -n 's/.*Timestamp: \([^|]*\).*/\1/p' | tr -d ' ')
        size=$(echo "$metadata" | sed -n 's/.*Size: \([^|]*\).*/\1/p' | tr -d ' ')
        
        # Format timestamp
        local formatted_date
        if [[ "$timestamp" != "unknown" && "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
            formatted_date=$(echo "$timestamp" | cut -d'T' -f1)
        else
            # Try to extract date from directory name
            if [[ "$version_name" =~ [0-9]{4}-?[0-9]{2}-?[0-9]{2} ]]; then
                formatted_date=$(echo "$version_name" | grep -o '[0-9]\{4\}-\?[0-9]\{2\}-\?[0-9]\{2\}' | head -1 | sed 's/-//g' | sed 's/\(.\{4\}\)\(.\{2\}\)\(.\{2\}\)/\1-\2-\3/')
            else
                formatted_date="unknown"
            fi
        fi
        
        # Get tags
        local tags
        tags=$(get_backup_tags "$backup_dir")
        if [[ -z "$tags" ]]; then
            tags="-"
        fi
        
        printf "%-35s %-12s %-15s %-8s %s\n" "$version_name" "$type" "$formatted_date" "$size" "$tags"
    done
    
    echo ""
    log "Total backup versions: ${#backup_dirs[@]}"
    
    # Show total size
    local total_size
    total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log "Total backup storage used: $total_size"
}

# Function to show version info
show_version_info() {
    local version="$1"
    local backup_path="$BACKUP_DIR/$version"
    
    log "Showing information for version: $version"
    
    if [[ ! -d "$backup_path" ]]; then
        error_log "Version not found: $version"
        return 1
    fi
    
    echo ""
    echo "=== VERSION INFORMATION ==="
    echo "Version: $version"
    echo "Path: $backup_path"
    echo ""
    
    # Show metadata if available
    local metadata_file="$backup_path/backup-metadata.json"
    if [[ -f "$metadata_file" ]]; then
        echo "=== METADATA ==="
        if python3 -m json.tool "$metadata_file" 2>/dev/null; then
            echo ""
        else
            echo "Metadata file exists but has invalid JSON format"
            echo ""
        fi
    else
        echo "No metadata file found"
        echo ""
    fi
    
    # Show tags if available
    local tags
    tags=$(get_backup_tags "$backup_path")
    if [[ -n "$tags" ]]; then
        echo "=== TAGS ==="
        echo "$tags"
        echo ""
    fi
    
    # Show directory structure
    echo "=== CONTENTS ==="
    ls -la "$backup_path" 2>/dev/null || echo "Cannot list directory contents"
    echo ""
    
    # Show size breakdown
    echo "=== SIZE BREAKDOWN ==="
    du -sh "$backup_path"/* 2>/dev/null | sort -hr || echo "Cannot calculate size breakdown"
    echo ""
    
    # Check if this version can be used for rollback
    echo "=== ROLLBACK COMPATIBILITY ==="
    if [[ -f "$backup_path/backup-metadata.json" ]] || [[ -f "$backup_path/package.json" ]] || [[ -d "$backup_path/files" ]]; then
        echo "✓ This version appears compatible for rollback"
        echo "To rollback to this version, run:"
        echo "  bash $SCRIPT_DIR/rollback.sh --backup \"$backup_path\" --target /path/to/production"
    else
        echo "⚠ This version may not be compatible for automatic rollback"
        echo "Manual restoration may be required"
    fi
    echo ""
}

# Function to add tag to version
tag_version() {
    local version="$1"
    local tag="$2"
    local backup_path="$BACKUP_DIR/$version"
    
    log "Adding tag '$tag' to version: $version"
    
    if [[ ! -d "$backup_path" ]]; then
        error_log "Version not found: $version"
        return 1
    fi
    
    # Validate tag format (alphanumeric, dashes, underscores only)
    if [[ ! "$tag" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_log "Invalid tag format. Use only alphanumeric characters, dashes, and underscores."
        return 1
    fi
    
    local tags_file="$backup_path/.backup-tags"
    
    # Check if tag already exists
    if [[ -f "$tags_file" ]] && grep -q "^$tag$" "$tags_file" 2>/dev/null; then
        log "Tag '$tag' already exists for this version"
        return 0
    fi
    
    # Add tag
    echo "$tag" >> "$tags_file"
    
    verbose_log "Tag '$tag' added to version $version"
    log "✓ Tag added successfully"
}

# Function to show latest version
show_latest_version() {
    log "Finding latest backup version..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "No backup directory found: $BACKUP_DIR"
        return 0
    fi
    
    # Find the most recent backup directory
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name "*backup*" -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
    
    if [[ -z "$latest_backup" ]]; then
        log "No backup versions found"
        return 0
    fi
    
    local version_name
    version_name=$(basename "$latest_backup")
    
    log "Latest version: $version_name"
    
    # Show brief info
    local metadata
    metadata=$(get_backup_metadata "$latest_backup" 2>/dev/null || echo "Type: unknown | Timestamp: unknown | Size: unknown")
    
    echo "Details: $metadata"
    
    # Show tags if any
    local tags
    tags=$(get_backup_tags "$latest_backup")
    if [[ -n "$tags" ]]; then
        echo "Tags: $tags"
    fi
    
    echo "Path: $latest_backup"
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backup versions..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "No backup directory found: $BACKUP_DIR"
        return 0
    fi
    
    # Configuration for cleanup
    local keep_recent=10          # Keep 10 most recent backups
    local keep_tagged_days=90     # Keep tagged backups for 90 days
    local keep_untagged_days=30   # Keep untagged backups for 30 days
    
    log "Cleanup policy:"
    log "  - Keep $keep_recent most recent backups"
    log "  - Keep tagged backups for $keep_tagged_days days"
    log "  - Keep untagged backups for $keep_untagged_days days"
    
    # Get all backup directories sorted by modification time (newest first)
    local backup_dirs=()
    while IFS= read -r backup_dir; do
        backup_dirs+=("$backup_dir")
    done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name "*backup*" -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-)
    
    if [[ ${#backup_dirs[@]} -eq 0 ]]; then
        log "No backup versions found to clean up"
        return 0
    fi
    
    log "Found ${#backup_dirs[@]} backup versions"
    
    local removed_count=0
    local kept_count=0
    local current_time
    current_time=$(date +%s)
    
    for i in "${!backup_dirs[@]}"; do
        local backup_dir="${backup_dirs[$i]}"
        local version_name
        version_name=$(basename "$backup_dir")
        
        local should_keep=false
        local reason=""
        
        # Keep most recent backups
        if [[ $i -lt $keep_recent ]]; then
            should_keep=true
            reason="recent (top $keep_recent)"
        else
            # Check if backup has tags
            local tags
            tags=$(get_backup_tags "$backup_dir")
            
            # Get backup age in days
            local backup_time
            backup_time=$(stat -c %Y "$backup_dir" 2>/dev/null || echo "$current_time")
            local age_days=$(( (current_time - backup_time) / 86400 ))
            
            if [[ -n "$tags" ]]; then
                # Tagged backup
                if [[ $age_days -le $keep_tagged_days ]]; then
                    should_keep=true
                    reason="tagged and within $keep_tagged_days days (tags: $tags)"
                fi
            else
                # Untagged backup
                if [[ $age_days -le $keep_untagged_days ]]; then
                    should_keep=true
                    reason="within $keep_untagged_days days"
                fi
            fi
        fi
        
        if [[ "$should_keep" == "true" ]]; then
            verbose_log "Keeping $version_name: $reason"
            ((kept_count++))
        else
            log "Removing old backup: $version_name"
            if rm -rf "$backup_dir"; then
                ((removed_count++))
                verbose_log "Removed: $backup_dir"
            else
                error_log "Failed to remove: $backup_dir"
            fi
        fi
    done
    
    log "Cleanup completed:"
    log "  - Kept: $kept_count versions"
    log "  - Removed: $removed_count versions"
    
    # Show new total size
    local total_size
    total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log "Current backup storage used: $total_size"
}

# Main function
main() {
    verbose_log "Starting deployment version management"
    
    # Validate backup directory
    if ! validate_backup_directory; then
        exit 1
    fi
    
    # Execute action
    case "$ACTION" in
        list)
            list_versions
            ;;
        info)
            if [[ -z "${VERSION:-}" ]]; then
                error_log "Version must be specified for info action"
                exit 1
            fi
            show_version_info "$VERSION"
            ;;
        tag)
            if [[ -z "${VERSION:-}" ]] || [[ -z "${TAG:-}" ]]; then
                error_log "Version and tag must be specified for tag action"
                exit 1
            fi
            tag_version "$VERSION" "$TAG"
            ;;
        latest)
            show_latest_version
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        *)
            error_log "No action specified or invalid action: $ACTION"
            usage
            exit 1
            ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --list)
            ACTION="list"
            shift
            ;;
        --info)
            ACTION="info"
            VERSION="$2"
            shift 2
            ;;
        --tag)
            ACTION="tag"
            VERSION="$2"
            TAG="$3"
            shift 3
            ;;
        --latest)
            ACTION="latest"
            shift
            ;;
        --cleanup)
            ACTION="cleanup"
            shift
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
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

# Check if action was specified
if [[ -z "$ACTION" ]]; then
    echo "No action specified"
    usage
    exit 1
fi

# Run main function
main