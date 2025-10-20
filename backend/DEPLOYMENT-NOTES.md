# Deployment Notes

## AI Agent Extension Setup

The `directus-extension-ai-agent` is a third-party extension that requires manual setup in production:

### Installation Steps

1. Clone the extension into the extensions directory:
```bash
cd extensions
git clone https://github.com/cryptoraichu/directus-extension-ai-agent.git
```

2. Apply PostgreSQL compatibility fixes to `src/mcp-server/functions.js`:
   - Change `DATABASE()` to `CURRENT_SCHEMA()`
   - Change `INT AUTO_INCREMENT` to `SERIAL`
   - Change `INSERT IGNORE` to `INSERT ... ON CONFLICT ... DO NOTHING`
   - Change parameter placeholders from `?` to `$1, $2, $3...`
   - Change backticks to double quotes for reserved words (e.g., `"group"`)
   - Add `parseInt()` for count comparisons
   - Add field existence checking before insertion

3. Disable sandbox mode in `package.json`:
```json
"sandbox": {
  "enabled": false
}
```

4. Build the extension:
```bash
cd directus-extension-ai-agent
npm install
npm run build
```

5. Configure settings in database:
   - Update `ai_agent_settings` table with:
     - `directus_url`: Internal Directus URL
       * **Docker/Local**: `http://localhost:8055`
       * **Render Production**: `http://localhost:8055` (internal container access)
     - `admin_token`: Directus admin token (from environment variable)
     - `ai_model`: OpenAI model (e.g., `gpt-4o`)
     - `ai_api_key`: OpenAI API key (from environment variable)
     - `ai_base_url`: `https://api.openai.com/v1`

### Production Database Configuration

For Render.com deployment, run this SQL to set up the extension after deployment:

```sql
-- The table should be auto-created by the extension, but if needed:
-- Update settings with production values
UPDATE ai_agent_settings SET
  directus_url = 'http://localhost:8055',
  admin_token = 'YOUR_ADMIN_TOKEN',
  ai_model = 'gpt-4o',
  ai_api_key = 'YOUR_OPENAI_API_KEY',
  ai_base_url = 'https://api.openai.com/v1';
```

**Important**: Use `http://localhost:8055` for the Directus URL in production (not the public URL) because the MCP server runs in the same container as Directus and needs to access it via localhost.

### Production Considerations

- The extension uses MCP (Model Context Protocol) which spawns a Node.js process
- Ensure the Directus URL is accessible from within the container/server environment
- For containerized deployments, use internal service names or `localhost` instead of external URLs
- The extension requires an OpenAI API key to function

### PostgreSQL Fixes Applied

The original extension was designed for MySQL. Our fixes enable PostgreSQL compatibility:

1. **Schema Functions**: `DATABASE()` → `CURRENT_SCHEMA()`
2. **Auto-increment**: `INT AUTO_INCREMENT` → `SERIAL`
3. **Upserts**: `INSERT IGNORE` → `INSERT ... ON CONFLICT ... DO NOTHING`
4. **Parameter Binding**: `?` placeholders → `$1, $2, $3...`
5. **Identifiers**: Backticks → Double quotes for reserved words
6. **Type Handling**: Added `parseInt()` for numeric comparisons
7. **Result Format**: Handle both MySQL (`result[0]`) and PostgreSQL (`result.rows`) formats
