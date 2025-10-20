# AI Assistant Settings Persistence

## Overview
The AI Assistant settings for the `input-rich-text-html` and `ai-proxy-endpoint` extensions are now persistently stored in the Directus `settings` collection. This ensures that AI configuration is shared across both extensions and persists between sessions.

## Changes Made

### 1. New Composable: `useAISettings.ts`
Created a new composable in `extensions/input-rich-text-html/src/composables/useAISettings.ts` that:
- Manages AI settings in the Directus `settings` collection
- Provides methods to load, save, and delete AI configuration
- Falls back to localStorage for backward compatibility

### 2. Updated `useAIAssistant.ts`
Modified to use the new `useAISettings` composable:
- `loadConfiguration()` now tries Directus settings first, then falls back to localStorage
- `saveConfiguration()` saves to both Directus settings and localStorage

### 3. Enhanced AI Proxy Endpoint
Updated `extensions/ai-proxy-endpoint/src/index.ts` with:
- Automatic loading of AI settings from the database when credentials aren't provided in requests
- New GET endpoint `/ai-proxy/settings` to retrieve current AI configuration
- New POST endpoint `/ai-proxy/settings` to update AI configuration
- Shared settings keys with the frontend extension

## Settings Structure

The following keys are used in the `settings` collection:

| Key | Description | Example Value |
|-----|-------------|---------------|
| `ai_assistant_provider` | AI provider (openai, openrouter, custom) | `openrouter` |
| `ai_assistant_base_url` | API base URL | `https://openrouter.ai/api/v1` |
| `ai_assistant_api_key` | API key (encrypted) | `sk-or-xxx...` |
| `ai_assistant_model` | Model to use | `openai/gpt-4` |
| `ai_assistant_temperature` | Temperature (0-2) | `0.7` |
| `ai_assistant_max_tokens` | Max tokens for responses | `2000` |
| `ai_assistant_system_prompt` | Custom system prompt | Optional custom prompt |

## Usage

### Frontend (Rich Text Editor)
When the AI Assistant modal is opened, it will:
1. Try to load settings from Directus `settings` collection
2. Fall back to localStorage if no settings found
3. Save new settings to both Directus and localStorage

### Backend (AI Proxy)
The proxy endpoint will:
1. Check if API credentials are provided in the request
2. If not, load credentials from the `settings` collection
3. Use the stored settings for API calls

### Testing
Run the test script to verify persistence:
```bash
node test-ai-settings.js
```

## Benefits

1. **Persistent Storage**: Settings survive browser cache clears and are stored in the database
2. **Shared Configuration**: Both extensions use the same settings
3. **Security**: API keys are stored server-side, not in browser localStorage
4. **User-Specific**: Settings can be made user-specific if needed (with proper permissions)
5. **Centralized Management**: Admins can manage AI settings through the Directus interface

## API Endpoints

### Get Current Settings
```http
GET /ai-proxy/settings
Authorization: Bearer {token}
```

### Update Settings
```http
POST /ai-proxy/settings
Authorization: Bearer {token}
Content-Type: application/json

{
  "provider": "openrouter",
  "baseUrl": "https://openrouter.ai/api/v1",
  "apiKey": "sk-or-xxx...",
  "model": "openai/gpt-4",
  "temperature": 0.7,
  "maxTokens": 2000
}
```

### Use AI Chat (with stored settings)
```http
POST /ai-proxy/chat
Authorization: Bearer {token}
Content-Type: application/json

{
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "stream": false
}
```

## Migration from localStorage

Existing settings in localStorage will continue to work as a fallback. To migrate:
1. The system will automatically use localStorage settings if no database settings exist
2. When users save their configuration again, it will be stored in both locations
3. Eventually, localStorage can be phased out

## Security Considerations

1. API keys are stored in the database with proper access controls
2. The GET endpoint masks API keys (shows only last 4 characters)
3. Settings require authentication to read/write
4. API keys are never sent to the frontend in full