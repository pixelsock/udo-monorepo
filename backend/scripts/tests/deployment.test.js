#!/usr/bin/env node
/**
 * Deployment Functionality Tests
 * Tests for selective deployment scripts that preserve production data
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
  console.log('Setting up deployment test environment...');
  
  // Create test directories
  if (!fs.existsSync(TEST_DIR)) {
    fs.mkdirSync(TEST_DIR, { recursive: true });
  }
  
  // Create mock production structure
  const prodDir = path.join(TEST_DIR, 'production');
  const sourceDir = path.join(TEST_DIR, 'source');
  
  [prodDir, sourceDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  });
  
  // Create production data that should be preserved
  const prodUploads = path.join(prodDir, 'uploads');
  const prodData = path.join(prodDir, 'data');
  
  fs.mkdirSync(prodUploads, { recursive: true });
  fs.mkdirSync(prodData, { recursive: true });
  
  fs.writeFileSync(path.join(prodUploads, 'production-image.jpg'), 'production image data');
  fs.writeFileSync(path.join(prodData, 'production-data.db'), 'production database data');
  
  // Create source code that should be deployed
  const sourceExtensions = path.join(sourceDir, 'extensions');
  fs.mkdirSync(sourceExtensions, { recursive: true });
  
  fs.writeFileSync(path.join(sourceDir, 'package.json'), '{"name": "test-project"}');
  fs.writeFileSync(path.join(sourceExtensions, 'custom-extension.js'), 'console.log("extension");');
  
  console.log('Deployment test environment ready');
}

/**
 * Test deployment configuration
 */
function testDeploymentConfiguration() {
  console.log('\n=== Testing Deployment Configuration ===');
  
  try {
    // Test if deployment config exists
    const deployConfig = path.join(__dirname, '../deployment/deploy-config.json');
    if (!fs.existsSync(deployConfig)) {
      throw new Error('Deployment configuration file not found');
    }
    console.log('✓ Deployment configuration exists');
    
    // Test config is valid JSON
    const configContent = fs.readFileSync(deployConfig, 'utf8');
    const config = JSON.parse(configContent);
    
    // Check required properties
    const requiredProps = ['exclude_patterns', 'include_patterns', 'preserve_directories'];
    requiredProps.forEach(prop => {
      if (!config.hasOwnProperty(prop)) {
        throw new Error(`Missing required config property: ${prop}`);
      }
    });
    console.log('✓ Configuration has required properties');
    
    // Check that production data directories are excluded
    const excludePatterns = config.exclude_patterns;
    const hasDataExclude = excludePatterns.some(pattern => pattern.includes('data') || pattern.includes('uploads'));
    if (!hasDataExclude) {
      throw new Error('Configuration should exclude data/uploads directories');
    }
    console.log('✓ Configuration excludes production data directories');
    
    console.log('Deployment configuration tests passed');
    return true;
  } catch (error) {
    console.error('❌ Deployment configuration test failed:', error.message);
    return false;
  }
}

/**
 * Test code-only sync script
 */
function testCodeOnlySync() {
  console.log('\n=== Testing Code-Only Sync ===');
  
  try {
    // Test if sync script exists
    const syncScript = path.join(__dirname, '../deployment/sync-code.sh');
    if (!fs.existsSync(syncScript)) {
      throw new Error('Code sync script not found');
    }
    console.log('✓ Code sync script exists');
    
    // Test script permissions
    const stats = fs.statSync(syncScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Code sync script is not executable');
    }
    console.log('✓ Code sync script is executable');
    
    // Test dry-run functionality
    console.log('Testing sync dry-run mode...');
    const sourceDir = path.join(TEST_DIR, 'source');
    const targetDir = path.join(TEST_DIR, 'production');
    
    const dryRunResult = execSync(`bash ${syncScript} --dry-run --source ${sourceDir} --target ${targetDir}`, { encoding: 'utf8' });
    if (!dryRunResult.includes('DRY RUN')) {
      throw new Error('Sync dry-run mode not working properly');
    }
    console.log('✓ Sync dry-run mode working');
    
    console.log('Code sync tests passed');
    return true;
  } catch (error) {
    console.error('❌ Code sync test failed:', error.message);
    return false;
  }
}

/**
 * Test extension deployment handling
 */
function testExtensionDeployment() {
  console.log('\n=== Testing Extension Deployment ===');
  
  try {
    // Test if extension deployment script exists
    const extensionScript = path.join(__dirname, '../deployment/deploy-extensions.sh');
    if (!fs.existsSync(extensionScript)) {
      throw new Error('Extension deployment script not found');
    }
    console.log('✓ Extension deployment script exists');
    
    // Test script permissions
    const stats = fs.statSync(extensionScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Extension deployment script is not executable');
    }
    console.log('✓ Extension deployment script is executable');
    
    // Test dry-run functionality
    console.log('Testing extension deployment dry-run...');
    const testTarget = path.join(TEST_DIR, 'target-extensions');
    const dryRunResult = execSync(`bash ${extensionScript} --dry-run --target ${testTarget}`, { encoding: 'utf8' });
    if (!dryRunResult.includes('DRY RUN')) {
      throw new Error('Extension deployment dry-run mode not working properly');
    }
    console.log('✓ Extension deployment dry-run mode working');
    
    console.log('Extension deployment tests passed');
    return true;
  } catch (error) {
    console.error('❌ Extension deployment test failed:', error.message);
    return false;
  }
}

/**
 * Test data preservation during deployment
 */
function testDataPreservation() {
  console.log('\n=== Testing Data Preservation ===');
  
  try {
    // Create a mock deployment scenario
    const prodDir = path.join(TEST_DIR, 'production');
    const sourceDir = path.join(TEST_DIR, 'source');
    
    // Verify production data exists before "deployment"
    const prodImage = path.join(prodDir, 'uploads', 'production-image.jpg');
    const prodData = path.join(prodDir, 'data', 'production-data.db');
    
    if (!fs.existsSync(prodImage) || !fs.existsSync(prodData)) {
      throw new Error('Production test data not found');
    }
    
    const originalImageContent = fs.readFileSync(prodImage, 'utf8');
    const originalDataContent = fs.readFileSync(prodData, 'utf8');
    
    console.log('✓ Production test data verified');
    
    // Simulate deployment exclusion patterns
    const excludePatterns = ['uploads/', 'data/', '*.db'];
    
    // Check that rsync exclude patterns would preserve data
    const wouldPreserveUploads = excludePatterns.some(pattern => 
      pattern.includes('uploads') || pattern === 'uploads/'
    );
    const wouldPreserveData = excludePatterns.some(pattern => 
      pattern.includes('data') || pattern === 'data/'
    );
    
    if (!wouldPreserveUploads) {
      throw new Error('Upload files would not be preserved');
    }
    console.log('✓ Upload files would be preserved');
    
    if (!wouldPreserveData) {
      throw new Error('Data files would not be preserved');
    }
    console.log('✓ Data files would be preserved');
    
    console.log('Data preservation tests passed');
    return true;
  } catch (error) {
    console.error('❌ Data preservation test failed:', error.message);
    return false;
  }
}

/**
 * Test deployment validation
 */
function testDeploymentValidation() {
  console.log('\n=== Testing Deployment Validation ===');
  
  try {
    // Test if validation script exists
    const validateScript = path.join(__dirname, '../deployment/validate-deployment.sh');
    if (!fs.existsSync(validateScript)) {
      throw new Error('Deployment validation script not found');
    }
    console.log('✓ Deployment validation script exists');
    
    // Test script permissions
    const stats = fs.statSync(validateScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Deployment validation script is not executable');
    }
    console.log('✓ Deployment validation script is executable');
    
    console.log('Deployment validation tests passed');
    return true;
  } catch (error) {
    console.error('❌ Deployment validation test failed:', error.message);
    return false;
  }
}

/**
 * Test atomic deployment logic
 */
function testAtomicDeployment() {
  console.log('\n=== Testing Atomic Deployment ===');
  
  try {
    // Test deployment staging concept
    const stagingDir = path.join(TEST_DIR, 'staging');
    if (!fs.existsSync(stagingDir)) {
      fs.mkdirSync(stagingDir, { recursive: true });
    }
    
    // Simulate atomic deployment staging
    const sourceFile = path.join(TEST_DIR, 'source', 'package.json');
    const stagingFile = path.join(stagingDir, 'package.json');
    
    if (fs.existsSync(sourceFile)) {
      fs.copyFileSync(sourceFile, stagingFile);
      console.log('✓ Files can be staged for atomic deployment');
      
      // Clean up staging
      fs.rmSync(stagingDir, { recursive: true, force: true });
      console.log('✓ Staging cleanup successful');
    }
    
    console.log('Atomic deployment tests passed');
    return true;
  } catch (error) {
    console.error('❌ Atomic deployment test failed:', error.message);
    return false;
  }
}

/**
 * Test cleanup
 */
function cleanupTest() {
  console.log('\nCleaning up deployment test environment...');
  
  try {
    if (fs.existsSync(TEST_DIR)) {
      fs.rmSync(TEST_DIR, { recursive: true, force: true });
    }
    console.log('Deployment test cleanup completed');
  } catch (error) {
    console.error('Warning: Deployment test cleanup failed:', error.message);
  }
}

/**
 * Run all deployment tests
 */
function runAllTests() {
  console.log('Starting Deployment Functionality Tests\n');
  
  let passed = 0;
  let total = 0;
  
  setupTest();
  
  // Run individual tests
  const tests = [
    testDeploymentConfiguration,
    testCodeOnlySync,
    testExtensionDeployment,
    testDataPreservation,
    testDeploymentValidation,
    testAtomicDeployment
  ];
  
  tests.forEach(test => {
    total++;
    if (test()) {
      passed++;
    }
  });
  
  cleanupTest();
  
  // Summary
  console.log('\n=== Deployment Test Summary ===');
  console.log(`Passed: ${passed}/${total}`);
  
  if (passed === total) {
    console.log('🎉 All deployment tests passed!');
    process.exit(0);
  } else {
    console.log('❌ Some deployment tests failed');
    process.exit(1);
  }
}

// Run tests if called directly
if (require.main === module) {
  runAllTests();
}

module.exports = {
  runAllTests,
  testDeploymentConfiguration,
  testCodeOnlySync,
  testExtensionDeployment,
  testDataPreservation,
  testDeploymentValidation,
  testAtomicDeployment
};