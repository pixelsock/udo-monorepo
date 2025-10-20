#!/bin/bash

# Copy and paste this command in your terminal to fix the Orama search tables:

echo "Please run this command in your terminal:"
echo ""
echo "render psql dpg-d1gsdjjipnbc73b509f0-a < scripts/deployment/orama-analytics-tables.sql"
echo ""
echo "Or if you're in a different directory:"
echo ""
echo "cd ~/Sites/charlotteUDO/directus/backend && render psql dpg-d1gsdjjipnbc73b509f0-a < scripts/deployment/orama-analytics-tables.sql"
echo ""
echo "This will create the 4 missing Orama analytics tables in production."