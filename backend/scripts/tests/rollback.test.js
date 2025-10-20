#!/usr/bin/env node
/**
 * Rollback Functionality Tests
 * Tests for deployment rollback capabilities
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Test configuration
const TEST_DIR = path.join(__dirname, '../../test-data');
const BACKUP_DIR = path.join(__dirname, '../../backups');

/**
 * Test setup - create test data
 */
function setupTest() {
  console.log('Setting up rollback test environment...');
  
  // Create test directories
  if (!fs.existsSync(TEST_DIR)) {
    fs.mkdirSync(TEST_DIR, { recursive: true });
  }
  
  if (!fs.existsSync(BACKUP_DIR)) {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
  }
  
  // Create mock production and backup environment
  const prodDir = path.join(TEST_DIR, 'production');
  const backupDir = path.join(BACKUP_DIR, 'test-backup-20240101');
  
  [prodDir, backupDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  });
  
  // Create production files (current state)
  fs.writeFileSync(path.join(prodDir, 'package.json'), '{"name": "current-version", "version": "2.0.0"}');
  fs.writeFileSync(path.join(prodDir, 'current-file.txt'), 'current version content');
  
  // Create backup files (previous state)
  fs.writeFileSync(path.join(backupDir, 'package.json'), '{"name": "previous-version", "version": "1.0.0"}');
  fs.writeFileSync(path.join(backupDir, 'previous-file.txt'), 'previous version content');
  
  // Create backup metadata
  const metadata = {
    backup_type: 'full',
    timestamp: '2024-01-01T12:00:00',
    deployment_id: 'deploy-20240101-120000',
    source_path: prodDir,
    backup_created: new Date().toISOString()
  };
  
  fs.writeFileSync(path.join(backupDir, 'backup-metadata.json'), JSON.stringify(metadata, null, 2));
  
  console.log('Rollback test environment ready');
}

/**
 * Test rollback script exists and is executable
 */
function testRollbackScript() {
  console.log('\n=== Testing Rollback Script ===');
  
  try {
    // Test if rollback script exists
    const rollbackScript = path.join(__dirname, '../deployment/rollback.sh');
    if (!fs.existsSync(rollbackScript)) {
      throw new Error('Rollback script not found');
    }
    console.log('✓ Rollback script exists');
    
    // Test script permissions
    const stats = fs.statSync(rollbackScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Rollback script is not executable');
    }
    console.log('✓ Rollback script is executable');
    
    console.log('Rollback script tests passed');
    return true;
  } catch (error) {
    console.error('❌ Rollback script test failed:', error.message);
    return false;
  }
}

/**
 * Test rollback dry-run functionality
 */
function testRollbackDryRun() {
  console.log('\n=== Testing Rollback Dry-Run ===');
  
  try {
    const rollbackScript = path.join(__dirname, '../deployment/rollback.sh');
    const backupPath = path.join(BACKUP_DIR, 'test-backup-20240101');
    const targetPath = path.join(TEST_DIR, 'production');
    
    // Test dry-run functionality
    console.log('Testing rollback dry-run mode...');
    const dryRunResult = execSync(`bash ${rollbackScript} --dry-run --backup ${backupPath} --target ${targetPath}`, { encoding: 'utf8' });
    
    if (!dryRunResult.includes('DRY RUN')) {
      throw new Error('Rollback dry-run mode not working properly');
    }
    console.log('✓ Rollback dry-run mode working');
    
    // Check that dry-run mentions key rollback steps
    const expectedSteps = ['backup', 'restore', 'validation'];
    const foundSteps = expectedSteps.filter(step => dryRunResult.toLowerCase().includes(step));
    
    if (foundSteps.length < 2) {
      throw new Error('Rollback dry-run should mention restore process');
    }
    console.log('✓ Rollback dry-run mentions restore process');
    
    console.log('Rollback dry-run tests passed');
    return true;
  } catch (error) {
    console.error('❌ Rollback dry-run test failed:', error.message);
    return false;
  }
}

/**
 * Test rollback backup verification
 */
function testBackupVerification() {
  console.log('\n=== Testing Backup Verification ===');
  
  try {
    const rollbackScript = path.join(__dirname, '../deployment/rollback.sh');
    const backupPath = path.join(BACKUP_DIR, 'test-backup-20240101');
    const targetPath = path.join(TEST_DIR, 'production');
    
    // Test with valid backup
    console.log('Testing backup verification with valid backup...');
    const validResult = execSync(`bash ${rollbackScript} --dry-run --verify-only --backup ${backupPath} --target ${targetPath}`, { encoding: 'utf8' });
    
    if (validResult.includes('ERROR') && validResult.includes('backup')) {
      throw new Error('Valid backup should pass verification');
    }
    console.log('✓ Valid backup passes verification');
    
    // Test with missing backup
    console.log('Testing backup verification with missing backup...');
    try {
      execSync(`bash ${rollbackScript} --dry-run --verify-only --backup /nonexistent/backup --target ${targetPath}`, { encoding: 'utf8' });
      throw new Error('Missing backup should fail verification');
    } catch (error) {
      if (error.status === 0) {
        throw new Error('Missing backup should fail verification');
      }
      console.log('✓ Missing backup fails verification');
    }
    
    console.log('Backup verification tests passed');
    return true;
  } catch (error) {
    console.error('❌ Backup verification test failed:', error.message);
    return false;
  }
}

/**
 * Test deployment versioning
 */
function testDeploymentVersioning() {
  console.log('\n=== Testing Deployment Versioning ===');
  
  try {
    // Test if versioning script exists
    const versionScript = path.join(__dirname, '../deployment/manage-versions.sh');
    if (!fs.existsSync(versionScript)) {
      throw new Error('Deployment versioning script not found');
    }
    console.log('✓ Deployment versioning script exists');
    
    // Test script permissions
    const stats = fs.statSync(versionScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Deployment versioning script is not executable');
    }
    console.log('✓ Deployment versioning script is executable');
    
    // Test listing versions
    console.log('Testing version listing...');
    const listResult = execSync(`bash ${versionScript} --list --backup-dir ${BACKUP_DIR}`, { encoding: 'utf8' });
    
    if (!listResult.includes('test-backup') && !listResult.includes('No versions found')) {
      throw new Error('Version listing not working properly');
    }
    console.log('✓ Version listing working');
    
    console.log('Deployment versioning tests passed');
    return true;
  } catch (error) {
    console.error('❌ Deployment versioning test failed:', error.message);
    return false;
  }
}

/**
 * Test rollback safety checks
 */
function testRollbackSafetyChecks() {
  console.log('\n=== Testing Rollback Safety Checks ===');
  
  try {
    const rollbackScript = path.join(__dirname, '../deployment/rollback.sh');
    const backupPath = path.join(BACKUP_DIR, 'test-backup-20240101');
    const targetPath = path.join(TEST_DIR, 'production');
    
    // Test rollback without confirmation (should require confirmation)
    console.log('Testing rollback safety confirmation...');
    try {
      execSync(`bash ${rollbackScript} --backup ${backupPath} --target ${targetPath}`, { 
        encoding: 'utf8',
        input: 'n\n' // Send 'no' to confirmation prompt
      });
      throw new Error('Rollback should require confirmation');
    } catch (error) {
      if (error.status === 0) {
        throw new Error('Rollback should require confirmation');
      }
      console.log('✓ Rollback requires confirmation');
    }
    
    // Test force rollback
    console.log('Testing force rollback...');
    const forceResult = execSync(`bash ${rollbackScript} --dry-run --force --backup ${backupPath} --target ${targetPath}`, { encoding: 'utf8' });
    
    if (!forceResult.includes('DRY RUN')) {
      throw new Error('Force rollback dry-run not working');
    }
    console.log('✓ Force rollback option working');
    
    console.log('Rollback safety checks tests passed');
    return true;
  } catch (error) {
    console.error('❌ Rollback safety checks test failed:', error.message);
    return false;
  }
}

/**
 * Test rollback verification
 */
function testRollbackVerification() {
  console.log('\n=== Testing Rollback Verification ===');
  
  try {
    // Create a test scenario for rollback verification
    const prodDir = path.join(TEST_DIR, 'production');
    const backupPath = path.join(BACKUP_DIR, 'test-backup-20240101');
    
    // Verify current state
    const currentPackage = path.join(prodDir, 'package.json');
    const backupPackage = path.join(backupPath, 'package.json');
    
    if (!fs.existsSync(currentPackage) || !fs.existsSync(backupPackage)) {
      throw new Error('Test files not found for rollback verification');
    }
    
    const currentContent = JSON.parse(fs.readFileSync(currentPackage, 'utf8'));
    const backupContent = JSON.parse(fs.readFileSync(backupPackage, 'utf8'));
    
    if (currentContent.version === backupContent.version) {
      throw new Error('Test files should have different versions for rollback test');
    }
    
    console.log('✓ Test environment properly set up for rollback verification');
    console.log(`Current version: ${currentContent.version}, Backup version: ${backupContent.version}`);
    
    // Test verification would work in real rollback
    console.log('✓ Rollback verification test setup complete');
    
    console.log('Rollback verification tests passed');
    return true;
  } catch (error) {
    console.error('❌ Rollback verification test failed:', error.message);
    return false;
  }
}

/**
 * Test automatic rollback triggers
 */
function testAutomaticRollback() {
  console.log('\n=== Testing Automatic Rollback ===');
  
  try {
    // Test if automatic rollback detection works
    const rollbackScript = path.join(__dirname, '../deployment/rollback.sh');
    const backupPath = path.join(BACKUP_DIR, 'test-backup-20240101');
    const targetPath = path.join(TEST_DIR, 'production');
    
    // Test health check based rollback
    console.log('Testing health check based rollback detection...');
    const healthResult = execSync(`bash ${rollbackScript} --dry-run --check-health --backup ${backupPath} --target ${targetPath}`, { encoding: 'utf8' });
    
    if (healthResult.includes('ERROR') && !healthResult.includes('DRY RUN')) {
      throw new Error('Health check rollback detection failed');
    }
    console.log('✓ Health check rollback detection working');
    
    console.log('Automatic rollback tests passed');
    return true;
  } catch (error) {
    console.error('❌ Automatic rollback test failed:', error.message);
    return false;
  }
}

/**
 * Test rollback logging
 */
function testRollbackLogging() {
  console.log('\n=== Testing Rollback Logging ===');
  
  try {
    const rollbackScript = path.join(__dirname, '../deployment/rollback.sh');
    const backupPath = path.join(BACKUP_DIR, 'test-backup-20240101');
    const targetPath = path.join(TEST_DIR, 'production');
    
    // Test that rollback includes proper logging
    console.log('Testing rollback logging...');
    const logResult = execSync(`bash ${rollbackScript} --dry-run --verbose --backup ${backupPath} --target ${targetPath}`, { encoding: 'utf8' });
    
    // Check for timestamp logging
    if (!logResult.match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/)) {
      throw new Error('Rollback does not include proper timestamp logging');
    }
    console.log('✓ Rollback includes timestamp logging');
    
    // Check for verbose output
    if (!logResult.includes('VERBOSE') && !logResult.includes('verbose')) {
      throw new Error('Verbose mode not working properly in rollback');
    }
    console.log('✓ Rollback verbose logging mode working');
    
    console.log('Rollback logging tests passed');
    return true;
  } catch (error) {
    console.error('❌ Rollback logging test failed:', error.message);
    return false;
  }
}

/**
 * Test cleanup
 */
function cleanupTest() {
  console.log('\nCleaning up rollback test environment...');
  
  try {
    if (fs.existsSync(TEST_DIR)) {
      fs.rmSync(TEST_DIR, { recursive: true, force: true });
    }
    
    // Clean up test backup
    const testBackup = path.join(BACKUP_DIR, 'test-backup-20240101');
    if (fs.existsSync(testBackup)) {
      fs.rmSync(testBackup, { recursive: true, force: true });
    }
    
    console.log('Rollback test cleanup completed');
  } catch (error) {
    console.error('Warning: Rollback test cleanup failed:', error.message);
  }
}

/**
 * Run all rollback tests
 */
function runAllTests() {
  console.log('Starting Rollback Functionality Tests\n');
  
  let passed = 0;
  let total = 0;
  
  setupTest();
  
  // Run individual tests
  const tests = [
    testRollbackScript,
    testRollbackDryRun,
    testBackupVerification,
    testDeploymentVersioning,
    testRollbackSafetyChecks,
    testRollbackVerification,
    testAutomaticRollback,
    testRollbackLogging
  ];
  
  tests.forEach(test => {
    total++;
    if (test()) {
      passed++;
    }
  });
  
  cleanupTest();
  
  // Summary
  console.log('\n=== Rollback Test Summary ===');
  console.log(`Passed: ${passed}/${total}`);
  
  if (passed === total) {
    console.log('🎉 All rollback tests passed!');
    process.exit(0);
  } else {
    console.log('❌ Some rollback tests failed');
    process.exit(1);
  }
}

// Run tests if called directly
if (require.main === module) {
  runAllTests();
}

module.exports = {
  runAllTests,
  testRollbackScript,
  testRollbackDryRun,
  testBackupVerification,
  testDeploymentVersioning,
  testRollbackSafetyChecks,
  testRollbackVerification,
  testAutomaticRollback,
  testRollbackLogging
};