#!/bin/bash

# File Backup Script for Directus Production
# Backs up all uploaded files and assets with timestamped directory structure

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_BASE_DIR="$PROJECT_ROOT/backups"

# Default source and target
DEFAULT_SOURCE_DIR="$PROJECT_ROOT/uploads"
SOURCE_DIR=""
TARGET_DIR=""

# Script options
DRY_RUN=false
VERBOSE=false
EXCLUDE_CACHE=true
TIMESTAMP=$(date +"%Y-%m-%dT%H-%M-%S")
BACKUP_NAME="directus-files-backup-$TIMESTAMP"

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create a timestamped backup of Directus upload files and assets.

OPTIONS:
    --source DIR       Source directory to backup (default: ./uploads)
    --target DIR       Target backup directory (default: ./backups/TIMESTAMP)
    --dry-run          Show what would be backed up without executing
    --verbose          Enable verbose output
    --include-cache    Include cache files in backup (default: exclude)
    --help            Show this help message

EXAMPLES:
    $0                                    # Backup default uploads directory
    $0 --source ./uploads --dry-run       # Show what would be backed up
    $0 --verbose --include-cache          # Verbose backup including cache files
    $0 --source /custom/path              # Backup from custom directory

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

# Function to check prerequisites
check_prerequisites() {
    verbose_log "Checking prerequisites..."
    
    # Check if rsync is available (more efficient than cp for large files)
    if command -v rsync &> /dev/null; then
        verbose_log "Using rsync for file operations"
    else
        verbose_log "rsync not available, will use cp"
    fi
    
    verbose_log "Prerequisites check passed"
}

# Function to validate source directory
validate_source() {
    if [[ -z "$SOURCE_DIR" ]]; then
        SOURCE_DIR="$DEFAULT_SOURCE_DIR"
    fi
    
    verbose_log "Source directory: $SOURCE_DIR"
    
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo "Error: Source directory does not exist: $SOURCE_DIR"
        exit 1
    fi
    
    if [[ ! -r "$SOURCE_DIR" ]]; then
        echo "Error: Source directory is not readable: $SOURCE_DIR"
        exit 1
    fi
    
    verbose_log "Source directory validation passed"
}

# Function to calculate directory size
calculate_source_size() {
    verbose_log "Calculating source directory size..."
    
    local size
    if command -v du &> /dev/null; then
        size=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        verbose_log "Source directory size: $size"
        echo "$size"
    else
        echo "unknown"
    fi
}

# Function to count files
count_files() {
    verbose_log "Counting files in source directory..."
    
    local count
    count=$(find "$SOURCE_DIR" -type f | wc -l | tr -d ' ')
    verbose_log "File count: $count files"
    echo "$count"
}

# Function to create backup directory
create_backup_directory() {
    if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$BACKUP_BASE_DIR/$BACKUP_NAME"
    fi
    
    verbose_log "Creating backup directory: $TARGET_DIR"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create directory: $TARGET_DIR"
        return
    fi
    
    mkdir -p "$TARGET_DIR"
    echo "$TARGET_DIR"
}

# Function to build rsync exclude patterns
build_exclude_patterns() {
    local exclude_args=""
    
    if [[ "$EXCLUDE_CACHE" == "true" ]]; then
        exclude_args="$exclude_args --exclude='.cache/' --exclude='cache/' --exclude='*.cache'"
        exclude_args="$exclude_args --exclude='thumbs/' --exclude='thumbnails/'"
        exclude_args="$exclude_args --exclude='.tmp/' --exclude='tmp/' --exclude='*.tmp'"
    fi
    
    # Always exclude system files
    exclude_args="$exclude_args --exclude='.DS_Store' --exclude='Thumbs.db'"
    exclude_args="$exclude_args --exclude='.git/' --exclude='.svn/'"
    
    echo "$exclude_args"
}

# Function to backup files using rsync
backup_files_rsync() {
    local target_dir="$1"
    local files_target="$target_dir/files"
    local exclude_patterns
    exclude_patterns=$(build_exclude_patterns)
    
    verbose_log "Using rsync for file backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would run rsync command:"
        echo "  rsync -av $exclude_patterns \"$SOURCE_DIR/\" \"$files_target/\""
        return
    fi
    
    # Create files subdirectory
    mkdir -p "$files_target"
    
    # Run rsync with archive mode and exclusions
    eval "rsync -av --progress $exclude_patterns \"$SOURCE_DIR/\" \"$files_target/\""
    
    verbose_log "Rsync backup completed"
}

# Function to backup files using cp (fallback)
backup_files_cp() {
    local target_dir="$1"
    local files_target="$target_dir/files"
    
    verbose_log "Using cp for file backup (rsync not available)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would run cp command:"
        echo "  cp -r \"$SOURCE_DIR\" \"$files_target\""
        return
    fi
    
    # Create files subdirectory
    mkdir -p "$files_target"
    
    # Copy files recursively
    cp -r "$SOURCE_DIR/"* "$files_target/" 2>/dev/null || true
    
    # Remove cache files if excluding cache
    if [[ "$EXCLUDE_CACHE" == "true" ]]; then
        find "$files_target" -name ".cache" -type d -exec rm -rf {} + 2>/dev/null || true
        find "$files_target" -name "cache" -type d -exec rm -rf {} + 2>/dev/null || true
        find "$files_target" -name "*.cache" -type f -delete 2>/dev/null || true
        find "$files_target" -name "thumbs" -type d -exec rm -rf {} + 2>/dev/null || true
        find "$files_target" -name "thumbnails" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
    
    # Remove system files
    find "$files_target" -name ".DS_Store" -delete 2>/dev/null || true
    find "$files_target" -name "Thumbs.db" -delete 2>/dev/null || true
    
    verbose_log "Copy backup completed"
}

# Function to create backup metadata
create_backup_metadata() {
    local target_dir="$1"
    local metadata_file="$target_dir/backup-metadata.json"
    local source_size
    local file_count
    
    source_size=$(calculate_source_size)
    file_count=$(count_files)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create metadata file: $metadata_file"
        echo "  Source size: $source_size"
        echo "  File count: $file_count files"
        return
    fi
    
    cat > "$metadata_file" << EOF
{
    "backup_type": "files",
    "timestamp": "$TIMESTAMP",
    "source_directory": "$SOURCE_DIR",
    "backup_directory": "$target_dir",
    "source_size": "$source_size",
    "file_count": $file_count,
    "exclude_cache": $EXCLUDE_CACHE,
    "backup_method": "$(command -v rsync &> /dev/null && echo 'rsync' || echo 'cp')",
    "created_by": "backup-files.sh",
    "git_commit": "$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo 'unknown')"
}
EOF
    
    verbose_log "Backup metadata created: $metadata_file"
}

# Function to create backup summary
create_backup_summary() {
    local target_dir="$1"
    local summary_file="$target_dir/README.md"
    local source_size
    local file_count
    
    source_size=$(calculate_source_size)
    file_count=$(count_files)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: Would create backup summary: $summary_file"
        return
    fi
    
    cat > "$summary_file" << EOF
# File Backup: $BACKUP_NAME

Created on: $(date)
Source: $SOURCE_DIR
Size: $source_size ($file_count files)

## Files in this backup:

- \`files/\` - All uploaded files and assets from source directory
- \`backup-metadata.json\` - Backup metadata and information
- \`README.md\` - This summary file

## Restore Instructions:

1. Ensure target directory exists and is writable
2. Copy files back to desired location:

\`\`\`bash
# Restore to original location
cp -r files/* $SOURCE_DIR/

# Or restore to new location
cp -r files/* /path/to/new/uploads/
\`\`\`

## Backup Contents:

$(if [[ "$EXCLUDE_CACHE" == "true" ]]; then echo "- Cache files excluded"; else echo "- Cache files included"; fi)
- System files (.DS_Store, Thumbs.db) excluded
- Hidden directories (.git, .svn) excluded

## Verification:

To verify this backup:
- Check that the files/ directory contains expected content
- Compare file count with source directory
- Verify important files are present

Generated by: backup-files.sh
EOF
    
    verbose_log "Backup summary created: $summary_file"
}

# Main backup function
main() {
    log "Starting file backup: $BACKUP_NAME"
    
    check_prerequisites
    validate_source
    
    local source_size
    local file_count
    source_size=$(calculate_source_size)
    file_count=$(count_files)
    
    log "Source: $SOURCE_DIR ($source_size, $file_count files)"
    
    local target_dir
    target_dir=$(create_backup_directory)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Target: $target_dir"
        
        # Perform backup using rsync or cp
        if command -v rsync &> /dev/null; then
            backup_files_rsync "$target_dir"
        else
            backup_files_cp "$target_dir"
        fi
        
        create_backup_metadata "$target_dir"
        create_backup_summary "$target_dir"
        
        # Calculate backup size
        local backup_size
        backup_size=$(du -sh "$target_dir" 2>/dev/null | cut -f1 || echo "unknown")
        
        log "File backup completed successfully!"
        log "Backup location: $target_dir"
        log "Backup size: $backup_size"
    else
        log "DRY RUN completed - no actual backup created"
        log "Would backup $file_count files ($source_size) to: $target_dir"
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
        --include-cache)
            EXCLUDE_CACHE=false
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