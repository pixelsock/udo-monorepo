# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

This is a Directus backend for the Charlotte UDO (Unified Development Ordinance) project. It provides content management capabilities for legal documents with specialized extensions for DOCX processing, AI assistance, and search functionality.

## Quick Commands

### Development Setup
```bash
# Start local development stack (requires .env.local)
docker compose -f docker-compose.local.yml up -d

# Production stack (uses .env.production)
docker compose up -d

# Build all extensions before deployment
./scripts/build-extensions.sh

# Connect to production database
render psql dpg-d1gsdjjipnbc73b509f0-a
```

### Extension Development
```bash
# Build specific extension (from extension directory)
cd extensions/input-rich-text-html && npm run build

# Restart Directus to reload extensions (local dev)
docker compose -f docker-compose.local.yml restart directus

# Watch extension logs
docker logs directus-app-local -f
```

### Database Operations
```bash
# Apply Orama analytics tables in production
render psql dpg-d1gsdjjipnbc73b509f0-a < scripts/deployment/orama-analytics-tables.sql

# Create database dump
pg_dump > production-dump.sql
```

## Architecture Overview

### Core Components
- **Directus 11.10.2** - Headless CMS with PostgreSQL database
- **Custom Extensions** - Located in `/extensions/`
- **Docker Services** - Database (PostgreSQL), Cache (Redis), Directus app
- **Render.com Deployment** - Production hosting with automated builds

### Key Extensions
1. **`input-rich-text-html`** - Custom rich text editor with DOCX import
2. **`orama-search-bundle`** - Full-text search using Orama Cloud
3. **`ai-proxy-endpoint`** - AI assistance proxy for content editing
4. **`migration-bundle`** - Database migration tools
5. **`pdf-viewer-interface`** - PDF display interface
6. **`udo-theme`** - Charlotte UDO branding theme

### DOCX Processing Flow
```
DOCX File → JSZip → XML Parsing → HTML Conversion → Charlotte UDO Formatting → Rich Text Editor
```

Core files:
- `extensions/input-rich-text-html/src/docx-converter-clean.ts` - Main conversion logic
- `extensions/input-rich-text-html/src/useDocxImport.ts` - React integration

## Charlotte UDO Formatting Rules

These are critical for legal document compliance and are built into the DOCX converter:

### 1. Indentation System
- **40px increments**: 40px, 80px, 120px, 160px, 200px
- Applied via inline `padding-left` styles
- Corresponds to document hierarchy levels

### 2. List Formatting Patterns
- **Section Headers**: "A. General", "B. Definitions" - merged with content using `<br>`
- **Numbered Items**: "1. Purpose", "2. Standards" - 40px indentation
- **Lettered Items**: "a. Requirements", "b. Exceptions" - 80px indentation  
- **Roman Numerals**: "i. Details", "ii. Specifications" - 120px indentation
- **Parenthetical**: "(A) Notes", "(1) References" - 160px/200px indentation

### 3. Bold Formatting Rule
- **Only list markers are bold**, not the content after them
- Example: **A.** General requirements (not **A. General requirements**)

### 4. Content Merging
- Section headers merge with following content using `<br>` tags
- Prevents orphaned headers in legal documents

### 5. Post-Processing Chain
- Apply formatting rules in order during HTML generation
- Preserve table background colors and structure from Word
- Clean up and normalize HTML output for consistency

## Configuration Files

### Environment Files
- **`.env.local`** - Local development settings
- **`.env.production`** - Production deployment settings  
- **`.env.example`** - Template with required variables

Key variables:
```bash
DB_CLIENT=pg
DB_HOST=localhost  # or production host
SECRET=your_secret_key_minimum_32_characters
ADMIN_EMAIL=admin@example.com
EXTENSIONS_AUTO_RELOAD=true  # for development
```

### Docker Compose
- **`docker-compose.yml`** - Production configuration with external database
- **`docker-compose.local.yml`** - Local development with PostgreSQL/Redis containers

Local development uses port 8056, production uses 8055.

### Deployment Scripts
Located in `scripts/deployment/`:
- **`deploy-to-render.sh`** - Automated Render.com deployment
- **`build-extensions.sh`** - Build all extensions before deploy
- **`orama-analytics-tables.sql`** - Required database tables for search

## AI Assistant Integration

The AI proxy endpoint (`ai-proxy-endpoint`) provides:
- Persistent settings storage in Directus `settings` collection
- OpenRouter/OpenAI API integration
- Settings keys: `ai_assistant_provider`, `ai_assistant_api_key`, etc.

Test AI settings persistence:
```bash
node test-ai-settings.js
```

## Extension Development Workflow

1. **Create Extension**
   ```bash
   cd extensions
   # Follow Directus extension patterns from existing extensions
   ```

2. **Development**
   - Place TypeScript source in `src/`
   - Build with `npm run build`
   - Extension loads automatically with `EXTENSIONS_AUTO_RELOAD=true`

3. **Testing**
   - Test DOCX import in rich text editor
   - Check console for errors
   - Validate HTML output matches Charlotte UDO patterns

4. **Deployment**
   - Add extension to `scripts/build-extensions.sh`
   - Add to `Dockerfile` COPY instructions
   - Extensions must be pre-built for production deployment

## Troubleshooting

### Common Issues

**Extension not loading:**
```bash
# Check extension build
cd extensions/your-extension && npm run build

# Restart Directus
docker compose restart directus

# Check logs
docker logs directus-app-local -f
```

**DOCX import formatting issues:**
- Verify indentation rules in `docx-converter-clean.ts`
- Check post-processing chain execution order
- Test with sample Charlotte UDO document

**Production search not working:**
```bash
# Apply missing database tables
render psql dpg-d1gsdjjipnbc73b509f0-a < scripts/deployment/orama-analytics-tables.sql
```

**AI Assistant settings not persisting:**
- Check `settings` collection in database
- Verify API keys are stored with `ai_assistant_*` prefixes
- Test with `test-ai-settings.js`

### Database Connection
Production database requires SSL. Local development uses Docker PostgreSQL without SSL.

### Extension Hot Reload
Only works in local development with `EXTENSIONS_AUTO_RELOAD=true`. Production requires container rebuild.