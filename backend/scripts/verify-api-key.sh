#!/bin/bash

# Quick script to verify API key is working in production
# Run with: ADMIN_PASSWORD=your-password ./scripts/verify-api-key.sh

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ Please set ADMIN_PASSWORD environment variable"
  echo "Usage: ADMIN_PASSWORD=your-password ./scripts/verify-api-key.sh"
  exit 1
fi

echo "🔍 Verifying API key in production..."
echo ""

cat > /tmp/verify-api-key.js << 'EOF'
const fetch = require('node-fetch');

const DIRECTUS_URL = 'https://admin.charlotteudo.org';
const ADMIN_EMAIL = 'nick@stump.works';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

async function verify() {
  try {
    // Login
    const loginRes = await fetch(`${DIRECTUS_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD })
    });
    
    if (!loginRes.ok) throw new Error('Login failed');
    const { data: { access_token } } = await loginRes.json();
    
    // Check API key
    const checkRes = await fetch(`${DIRECTUS_URL}/items/settings?filter[key][_eq]=ai_assistant_api_key`, {
      headers: { 'Authorization': `Bearer ${access_token}` }
    });
    
    const settings = await checkRes.json();
    
    if (settings.data && settings.data.length > 0) {
      const apiKey = settings.data[0].value;
      console.log(`✅ API key found: ***${apiKey ? apiKey.slice(-4) : 'EMPTY'}`);
      
      // Test the API key with a simple call
      console.log('\n🤖 Testing AI call with stored settings...\n');
      
      const testRes = await fetch(`${DIRECTUS_URL}/ai-proxy/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${access_token}`
        },
        body: JSON.stringify({
          messages: [
            { role: 'system', content: 'Reply with one word only.' },
            { role: 'user', content: 'Say "Working"' }
          ],
          stream: false
        })
      });
      
      if (testRes.ok) {
        const result = await testRes.json();
        console.log('✅ AI Assistant is working!');
        console.log('Response:', result.choices?.[0]?.message?.content);
      } else {
        const error = await testRes.text();
        console.log('❌ AI call failed:', error.substring(0, 200));
        
        // Parse error for more details
        try {
          const errorObj = JSON.parse(error);
          if (errorObj.error?.message?.includes('429')) {
            console.log('\n⚠️  Still getting rate limited. Possible issues:');
            console.log('1. API key might be invalid');
            console.log('2. API key has no credits');
            console.log('3. Browser might be caching old settings');
            console.log('\nTry: Clear browser cache (Cmd+Shift+R) and reload');
          }
        } catch (e) {}
      }
    } else {
      console.log('❌ No API key found in settings!');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

verify();
EOF

ADMIN_PASSWORD=$ADMIN_PASSWORD node /tmp/verify-api-key.js
rm /tmp/verify-api-key.js

echo ""
echo "================================"
echo "If the test succeeded, your API key is working!"
echo "If not, try clearing your browser cache and reloading."