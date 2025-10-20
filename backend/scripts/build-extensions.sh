#!/bin/bash

# Build all Directus extensions
# Run this before committing to ensure all extensions are built

set -e

echo "🔨 Building Directus extensions..."
echo "================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXTENSIONS_DIR="$PROJECT_ROOT/extensions"

# List of extensions to build
EXTENSIONS=(
    "input-rich-text-html"
    "ai-proxy-endpoint"
    "migration-bundle"
    "orama-search-bundle"
    "pdf-viewer-interface"
    "udo-theme"
)

# Build each extension
for ext in "${EXTENSIONS[@]}"; do
    EXT_PATH="$EXTENSIONS_DIR/$ext"
    
    if [ -d "$EXT_PATH" ]; then
        echo ""
        echo "📦 Building $ext..."
        
        if [ -f "$EXT_PATH/package.json" ]; then
            cd "$EXT_PATH"
            
            # Install dependencies if node_modules doesn't exist
            if [ ! -d "node_modules" ]; then
                echo "  → Installing dependencies..."
                npm ci
            fi
            
            # Build the extension
            echo "  → Building..."
            npm run build
            
            if [ $? -eq 0 ]; then
                echo "  ✅ $ext built successfully"
            else
                echo "  ❌ Failed to build $ext"
                exit 1
            fi
        else
            echo "  ⚠️  No package.json found, skipping..."
        fi
    else
        echo "  ⚠️  Extension directory not found: $ext"
    fi
done

echo ""
echo "================================"
echo "✅ All extensions built successfully!"
echo ""
echo "📌 Next steps:"
echo "1. Test your changes locally"
echo "2. Commit and push to GitHub"
echo "3. Render will automatically rebuild and deploy"