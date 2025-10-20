#!/bin/bash

# Quick script to update the AI model in production
# Run with: ADMIN_PASSWORD=your-password ./scripts/update-production-model.sh

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ Please set ADMIN_PASSWORD environment variable"
  echo "Usage: ADMIN_PASSWORD=your-password ./scripts/update-production-model.sh"
  exit 1
fi

echo "🔄 Updating AI model in production..."
echo ""

# Run the Node.js script to update the model
ADMIN_PASSWORD=$ADMIN_PASSWORD node scripts/fix-ai-model.js

echo ""
echo "✅ Done! Next steps:"
echo "1. Clear your browser cache (Cmd+Shift+R or Ctrl+Shift+F5)"
echo "2. Reload the editor page at admin.charlotteudo.org"
echo "3. The console should now show: model: 'anthropic/claude-3.5-sonnet'"
echo ""
echo "If you don't have an OpenRouter API key yet:"
echo "1. Go to https://openrouter.ai/settings/keys"
echo "2. Create a new API key"
echo "3. Add credits ($5-10 to start)"
echo "4. Update the key in settings or run setup-ai-settings-production.js"