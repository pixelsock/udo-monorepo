#!/bin/bash

# Quick script to add OpenRouter API key to production
# Run with: ADMIN_PASSWORD=your-password OPENROUTER_API_KEY=your-key ./scripts/quick-fix-api-key.sh

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ Please set ADMIN_PASSWORD environment variable"
  echo "Usage: ADMIN_PASSWORD=your-password OPENROUTER_API_KEY=your-key ./scripts/quick-fix-api-key.sh"
  exit 1
fi

if [ -z "$OPENROUTER_API_KEY" ]; then
  echo "❌ Please set OPENROUTER_API_KEY environment variable"
  echo ""
  echo "To get an API key:"
  echo "1. Go to https://openrouter.ai/settings/keys"
  echo "2. Create a new API key"
  echo "3. Add credits (\$5-10 to start)"
  echo ""
  exit 1
fi

echo "🔄 Adding OpenRouter API key to production..."
echo ""

# Run the Node.js script to add the API key
cat > /tmp/add-api-key.js << 'EOF'
const fetch = require('node-fetch');

const DIRECTUS_URL = 'https://admin.charlotteudo.org';
const ADMIN_EMAIL = 'nick@stump.works';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;

async function addApiKey() {
  try {
    // Login
    const loginRes = await fetch(`${DIRECTUS_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD })
    });
    
    if (!loginRes.ok) throw new Error('Login failed');
    const { data: { access_token } } = await loginRes.json();
    
    // Check if API key setting exists
    const checkRes = await fetch(`${DIRECTUS_URL}/items/settings?filter[key][_eq]=ai_assistant_api_key`, {
      headers: { 'Authorization': `Bearer ${access_token}` }
    });
    
    const settings = await checkRes.json();
    
    if (settings.data && settings.data.length > 0) {
      // Update existing
      const current = settings.data[0];
      console.log(`Current API key: ***${current.value ? current.value.slice(-4) : 'NONE'}`);
      
      const updateRes = await fetch(`${DIRECTUS_URL}/items/settings/${current.id}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${access_token}`
        },
        body: JSON.stringify({ value: OPENROUTER_API_KEY })
      });
      
      if (!updateRes.ok) throw new Error('Update failed');
      console.log(`✅ API key updated: ***${OPENROUTER_API_KEY.slice(-4)}`);
    } else {
      // Create new
      const createRes = await fetch(`${DIRECTUS_URL}/items/settings`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${access_token}`
        },
        body: JSON.stringify({
          key: 'ai_assistant_api_key',
          value: OPENROUTER_API_KEY,
          description: 'OpenRouter API key for AI Assistant'
        })
      });
      
      if (!createRes.ok) throw new Error('Create failed');
      console.log(`✅ API key setting created: ***${OPENROUTER_API_KEY.slice(-4)}`);
    }
    
    console.log('\n📌 Next steps:');
    console.log('1. Clear your browser cache (Cmd+Shift+R)');
    console.log('2. Reload the editor at admin.charlotteudo.org');
    console.log('3. The AI Assistant should now work with your API key');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

addApiKey();
EOF

ADMIN_PASSWORD=$ADMIN_PASSWORD OPENROUTER_API_KEY=$OPENROUTER_API_KEY node /tmp/add-api-key.js
rm /tmp/add-api-key.js

echo ""
echo "✅ Done! The API key has been added to production."
echo ""
echo "The free model 'qwen/qwen3-coder:free' will now work with your API key."
echo "Your rate limits will be tracked per your account instead of globally."