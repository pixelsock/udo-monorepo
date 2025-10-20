#!/usr/bin/env node

/**
 * Script to manually create AI settings in the Directus settings collection
 * This ensures the settings exist even if the UI isn't saving them properly
 */

const fetch = require('node-fetch');

// Configuration - update these as needed
const DIRECTUS_URL = process.env.DIRECTUS_URL || 'http://localhost:8056';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'nick@stump.works';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin';

// Default AI configuration - using OpenRouter as it's more reliable
const DEFAULT_AI_CONFIG = {
  provider: 'openrouter',
  baseUrl: 'https://openrouter.ai/api/v1',
  apiKey: process.env.OPENROUTER_API_KEY || '', // Set this in environment
  model: 'anthropic/claude-3.5-sonnet', // More reliable than free models
  temperature: 0.7,
  maxTokens: 2000
};

// Settings keys
const AI_SETTINGS_KEYS = {
  provider: 'ai_assistant_provider',
  baseUrl: 'ai_assistant_base_url',
  apiKey: 'ai_assistant_api_key',
  model: 'ai_assistant_model',
  temperature: 'ai_assistant_temperature',
  maxTokens: 'ai_assistant_max_tokens'
};

async function getAuthToken() {
  console.log('🔐 Authenticating with Directus...');
  const response = await fetch(`${DIRECTUS_URL}/auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email: ADMIN_EMAIL,
      password: ADMIN_PASSWORD,
    }),
  });

  if (!response.ok) {
    throw new Error(`Authentication failed: ${response.statusText}`);
  }

  const data = await response.json();
  return data.data.access_token;
}

async function checkExistingSettings(token) {
  console.log('\n🔍 Checking existing AI settings...');
  
  const response = await fetch(`${DIRECTUS_URL}/items/settings?filter[key][_in]=${Object.values(AI_SETTINGS_KEYS).join(',')}`, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    console.log('⚠️  Could not fetch existing settings');
    return [];
  }

  const result = await response.json();
  return result.data || [];
}

async function createOrUpdateSetting(token, key, value, description) {
  // Check if setting exists
  const checkResponse = await fetch(`${DIRECTUS_URL}/items/settings?filter[key][_eq]=${key}`, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });

  const existing = await checkResponse.json();
  
  if (existing.data && existing.data.length > 0) {
    // Update existing
    console.log(`  📝 Updating: ${key}`);
    const updateResponse = await fetch(`${DIRECTUS_URL}/items/settings/${existing.data[0].id}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify({
        value: value,
        description: description
      }),
    });
    
    if (!updateResponse.ok) {
      const error = await updateResponse.text();
      throw new Error(`Failed to update ${key}: ${error}`);
    }
  } else {
    // Create new
    console.log(`  ➕ Creating: ${key}`);
    const createResponse = await fetch(`${DIRECTUS_URL}/items/settings`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify({
        key: key,
        value: value,
        description: description
      }),
    });
    
    if (!createResponse.ok) {
      const error = await createResponse.text();
      throw new Error(`Failed to create ${key}: ${error}`);
    }
  }
}

async function setupAISettings() {
  console.log('🚀 Setting up AI Assistant Settings\n');
  console.log('================================');
  console.log(`Server: ${DIRECTUS_URL}`);
  console.log(`User: ${ADMIN_EMAIL}`);
  console.log('================================\n');
  
  try {
    // Get authentication token
    const token = await getAuthToken();
    console.log('✅ Authentication successful');
    
    // Check existing settings
    const existing = await checkExistingSettings(token);
    console.log(`Found ${existing.length} existing AI settings`);
    
    // Create/update each setting
    console.log('\n📝 Creating/updating AI settings...\n');
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.provider,
      DEFAULT_AI_CONFIG.provider,
      'AI Assistant provider (openai, openrouter, custom)'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.baseUrl,
      DEFAULT_AI_CONFIG.baseUrl,
      'AI Assistant API base URL'
    );
    
    if (DEFAULT_AI_CONFIG.apiKey) {
      await createOrUpdateSetting(
        token,
        AI_SETTINGS_KEYS.apiKey,
        DEFAULT_AI_CONFIG.apiKey,
        'AI Assistant API key (encrypted)'
      );
    } else {
      console.log('  ⚠️  Skipping API key (not provided)');
    }
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.model,
      DEFAULT_AI_CONFIG.model,
      'AI model to use for text generation'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.temperature,
      DEFAULT_AI_CONFIG.temperature.toString(),
      'AI model temperature (0-2)'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.maxTokens,
      DEFAULT_AI_CONFIG.maxTokens.toString(),
      'Maximum tokens for AI responses'
    );
    
    // Verify settings were created
    console.log('\n✅ Verifying settings...\n');
    const finalCheck = await checkExistingSettings(token);
    
    console.log(`Successfully configured ${finalCheck.length} AI settings:`);
    finalCheck.forEach(setting => {
      const value = setting.key === AI_SETTINGS_KEYS.apiKey 
        ? '***' + (setting.value ? setting.value.slice(-4) : 'NOT_SET')
        : setting.value;
      console.log(`  ✓ ${setting.key}: ${value}`);
    });
    
    console.log('\n================================');
    console.log('✅ AI settings successfully configured!');
    console.log('\n📌 Next steps:');
    console.log('1. If you need to set an API key:');
    console.log('   OPENROUTER_API_KEY=your-key node scripts/setup-ai-settings.js');
    console.log('2. Or update the API key in Directus Admin > Settings');
    console.log('3. Test the AI Assistant in the rich text editor');
    
    if (!DEFAULT_AI_CONFIG.apiKey) {
      console.log('\n⚠️  WARNING: No API key was set. The AI Assistant won\'t work until you add one.');
    }
    
  } catch (error) {
    console.error('\n❌ Setup failed:', error.message);
    process.exit(1);
  }
}

// Run the setup
setupAISettings().catch(console.error);