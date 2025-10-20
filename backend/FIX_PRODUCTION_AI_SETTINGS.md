# Fixing Production AI Settings

## The Issues

1. **Rate Limiting**: The free model `qwen/qwen3-coder:free` is being rate-limited
2. **No Settings Saved**: AI settings aren't appearing in the settings collection

## Solutions

### 1. Manual Configuration (Immediate Fix)

Run this command locally to configure production settings:

```bash
# Set your OpenRouter API key and Directus admin password
DIRECTUS_ADMIN_PASSWORD=your-admin-password \
OPENROUTER_API_KEY=your-openrouter-key \
node scripts/setup-ai-settings-production.js
```

This will:
- Create all necessary AI settings in the production database
- Set the model to `anthropic/claude-3.5-sonnet` (reliable paid model)
- Configure the OpenRouter API endpoint

### 2. Get an OpenRouter API Key

1. Go to https://openrouter.ai/
2. Sign up/login
3. Go to https://openrouter.ai/settings/keys
4. Create a new API key
5. Add credits to your account (start with $5-10)

### 3. Alternative Free Models

If you want to use free models (less reliable), change the model in settings to:
- `openai/gpt-3.5-turbo` - More reliable free option
- `meta-llama/llama-3.2-11b-vision-instruct:free` - Free but may rate limit
- `google/gemini-2.0-flash-exp:free` - Google's free model

### 4. Verify Settings in Production

After running the setup script, verify at:
https://admin.charlotteudo.org

1. Login as admin
2. Go to Settings (gear icon)
3. Search for "ai_assistant"
4. You should see 6 settings:
   - ai_assistant_provider
   - ai_assistant_base_url
   - ai_assistant_api_key
   - ai_assistant_model
   - ai_assistant_temperature
   - ai_assistant_max_tokens

### 5. Test the AI Assistant

1. Edit any article with rich text content
2. Select some text
3. Click the AI Assistant button (robot icon)
4. Try a command like "Make this more concise"

## Why Settings Weren't Saving

The issue appears to be that:
1. The extensions ARE deployed (dist files are there)
2. The settings collection EXISTS
3. But the UI save might have permission issues or the API endpoint isn't creating settings properly

The manual script bypasses these issues by directly creating the settings via the Directus API.

## Troubleshooting

### Check if extensions are working:
```bash
node test-production-settings.js
```

### Check settings directly:
```bash
curl https://admin.charlotteudo.org/items/settings?filter[key][_starts_with]=ai_assistant \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### If AI still doesn't work:

1. **Check API Key**: Make sure your OpenRouter API key is valid and has credits
2. **Check Model**: Ensure the model name is correct (check OpenRouter docs)
3. **Check Endpoint**: The endpoint should be working at `/ai-proxy/chat`
4. **Check Console**: Browser console will show specific errors

## Long-term Fix

The settings persistence from the UI needs investigation. Possible causes:
- Permission issues with the settings collection
- The Vue component not properly calling the save function
- CORS or authentication issues

For now, use the manual configuration script to set up AI settings.