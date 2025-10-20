#!/usr/bin/env node

/**
 * Migrate Directus Schema via HTTP API
 * This is the most reliable method - uses Directus API instead of direct database access
 */

import { createDirectus, authentication, rest, schemaSnapshot, schemaDiff, schemaApply } from '@directus/sdk';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import * as readline from 'readline';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const LOCAL_URL = 'http://localhost:8056';
const LOCAL_EMAIL = 'nick@stump.works';
const LOCAL_PASSWORD = 'admin';

const PROD_URL = 'https://udo-backend-y1w0.onrender.com';
const PROD_EMAIL = 'nick@stump.works';
const PROD_PASSWORD = 'admin';

const isDryRun = process.argv.includes('--dry-run');
const isForce = process.argv.includes('--force');

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

async function main() {
  log('\n' + '='.repeat(60), 'magenta');
  log('DIRECTUS SCHEMA MIGRATION VIA API', 'magenta');
  log('Local → Production', 'magenta');
  log('='.repeat(60) + '\n', 'magenta');

  if (isDryRun) {
    log('🔍 DRY RUN MODE - No changes will be applied\n', 'yellow');
  }

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

    // Get local snapshot
    log('📸 Getting LOCAL schema snapshot...', 'cyan');
    const localSnapshot = await localClient.request(schemaSnapshot());
    log('✅ Local snapshot captured\n', 'green');

    // Save local snapshot for reference
    const snapshotDir = path.join(__dirname, '..', 'schema-snapshots');
    fs.mkdirSync(snapshotDir, { recursive: true });
    const localSnapshotPath = path.join(snapshotDir, `local-${Date.now()}.json`);
    fs.writeFileSync(localSnapshotPath, JSON.stringify(localSnapshot, null, 2));
    log(`📁 Saved to: ${localSnapshotPath}`, 'blue');

    // Get production snapshot (for comparison)
    log('\n📸 Getting PRODUCTION schema snapshot...', 'cyan');
    const prodSnapshot = await prodClient.request(schemaSnapshot());
    log('✅ Production snapshot captured\n', 'green');

    const prodSnapshotPath = path.join(snapshotDir, `production-${Date.now()}.json`);
    fs.writeFileSync(prodSnapshotPath, JSON.stringify(prodSnapshot, null, 2));
    log(`📁 Saved to: ${prodSnapshotPath}`, 'blue');

    // Generate diff
    log('\n🔍 Generating schema diff...', 'cyan');
    const diff = await prodClient.request(schemaDiff(localSnapshot));
    log('✅ Diff generated\n', 'green');

    // Check if there are changes
    if (!diff || !diff.diff || Object.keys(diff.diff).length === 0) {
      log('✨ No schema changes detected!\n', 'green');
      log('Production is already up to date.\n', 'cyan');
      return;
    }

    // Save diff
    const diffPath = path.join(snapshotDir, `diff-${Date.now()}.json`);
    fs.writeFileSync(diffPath, JSON.stringify(diff, null, 2));
    log(`📁 Diff saved to: ${diffPath}`, 'blue');

    // Analyze and display changes
    log('\n' + '='.repeat(60), 'cyan');
    log('SCHEMA CHANGES SUMMARY', 'cyan');
    log('='.repeat(60), 'cyan');

    const { collections, fields, relations } = diff.diff;

    // Count changes
    let totalChanges = 0;
    if (collections) totalChanges += collections.length || 0;
    if (fields) totalChanges += fields.length || 0;
    if (relations) totalChanges += relations.length || 0;

    log(`\nTotal changes: ${totalChanges}`, 'yellow');

    if (collections && collections.length > 0) {
      log('\n📦 Collection Changes:', 'yellow');
      collections.forEach(c => {
        if (c.diff && c.diff.length > 0) {
          log(`  ${c.collection}:`, 'blue');
          c.diff.forEach(d => {
            const kind = d.kind === 'N' ? '➕ New' : d.kind === 'D' ? '❌ Deleted' : '✏️  Modified';
            const color = d.kind === 'N' ? 'green' : d.kind === 'D' ? 'red' : 'blue';
            log(`    ${kind}: ${d.path ? d.path.join('.') : 'collection'}`, color);
          });
        }
      });
    }

    if (fields && fields.length > 0) {
      log('\n🏷  Field Changes:', 'yellow');
      fields.forEach(f => {
        if (f.diff && f.diff.length > 0) {
          log(`  ${f.collection}.${f.field}:`, 'blue');
          f.diff.forEach(d => {
            const kind = d.kind === 'N' ? '➕ New' : d.kind === 'D' ? '❌ Deleted' : '✏️  Modified';
            const color = d.kind === 'N' ? 'green' : d.kind === 'D' ? 'red' : 'blue';
            log(`    ${kind}: ${d.path ? d.path.join('.') : 'field'}`, color);
          });
        }
      });
    }

    if (relations && relations.length > 0) {
      log('\n🔗 Relation Changes:', 'yellow');
      relations.forEach(r => {
        if (r.diff && r.diff.length > 0) {
          log(`  ${r.collection}.${r.field}:`, 'blue');
          r.diff.forEach(d => {
            const kind = d.kind === 'N' ? '➕ New' : d.kind === 'D' ? '❌ Deleted' : '✏️  Modified';
            const color = d.kind === 'N' ? 'green' : d.kind === 'D' ? 'red' : 'blue';
            log(`    ${kind}: ${d.path ? d.path.join('.') : 'relation'}`, color);
          });
        }
      });
    }

    log('\n' + '='.repeat(60) + '\n', 'cyan');

    // Stop if dry run
    if (isDryRun) {
      log('🔍 DRY RUN COMPLETE', 'yellow');
      log('No changes were applied to production', 'blue');
      log('Run without --dry-run to apply these changes\n', 'blue');
      return;
    }

    // Confirm before applying
    if (!isForce) {
      log('⚠️  IMPORTANT SAFETY CHECKS:', 'yellow');
      log('   1. Have you backed up production? ✅', 'yellow');
      log('   2. Have you reviewed the changes above?', 'yellow');
      log('   3. Are you ready to proceed?\n', 'yellow');

      const answer = await askQuestion('Apply these changes to production? (yes/no): ');
      if (answer.toLowerCase() !== 'yes') {
        log('\n❌ Migration cancelled\n', 'yellow');
        return;
      }
    }

    // Apply changes
    log('\n🚀 Applying schema changes to production...', 'cyan');
    await prodClient.request(schemaApply(diff));
    log('✅ Schema migration completed successfully!\n', 'green');

    log('Next steps:', 'cyan');
    log('  1. Visit https://admin.charlotteudo.org', 'blue');
    log('  2. Go to Settings → Data Model', 'blue');
    log('  3. Verify all collections and fields', 'blue');
    log('  4. Test your application\n', 'blue');

  } catch (error) {
    log('\n❌ Migration failed!', 'red');
    log(`Error: ${error.message}`, 'red');
    if (error.errors) {
      log('\nDetails:', 'red');
      console.error(error.errors);
    }
    process.exit(1);
  }
}

main();
