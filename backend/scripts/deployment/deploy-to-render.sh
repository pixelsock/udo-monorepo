#!/bin/bash

# Deploy Orama Analytics Tables to Render Production
# This script uses Render's psql command to create the necessary tables

echo "========================================"
echo "Deploying Orama Analytics Tables to Render"
echo "========================================"
echo ""

# Check if render CLI is available
if ! command -v render &> /dev/null; then
    echo "❌ Render CLI not found. Please install it first:"
    echo "   brew install render"
    echo "   or visit: https://render.com/docs/cli"
    exit 1
fi

echo "📦 Deploying to database: dpg-d1gsdjjipnbc73b509f0-a"
echo ""

# Execute the SQL file using Render's psql
echo "Creating analytics tables..."
render psql dpg-d1gsdjjipnbc73b509f0-a < scripts/deployment/orama-analytics-tables.sql

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Success! Tables created."
    echo ""
    echo "Verifying installation..."
    
    # Verify tables were created
    echo "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'orama_%';" | render psql dpg-d1gsdjjipnbc73b509f0-a
    
    echo ""
    echo "========================================"
    echo "🎉 Deployment Complete!"
    echo "========================================"
    echo ""
    echo "The Orama search analytics tables are now deployed."
    echo "Search functionality should now work properly."
else
    echo "❌ Deployment failed. Please check the error messages above."
    exit 1
fi