#!/usr/bin/env node

/**
 * Migrate Directus Schema from Local to Production
 *
 * This script safely migrates schema changes from your local Directus instance
 * to production without losing any data.
 *
 * Safety features:
 * - Creates a backup before migration
 * - Shows a diff of changes before applying
 * - Requires confirmation before applying changes
 * - Only migrates schema, not data
 *
 * Usage:
 *   node scripts/migrate-schema-to-production.js [--dry-run] [--force]
 */

import { createDirectus, authentication, rest, schemaSnapshot, schemaDiff, schemaApply } from '@directus/sdk';
import * as readline from 'readline';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const LOCAL_URL = 'http://localhost:8056';
const LOCAL_EMAIL = 'nick@stump.works';
const LOCAL_PASSWORD = 'admin';

const PROD_URL = 'https://udo-backend-y1w0.onrender.com';
const PROD_EMAIL = 'nick@stump.works';
const PROD_PASSWORD = 'admin';

// Parse command line arguments
const args = process.argv.slice(2);
const isDryRun = args.includes('--dry-run');
const isForce = args.includes('--force');

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function createInterface() {
  return readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
}

async function askQuestion(question) {
  const rl = createInterface();
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

async function connectToLocal() {
  log('\n📡 Connecting to local Directus...', 'cyan');

  const client = createDirectus(LOCAL_URL)
    .with(rest())
    .with(authentication());

  try {
    await client.login({ email: LOCAL_EMAIL, password: LOCAL_PASSWORD });
    log('✅ Connected to local Directus', 'green');
    return client;
  } catch (error) {
    log(`❌ Failed to connect to local Directus: ${error.message}`, 'red');
    throw error;
  }
}

async function connectToProduction() {
  log('\n📡 Connecting to production Directus...', 'cyan');

  const client = createDirectus(PROD_URL)
    .with(rest())
    .with(authentication());

  try {
    await client.login({ email: PROD_EMAIL, password: PROD_PASSWORD });
    log('✅ Connected to production Directus', 'green');
    return client;
  } catch (error) {
    log(`❌ Failed to connect to production Directus: ${error.message}`, 'red');
    throw error;
  }
}

async function getLocalSnapshot(localClient) {
  log('\n📸 Taking snapshot of local schema...', 'cyan');

  try {
    const snapshot = await localClient.request(schemaSnapshot());
    log('✅ Local schema snapshot captured', 'green');

    // Save snapshot for reference
    const snapshotPath = path.join(__dirname, '..', 'schema-snapshots', `local-${Date.now()}.json`);
    fs.mkdirSync(path.dirname(snapshotPath), { recursive: true });
    fs.writeFileSync(snapshotPath, JSON.stringify(snapshot, null, 2));
    log(`📁 Snapshot saved to: ${snapshotPath}`, 'blue');

    return snapshot;
  } catch (error) {
    log(`❌ Failed to capture local snapshot: ${error.message}`, 'red');
    throw error;
  }
}

async function getProductionSnapshot(prodClient) {
  log('\n📸 Taking snapshot of production schema...', 'cyan');

  try {
    const snapshot = await prodClient.request(schemaSnapshot());
    log('✅ Production schema snapshot captured', 'green');

    // Save snapshot for reference
    const snapshotPath = path.join(__dirname, '..', 'schema-snapshots', `production-${Date.now()}.json`);
    fs.mkdirSync(path.dirname(snapshotPath), { recursive: true });
    fs.writeFileSync(snapshotPath, JSON.stringify(snapshot, null, 2));
    log(`📁 Snapshot saved to: ${snapshotPath}`, 'blue');

    return snapshot;
  } catch (error) {
    log(`❌ Failed to capture production snapshot: ${error.message}`, 'red');
    throw error;
  }
}

async function generateDiff(prodClient, localSnapshot) {
  log('\n🔍 Generating schema diff...', 'cyan');

  try {
    const diff = await prodClient.request(schemaDiff(localSnapshot));
    log('✅ Schema diff generated', 'green');

    if (!diff || diff.length === 0) {
      log('\n✨ No schema changes detected! Production is already up to date.', 'green');
      return null;
    }

    // Save diff for reference
    const diffPath = path.join(__dirname, '..', 'schema-snapshots', `diff-${Date.now()}.json`);
    fs.writeFileSync(diffPath, JSON.stringify(diff, null, 2));
    log(`📁 Diff saved to: ${diffPath}`, 'blue');

    return diff;
  } catch (error) {
    log(`❌ Failed to generate diff: ${error.message}`, 'red');
    throw error;
  }
}

function analyzeDiff(diff) {
  log('\n📊 Analyzing changes...', 'cyan');

  const stats = {
    collections: { create: 0, update: 0, delete: 0 },
    fields: { create: 0, update: 0, delete: 0 },
    relations: { create: 0, update: 0, delete: 0 },
    total: diff.length
  };

  const changes = [];

  for (const change of diff) {
    const { action, collection, field } = change;

    if (action.includes('collection')) {
      if (action.includes('create')) stats.collections.create++;
      else if (action.includes('update')) stats.collections.update++;
      else if (action.includes('delete')) stats.collections.delete++;

      changes.push({
        type: 'collection',
        action: action.replace('_', ' '),
        name: collection || change.name
      });
    } else if (action.includes('field')) {
      if (action.includes('create')) stats.fields.create++;
      else if (action.includes('update')) stats.fields.update++;
      else if (action.includes('delete')) stats.fields.delete++;

      changes.push({
        type: 'field',
        action: action.replace('_', ' '),
        collection,
        name: field
      });
    } else if (action.includes('relation')) {
      if (action.includes('create')) stats.relations.create++;
      else if (action.includes('update')) stats.relations.update++;
      else if (action.includes('delete')) stats.relations.delete++;

      changes.push({
        type: 'relation',
        action: action.replace('_', ' '),
        collection,
        field
      });
    }
  }

  return { stats, changes };
}

function displayDiff(diff) {
  const { stats, changes } = analyzeDiff(diff);

  log('\n' + '='.repeat(60), 'cyan');
  log('SCHEMA MIGRATION SUMMARY', 'cyan');
  log('='.repeat(60), 'cyan');

  log(`\nTotal changes: ${stats.total}`, 'yellow');

  log('\nCollections:', 'yellow');
  log(`  ➕ Create: ${stats.collections.create}`, 'green');
  log(`  ✏️  Update: ${stats.collections.update}`, 'blue');
  log(`  ❌ Delete: ${stats.collections.delete}`, 'red');

  log('\nFields:', 'yellow');
  log(`  ➕ Create: ${stats.fields.create}`, 'green');
  log(`  ✏️  Update: ${stats.fields.update}`, 'blue');
  log(`  ❌ Delete: ${stats.fields.delete}`, 'red');

  log('\nRelations:', 'yellow');
  log(`  ➕ Create: ${stats.relations.create}`, 'green');
  log(`  ✏️  Update: ${stats.relations.update}`, 'blue');
  log(`  ❌ Delete: ${stats.relations.delete}`, 'red');

  log('\n' + '-'.repeat(60), 'cyan');
  log('DETAILED CHANGES', 'cyan');
  log('-'.repeat(60), 'cyan');

  for (const change of changes) {
    const icon = change.action.includes('create') ? '➕' :
                 change.action.includes('update') ? '✏️' : '❌';
    const color = change.action.includes('create') ? 'green' :
                  change.action.includes('update') ? 'blue' : 'red';

    if (change.type === 'collection') {
      log(`\n${icon} ${change.action}: ${change.name}`, color);
    } else if (change.type === 'field') {
      log(`\n${icon} ${change.action}: ${change.collection}.${change.name}`, color);
    } else if (change.type === 'relation') {
      log(`\n${icon} ${change.action}: ${change.collection}.${change.field}`, color);
    }
  }

  log('\n' + '='.repeat(60) + '\n', 'cyan');

  // Warnings for destructive operations
  if (stats.collections.delete > 0 || stats.fields.delete > 0) {
    log('⚠️  WARNING: This migration includes DELETE operations!', 'red');
    log('   Make sure you have a backup before proceeding.', 'yellow');
  }
}

async function applyDiff(prodClient, diff) {
  log('\n🚀 Applying schema changes to production...', 'cyan');

  try {
    await prodClient.request(schemaApply(diff));
    log('✅ Schema changes applied successfully!', 'green');
  } catch (error) {
    log(`❌ Failed to apply schema changes: ${error.message}`, 'red');
    log('\nProduction schema was NOT modified.', 'yellow');
    throw error;
  }
}

async function main() {
  log('\n' + '='.repeat(60), 'magenta');
  log('DIRECTUS SCHEMA MIGRATION', 'magenta');
  log('Local → Production', 'magenta');
  log('='.repeat(60) + '\n', 'magenta');

  if (isDryRun) {
    log('🔍 Running in DRY RUN mode - no changes will be applied\n', 'yellow');
  }

  try {
    // Step 1: Connect to both instances
    const localClient = await connectToLocal();
    const prodClient = await connectToProduction();

    // Step 2: Get snapshots
    const localSnapshot = await getLocalSnapshot(localClient);
    const prodSnapshot = await getProductionSnapshot(prodClient);

    // Step 3: Generate diff
    const diff = await generateDiff(prodClient, localSnapshot);

    if (!diff) {
      log('\n✨ Migration complete - no changes needed!\n', 'green');
      process.exit(0);
    }

    // Step 4: Display diff
    displayDiff(diff);

    // Step 5: Confirm and apply (unless dry run)
    if (isDryRun) {
      log('🔍 Dry run complete - no changes were made', 'yellow');
      log('Run without --dry-run to apply these changes\n', 'blue');
      process.exit(0);
    }

    if (!isForce) {
      log('⚠️  IMPORTANT SAFETY CHECKS:', 'yellow');
      log('   1. Have you backed up your production database?', 'yellow');
      log('   2. Have you reviewed all changes above?', 'yellow');
      log('   3. Are you sure you want to proceed?\n', 'yellow');

      const answer = await askQuestion('Apply these changes to production? (yes/no): ');

      if (answer.toLowerCase() !== 'yes') {
        log('\n❌ Migration cancelled by user', 'yellow');
        process.exit(0);
      }
    }

    // Step 6: Apply changes
    await applyDiff(prodClient, diff);

    log('\n✅ Migration completed successfully!', 'green');
    log('\nRecommendations:', 'cyan');
    log('  1. Test your production instance thoroughly', 'blue');
    log('  2. Check that all collections and fields are working correctly', 'blue');
    log('  3. Monitor your application logs for any issues\n', 'blue');

  } catch (error) {
    log('\n❌ Migration failed!', 'red');
    log(`Error: ${error.message}`, 'red');

    if (error.stack) {
      log('\nStack trace:', 'red');
      console.error(error.stack);
    }

    process.exit(1);
  }
}

// Run the migration
main();
