#!/usr/bin/env node
/**
 * Backup Functionality Tests
 * Tests for database and file backup scripts
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
  console.log('Setting up test environment...');
  
  // Create test directories
  if (!fs.existsSync(TEST_DIR)) {
    fs.mkdirSync(TEST_DIR, { recursive: true });
  }
  
  // Create mock upload files for testing
  const testUploadsDir = path.join(TEST_DIR, 'uploads');
  if (!fs.existsSync(testUploadsDir)) {
    fs.mkdirSync(testUploadsDir, { recursive: true });
  }
  
  // Create test files
  fs.writeFileSync(path.join(testUploadsDir, 'test-image.jpg'), 'fake image data');
  fs.writeFileSync(path.join(testUploadsDir, 'test-document.pdf'), 'fake pdf data');
  
  console.log('Test environment ready');
}

/**
 * Test database backup functionality
 */
function testDatabaseBackup() {
  console.log('\n=== Testing Database Backup ===');
  
  try {
    // Test if backup script exists
    const backupScript = path.join(__dirname, '../deployment/backup-database.sh');
    if (!fs.existsSync(backupScript)) {
      throw new Error('Database backup script not found');
    }
    console.log('✓ Database backup script exists');
    
    // Test script permissions
    const stats = fs.statSync(backupScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Database backup script is not executable');
    }
    console.log('✓ Database backup script is executable');
    
    // Test dry-run functionality
    console.log('Testing dry-run mode...');
    const dryRunResult = execSync(`bash ${backupScript} --dry-run`, { encoding: 'utf8' });
    if (!dryRunResult.includes('DRY RUN')) {
      throw new Error('Dry-run mode not working properly');
    }
    console.log('✓ Dry-run mode working');
    
    console.log('Database backup tests passed');
    return true;
  } catch (error) {
    console.error('❌ Database backup test failed:', error.message);
    return false;
  }
}

/**
 * Test file backup functionality
 */
function testFileBackup() {
  console.log('\n=== Testing File Backup ===');
  
  try {
    // Test if backup script exists
    const backupScript = path.join(__dirname, '../deployment/backup-files.sh');
    if (!fs.existsSync(backupScript)) {
      throw new Error('File backup script not found');
    }
    console.log('✓ File backup script exists');
    
    // Test script permissions
    const stats = fs.statSync(backupScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('File backup script is not executable');
    }
    console.log('✓ File backup script is executable');
    
    // Test with test data
    console.log('Testing file backup with test data...');
    const testBackupDir = path.join(BACKUP_DIR, 'test-backup');
    const dryRunResult = execSync(`bash ${backupScript} --dry-run --source ${TEST_DIR}/uploads --target ${testBackupDir}`, { encoding: 'utf8' });
    if (!dryRunResult.includes('DRY RUN')) {
      throw new Error('File backup dry-run mode not working properly');
    }
    console.log('✓ File backup dry-run mode working');
    
    console.log('File backup tests passed');
    return true;
  } catch (error) {
    console.error('❌ File backup test failed:', error.message);
    return false;
  }
}

/**
 * Test backup verification functionality
 */
function testBackupVerification() {
  console.log('\n=== Testing Backup Verification ===');
  
  try {
    // Test if verification script exists
    const verifyScript = path.join(__dirname, '../deployment/verify-backup.sh');
    if (!fs.existsSync(verifyScript)) {
      throw new Error('Backup verification script not found');
    }
    console.log('✓ Backup verification script exists');
    
    // Test script permissions
    const stats = fs.statSync(verifyScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Backup verification script is not executable');
    }
    console.log('✓ Backup verification script is executable');
    
    console.log('Backup verification tests passed');
    return true;
  } catch (error) {
    console.error('❌ Backup verification test failed:', error.message);
    return false;
  }
}

/**
 * Test backup timestamp generation
 */
function testTimestampGeneration() {
  console.log('\n=== Testing Timestamp Generation ===');
  
  try {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$/.test(timestamp)) {
      throw new Error('Invalid timestamp format');
    }
    console.log('✓ Timestamp generation working:', timestamp);
    
    console.log('Timestamp generation tests passed');
    return true;
  } catch (error) {
    console.error('❌ Timestamp generation test failed:', error.message);
    return false;
  }
}

/**
 * Test cleanup
 */
function cleanupTest() {
  console.log('\nCleaning up test environment...');
  
  try {
    if (fs.existsSync(TEST_DIR)) {
      fs.rmSync(TEST_DIR, { recursive: true, force: true });
    }
    console.log('Test cleanup completed');
  } catch (error) {
    console.error('Warning: Test cleanup failed:', error.message);
  }
}

/**
 * Run all backup tests
 */
function runAllTests() {
  console.log('Starting Backup Functionality Tests\n');
  
  let passed = 0;
  let total = 0;
  
  setupTest();
  
  // Run individual tests
  const tests = [
    testTimestampGeneration,
    testDatabaseBackup,
    testFileBackup,
    testBackupVerification
  ];
  
  tests.forEach(test => {
    total++;
    if (test()) {
      passed++;
    }
  });
  
  cleanupTest();
  
  // Summary
  console.log('\n=== Test Summary ===');
  console.log(`Passed: ${passed}/${total}`);
  
  if (passed === total) {
    console.log('🎉 All backup tests passed!');
    process.exit(0);
  } else {
    console.log('❌ Some backup tests failed');
    process.exit(1);
  }
}

// Run tests if called directly
if (require.main === module) {
  runAllTests();
}

module.exports = {
  runAllTests,
  testDatabaseBackup,
  testFileBackup,
  testBackupVerification,
  testTimestampGeneration
};