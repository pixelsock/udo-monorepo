# Charlotte UDO Directus Backend - Cline Rules

## Project Structure Overview

This is a Directus backend for the Charlotte UDO (Unified Development Ordinance) project. The backend provides content management capabilities for legal documents, with specialized extensions for document processing and search functionality.

### Key Components

1. **Extensions Directory** (`/extensions/`)
   - `input-rich-text-html/` - Custom rich text editor with DOCX import capabilities
   - `orama-search-bundle/` - Search functionality using Orama
   - `migration-bundle/` - Database migration tools

2. **DOCX Converter** (`extensions/input-rich-text-html/src/docx-converter-clean.ts`)
   - Converts DOCX files to HTML with Charlotte UDO-specific formatting
   - Handles complex indentation patterns (40px, 80px, 120px, 160px, 200px increments)
   - Processes section headers (A., B., C.) and numbered items (1., 2., 3.)
   - Merges related content using `<br>` tags for proper formatting

3. **Configuration Files**
   - `docker-compose.yml` - Main Docker configuration
   - `docker-compose.local.yml` - Local development overrides
   - `.env.local` - Local environment variables
   - `.env.production` - Production environment variables

### Charlotte UDO Formatting Patterns

The DOCX converter is specifically tuned for Charlotte UDO document patterns:

- **Section Headers**: "A. General", "B. Definitions" - merged with following content using `<br>`
- **Numbered Items**: "1. Purpose", "2. Standards" - with proper indentation
- **Lettered Items**: "a. Requirements", "b. Exceptions" - 80px indentation
- **Roman Numerals**: "i. Details", "ii. Specifications" - 120px indentation
- **Parenthetical**: "(A) Notes", "(1) References" - 160px and 200px indentation

### Development Notes

- Uses TypeScript for type safety
- Directus extensions follow the standard extension API
- DOCX processing uses JSZip and @xmldom/xmldom for XML parsing
- Indentation is handled via inline `padding-left` styles for editor compatibility
- Post-processing rules clean up and merge content for proper UDO formatting

### Important Files to Monitor

- `extensions/input-rich-text-html/src/docx-converter-clean.ts` - Main DOCX conversion logic
- `extensions/input-rich-text-html/src/useDocxImport.ts` - React hook for DOCX import
- `docker-compose.yml` - Container orchestration
- `.env.local` - Local environment configuration

### Deployment

- Uses Docker containers for consistent deployment
- Render.com for production hosting
- Automated deployment scripts in `/scripts/deployment/`

### Key Patterns for Future Development

1. **Indentation Logic**: Always use 40px increments (40, 80, 120, 160, 200)
2. **Content Merging**: Section headers should merge with following content using `<br>` tags
3. **Bold Formatting**: Only list markers should be bold, not the content after them
4. **Table Processing**: Preserve background colors and structure from Word documents
5. **Post-Processing**: Apply rules in order to clean up and normalize HTML output

This project requires careful attention to document formatting accuracy for legal compliance.
