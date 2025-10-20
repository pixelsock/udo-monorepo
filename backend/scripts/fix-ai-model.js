#!/usr/bin/env node

/**
 * Quick fix to update AI model in production
 */

const fetch = require('node-fetch');

const DIRECTUS_URL = 'https://admin.charlotteudo.org';
const ADMIN_EMAIL = 'nick@stump.works';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

// Recommended models (in order of preference)
const MODELS = {
  CLAUDE: 'anthropic/claude-3.5-sonnet',           // Best quality, requires credits
  GPT4: 'openai/gpt-4-turbo-preview',             // Very good, requires credits  
  GPT35: 'openai/gpt-3.5-turbo',                  // Good, cheaper
  GEMINI: 'google/gemini-2.0-flash-exp:free',     // Free but may rate limit
  LLAMA: 'meta-llama/llama-3.2-11b-vision-instruct:free', // Free but may rate limit
};

const TARGET_MODEL = MODELS.CLAUDE; // Change this to your preferred model

if (!ADMIN_PASSWORD) {
  console.error('❌ Please run with: ADMIN_PASSWORD=your-password node scripts/fix-ai-model.js');
  process.exit(1);
}

async function fixModel() {
  try {
    // Login
    const loginRes = await fetch(`${DIRECTUS_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD })
    });
    
    if (!loginRes.ok) throw new Error('Login failed');
    const { data: { access_token } } = await loginRes.json();
    
    // Check current model
    const checkRes = await fetch(`${DIRECTUS_URL}/items/settings?filter[key][_eq]=ai_assistant_model`, {
      headers: { 'Authorization': `Bearer ${access_token}` }
    });
    
    const settings = await checkRes.json();
    
    if (settings.data && settings.data.length > 0) {
      const current = settings.data[0];
      console.log(`Current model: ${current.value}`);
      
      if (current.value === TARGET_MODEL) {
        console.log('✅ Model is already correct!');
        return;
      }
      
      // Update model
      const updateRes = await fetch(`${DIRECTUS_URL}/items/settings/${current.id}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${access_token}`
        },
        body: JSON.stringify({ value: TARGET_MODEL })
      });
      
      if (!updateRes.ok) throw new Error('Update failed');
      console.log(`✅ Model updated to: ${TARGET_MODEL}`);
    } else {
      // Create model setting
      const createRes = await fetch(`${DIRECTUS_URL}/items/settings`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${access_token}`
        },
        body: JSON.stringify({
          key: 'ai_assistant_model',
          value: TARGET_MODEL,
          description: 'AI model to use for text generation'
        })
      });
      
      if (!createRes.ok) throw new Error('Create failed');
      console.log(`✅ Model setting created: ${TARGET_MODEL}`);
    }
    
    console.log('\n📌 Next: Clear your browser cache and reload the editor');
    console.log('The new model will be loaded when the component mounts.');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

fixModel();