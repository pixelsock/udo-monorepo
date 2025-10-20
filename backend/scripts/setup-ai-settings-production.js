#!/usr/bin/env node

/**
 * Script to setup AI settings in production
 * Run this after deployment to ensure AI settings are properly configured
 */

const fetch = require('node-fetch');

// Production configuration
const DIRECTUS_URL = 'https://admin.charlotteudo.org';
const ADMIN_EMAIL = process.env.DIRECTUS_ADMIN_EMAIL || 'nick@stump.works';
const ADMIN_PASSWORD = process.env.DIRECTUS_ADMIN_PASSWORD;
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;

if (!ADMIN_PASSWORD) {
  console.error('❌ Please provide DIRECTUS_ADMIN_PASSWORD environment variable');
  process.exit(1);
}

if (!OPENROUTER_API_KEY) {
  console.warn('⚠️  No OPENROUTER_API_KEY provided. You\'ll need to set it manually in Directus.');
}

// AI configuration for production
const AI_CONFIG = {
  provider: 'openrouter',
  baseUrl: 'https://openrouter.ai/api/v1',
  apiKey: OPENROUTER_API_KEY || 'YOUR_API_KEY_HERE',
  model: 'anthropic/claude-3.5-sonnet', // Reliable model
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
  console.log('🔐 Authenticating with production Directus...');
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
    const error = await response.text();
    throw new Error(`Authentication failed: ${error}`);
  }

  const data = await response.json();
  return data.data.access_token;
}

async function createOrUpdateSetting(token, key, value, description) {
  // Check if setting exists
  const checkResponse = await fetch(`${DIRECTUS_URL}/items/settings?filter[key][_eq]=${key}`, {
    method: 'GET',
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });

  if (!checkResponse.ok) {
    console.log(`⚠️  Could not check setting ${key}`);
    return;
  }

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
      console.error(`  ❌ Failed to update ${key}: ${error}`);
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
      console.error(`  ❌ Failed to create ${key}: ${error}`);
    }
  }
}

async function setupProductionAISettings() {
  console.log('🚀 Setting up AI Assistant Settings in PRODUCTION\n');
  console.log('================================');
  console.log(`Server: ${DIRECTUS_URL}`);
  console.log(`User: ${ADMIN_EMAIL}`);
  console.log(`API Key: ${OPENROUTER_API_KEY ? '***' + OPENROUTER_API_KEY.slice(-4) : 'NOT PROVIDED'}`);
  console.log('================================\n');
  
  try {
    // Get authentication token
    const token = await getAuthToken();
    console.log('✅ Authentication successful');
    
    // Create/update each setting
    console.log('\n📝 Creating/updating AI settings...\n');
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.provider,
      AI_CONFIG.provider,
      'AI Assistant provider (openai, openrouter, custom)'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.baseUrl,
      AI_CONFIG.baseUrl,
      'AI Assistant API base URL'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.apiKey,
      AI_CONFIG.apiKey,
      'AI Assistant API key (encrypted)'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.model,
      AI_CONFIG.model,
      'AI model to use for text generation'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.temperature,
      AI_CONFIG.temperature.toString(),
      'AI model temperature (0-2)'
    );
    
    await createOrUpdateSetting(
      token,
      AI_SETTINGS_KEYS.maxTokens,
      AI_CONFIG.maxTokens.toString(),
      'Maximum tokens for AI responses'
    );
    
    // Verify settings
    console.log('\n✅ Verifying settings...\n');
    
    const verifyResponse = await fetch(`${DIRECTUS_URL}/items/settings?filter[key][_starts_with]=ai_assistant`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${token}`,
      },
    });
    
    if (verifyResponse.ok) {
      const result = await verifyResponse.json();
      console.log(`Successfully configured ${result.data.length} AI settings:`);
      result.data.forEach(setting => {
        const value = setting.key === AI_SETTINGS_KEYS.apiKey 
          ? '***' + (setting.value ? setting.value.slice(-4) : '')
          : setting.value;
        console.log(`  ✓ ${setting.key}: ${value}`);
      });
    }
    
    console.log('\n================================');
    console.log('✅ Production AI settings configured!');
    console.log('\n📌 Important Notes:');
    console.log('1. Model is set to: anthropic/claude-3.5-sonnet (reliable paid model)');
    console.log('2. For free models, change to: openai/gpt-3.5-turbo');
    console.log('3. Make sure your OpenRouter account has credits');
    console.log('4. Test in the rich text editor at admin.charlotteudo.org');
    
  } catch (error) {
    console.error('\n❌ Setup failed:', error.message);
    process.exit(1);
  }
}

// Run the setup
setupProductionAISettings().catch(console.error);