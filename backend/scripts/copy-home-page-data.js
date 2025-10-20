#!/usr/bin/env node

/**
 * Copy home_page data from local to production
 */

import { createDirectus, authentication, rest, readItems, createItems } from '@directus/sdk';

const LOCAL_URL = 'http://localhost:8056';
const LOCAL_EMAIL = 'nick@stump.works';
const LOCAL_PASSWORD = 'admin';

const PROD_URL = 'https://udo-backend-y1w0.onrender.com';
const PROD_EMAIL = 'nick@stump.works';
const PROD_PASSWORD = 'admin';

// Colors
const c = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m'
};

function log(msg, color = 'reset') {
  console.log(`${c[color]}${msg}${c.reset}`);
}

async function main() {
  log('\n' + '='.repeat(60), 'magenta');
  log('COPY HOME_PAGE DATA', 'magenta');
  log('Local → Production', 'magenta');
  log('='.repeat(60) + '\n', 'magenta');

  try {
    // Connect to local
    log('📡 Connecting to LOCAL Directus...', 'cyan');
    const localClient = createDirectus(LOCAL_URL).with(rest()).with(authentication());
    await localClient.login({ email: LOCAL_EMAIL, password: LOCAL_PASSWORD });
    log('✅ Connected to local\n', 'green');

    // Connect to production
    log('📡 Connecting to PRODUCTION Directus...', 'cyan');
    const prodClient = createDirectus(PROD_URL).with(rest()).with(authentication());
    await prodClient.login({ email: PROD_EMAIL, password: PROD_PASSWORD });
    log('✅ Connected to production\n', 'green');

    // Read home_page data from local
    log('📖 Reading home_page data from local...', 'cyan');
    const localData = await localClient.request(
      readItems('home_page', {
        fields: ['*']
      })
    );

    if (!localData) {
      log('⚠️  No home_page data found in local database', 'yellow');
      log('Nothing to copy!\n', 'yellow');
      return;
    }

    log('✅ Found home_page data in local\n', 'green');

    // Display what will be copied
    log('Data to copy:', 'cyan');
    console.log(JSON.stringify(localData, null, 2));
    console.log('');

    // Check if production already has data
    log('📖 Checking production home_page...', 'cyan');
    let prodData;
    try {
      prodData = await prodClient.request(
        readItems('home_page', {
          fields: ['id']
        })
      );
    } catch (error) {
      // Collection might be empty, that's fine
      prodData = null;
    }

    if (prodData) {
      log('⚠️  WARNING: Production already has home_page data!', 'yellow');
      log('This will overwrite existing data.\n', 'yellow');
    }

    // Copy data to production (remove id to let it auto-generate)
    log('🚀 Copying data to production...', 'cyan');
    const { id, ...dataToCreate } = localData; // Remove id

    const created = await prodClient.request(
      createItems('home_page', dataToCreate)
    );

    log('✅ Data copied successfully!\n', 'green');
    log('Created 1 item in production', 'green');

    log('\nNext steps:', 'cyan');
    log('  1. Visit https://admin.charlotteudo.org', 'blue');
    log('  2. Go to Content → Home Page', 'blue');
    log('  3. Verify the data was copied correctly\n', 'blue');

  } catch (error) {
    log('\n❌ Copy failed!', 'red');
    log(`Error: ${error.message}`, 'red');
    if (error.errors) {
      log('\nDetails:', 'red');
      console.error(error.errors);
    }
    process.exit(1);
  }
}

main();
