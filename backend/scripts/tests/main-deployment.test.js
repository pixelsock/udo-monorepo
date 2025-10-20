#!/usr/bin/env node
/**
 * Main Deployment Workflow Tests
 * Tests for the main deployment orchestration script
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
  console.log('Setting up main deployment test environment...');
  
  // Create test directories
  if (!fs.existsSync(TEST_DIR)) {
    fs.mkdirSync(TEST_DIR, { recursive: true });
  }
  
  // Create mock production and staging environment
  const prodDir = path.join(TEST_DIR, 'production');
  const stagingDir = path.join(TEST_DIR, 'staging');
  
  [prodDir, stagingDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  });
  
  // Create production data that should be preserved
  const prodUploads = path.join(prodDir, 'uploads');
  const prodData = path.join(prodDir, 'data');
  
  fs.mkdirSync(prodUploads, { recursive: true });
  fs.mkdirSync(prodData, { recursive: true });
  
  fs.writeFileSync(path.join(prodUploads, 'important-file.jpg'), 'important production data');
  fs.writeFileSync(path.join(prodData, 'database.sqlite'), 'database content');
  
  // Create staging content
  fs.writeFileSync(path.join(stagingDir, 'package.json'), '{"name": "test-app", "version": "1.0.0"}');
  fs.writeFileSync(path.join(stagingDir, '.env.example'), 'EXAMPLE_VAR=value');
  
  console.log('Main deployment test environment ready');
}

/**
 * Test main deployment script exists and is executable
 */
function testMainDeploymentScript() {
  console.log('\n=== Testing Main Deployment Script ===');
  
  try {
    // Test if main deployment script exists
    const deployScript = path.join(__dirname, '../deployment/deploy.sh');
    if (!fs.existsSync(deployScript)) {
      throw new Error('Main deployment script not found');
    }
    console.log('✓ Main deployment script exists');
    
    // Test script permissions
    const stats = fs.statSync(deployScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Main deployment script is not executable');
    }
    console.log('✓ Main deployment script is executable');
    
    console.log('Main deployment script tests passed');
    return true;
  } catch (error) {
    console.error('❌ Main deployment script test failed:', error.message);
    return false;
  }
}

/**
 * Test pre-deployment checks
 */
function testPreDeploymentChecks() {
  console.log('\n=== Testing Pre-Deployment Checks ===');
  
  try {
    // Test if pre-deployment check script exists
    const preCheckScript = path.join(__dirname, '../deployment/pre-deployment-checks.sh');
    if (!fs.existsSync(preCheckScript)) {
      throw new Error('Pre-deployment checks script not found');
    }
    console.log('✓ Pre-deployment checks script exists');
    
    // Test script permissions
    const stats = fs.statSync(preCheckScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Pre-deployment checks script is not executable');
    }
    console.log('✓ Pre-deployment checks script is executable');
    
    // Test dry-run functionality
    console.log('Testing pre-deployment checks dry-run...');
    const dryRunResult = execSync(`bash ${preCheckScript} --dry-run --target ${TEST_DIR}/production`, { encoding: 'utf8' });
    if (!dryRunResult.includes('DRY RUN') && !dryRunResult.includes('PRE-DEPLOYMENT')) {
      throw new Error('Pre-deployment checks dry-run mode not working properly');
    }
    console.log('✓ Pre-deployment checks dry-run mode working');
    
    console.log('Pre-deployment checks tests passed');
    return true;
  } catch (error) {
    console.error('❌ Pre-deployment checks test failed:', error.message);
    return false;
  }
}

/**
 * Test post-deployment validation
 */
function testPostDeploymentValidation() {
  console.log('\n=== Testing Post-Deployment Validation ===');
  
  try {
    // Test if post-deployment validation script exists
    const postValidateScript = path.join(__dirname, '../deployment/post-deployment-validation.sh');
    if (!fs.existsSync(postValidateScript)) {
      throw new Error('Post-deployment validation script not found');
    }
    console.log('✓ Post-deployment validation script exists');
    
    // Test script permissions
    const stats = fs.statSync(postValidateScript);
    if (!(stats.mode & 0o100)) {
      throw new Error('Post-deployment validation script is not executable');
    }
    console.log('✓ Post-deployment validation script is executable');
    
    console.log('Post-deployment validation tests passed');
    return true;
  } catch (error) {
    console.error('❌ Post-deployment validation test failed:', error.message);
    return false;
  }
}

/**
 * Test deployment orchestration workflow
 */
function testDeploymentOrchestration() {
  console.log('\n=== Testing Deployment Orchestration ===');
  
  try {
    const deployScript = path.join(__dirname, '../deployment/deploy.sh');
    const stagingDir = path.join(TEST_DIR, 'staging');
    const prodDir = path.join(TEST_DIR, 'production');
    
    // Test deployment workflow in dry-run mode
    console.log('Testing deployment orchestration dry-run...');
    const dryRunResult = execSync(`bash ${deployScript} --dry-run --source ${stagingDir} --target ${prodDir}`, { encoding: 'utf8' });
    
    if (!dryRunResult.includes('DRY RUN')) {
      throw new Error('Deployment orchestration dry-run mode not working properly');
    }
    console.log('✓ Deployment orchestration dry-run mode working');
    
    // Check that dry-run mentions key workflow steps
    const expectedSteps = ['backup', 'validation', 'deployment'];
    const missingSteps = expectedSteps.filter(step => !dryRunResult.toLowerCase().includes(step));
    
    if (missingSteps.length > 0) {
      throw new Error(`Deployment workflow missing steps: ${missingSteps.join(', ')}`);
    }
    console.log('✓ Deployment workflow includes all expected steps');
    
    console.log('Deployment orchestration tests passed');
    return true;
  } catch (error) {
    console.error('❌ Deployment orchestration test failed:', error.message);
    return false;
  }
}

/**
 * Test deployment logging and monitoring
 */
function testDeploymentLogging() {
  console.log('\n=== Testing Deployment Logging ===');
  
  try {
    // Test if deployment creates proper logs
    const deployScript = path.join(__dirname, '../deployment/deploy.sh');
    const stagingDir = path.join(TEST_DIR, 'staging');
    const prodDir = path.join(TEST_DIR, 'production');
    
    // Run deployment in dry-run mode and check for logging output
    console.log('Testing deployment logging...');
    const logResult = execSync(`bash ${deployScript} --dry-run --verbose --source ${stagingDir} --target ${prodDir}`, { encoding: 'utf8' });
    
    // Check for timestamp logging
    if (!logResult.match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/)) {
      throw new Error('Deployment does not include proper timestamp logging');
    }
    console.log('✓ Deployment includes timestamp logging');
    
    // Check for verbose output
    if (!logResult.includes('VERBOSE') && !logResult.includes('verbose')) {
      throw new Error('Verbose mode not working properly');
    }
    console.log('✓ Verbose logging mode working');
    
    console.log('Deployment logging tests passed');
    return true;
  } catch (error) {
    console.error('❌ Deployment logging test failed:', error.message);
    return false;
  }
}

/**
 * Test deployment error handling
 */
function testDeploymentErrorHandling() {
  console.log('\n=== Testing Deployment Error Handling ===');
  
  try {
    const deployScript = path.join(__dirname, '../deployment/deploy.sh');
    
    // Test with invalid source directory
    console.log('Testing error handling with invalid source...');
    try {
      execSync(`bash ${deployScript} --dry-run --source /nonexistent/directory --target ${TEST_DIR}/production`, { encoding: 'utf8' });
      throw new Error('Deployment should have failed with invalid source directory');
    } catch (error) {
      if (error.status === 0) {
        throw new Error('Deployment should have failed with invalid source directory');
      }
      console.log('✓ Deployment properly handles invalid source directory');
    }
    
    // Test with invalid target directory (parent doesn't exist)
    console.log('Testing error handling with invalid target...');
    try {
      execSync(`bash ${deployScript} --dry-run --source ${TEST_DIR}/staging --target /nonexistent/parent/target`, { encoding: 'utf8' });
      throw new Error('Deployment should have failed with invalid target directory');
    } catch (error) {
      if (error.status === 0) {
        throw new Error('Deployment should have failed with invalid target directory');
      }
      console.log('✓ Deployment properly handles invalid target directory');
    }
    
    console.log('Deployment error handling tests passed');
    return true;
  } catch (error) {
    console.error('❌ Deployment error handling test failed:', error.message);
    return false;
  }
}

/**
 * Test deployment configuration loading
 */
function testDeploymentConfiguration() {
  console.log('\n=== Testing Deployment Configuration Loading ===');
  
  try {
    const deployScript = path.join(__dirname, '../deployment/deploy.sh');
    const configFile = path.join(__dirname, '../deployment/deploy-config.json');
    
    // Test that deployment script can load configuration
    console.log('Testing configuration loading...');
    const configResult = execSync(`bash ${deployScript} --dry-run --config ${configFile} --source ${TEST_DIR}/staging --target ${TEST_DIR}/production`, { encoding: 'utf8' });
    
    if (configResult.includes('ERROR') && configResult.includes('config')) {
      throw new Error('Configuration loading failed');
    }
    console.log('✓ Configuration loading working');
    
    // Test with missing configuration file
    console.log('Testing missing configuration handling...');
    try {
      execSync(`bash ${deployScript} --dry-run --config /nonexistent/config.json --source ${TEST_DIR}/staging --target ${TEST_DIR}/production`, { encoding: 'utf8' });
      throw new Error('Deployment should have failed with missing config file');
    } catch (error) {
      if (error.status === 0) {
        throw new Error('Deployment should have failed with missing config file');
      }
      console.log('✓ Deployment properly handles missing configuration file');
    }
    
    console.log('Deployment configuration tests passed');
    return true;
  } catch (error) {
    console.error('❌ Deployment configuration test failed:', error.message);
    return false;
  }
}

/**
 * Test deployment rollback preparation
 */
function testRollbackPreparation() {
  console.log('\n=== Testing Rollback Preparation ===');
  
  try {
    const deployScript = path.join(__dirname, '../deployment/deploy.sh');
    const prodDir = path.join(TEST_DIR, 'production');
    
    // Test that deployment prepares for rollback
    console.log('Testing rollback preparation...');
    const rollbackResult = execSync(`bash ${deployScript} --dry-run --source ${TEST_DIR}/staging --target ${prodDir}`, { encoding: 'utf8' });
    
    // Check for rollback-related output
    if (!rollbackResult.toLowerCase().includes('rollback') && !rollbackResult.toLowerCase().includes('backup')) {
      throw new Error('Deployment does not appear to prepare for rollback');
    }
    console.log('✓ Deployment prepares for rollback');
    
    console.log('Rollback preparation tests passed');
    return true;
  } catch (error) {
    console.error('❌ Rollback preparation test failed:', error.message);
    return false;
  }
}

/**
 * Test cleanup
 */
function cleanupTest() {
  console.log('\nCleaning up main deployment test environment...');
  
  try {
    if (fs.existsSync(TEST_DIR)) {
      fs.rmSync(TEST_DIR, { recursive: true, force: true });
    }
    console.log('Main deployment test cleanup completed');
  } catch (error) {
    console.error('Warning: Main deployment test cleanup failed:', error.message);
  }
}

/**
 * Run all main deployment tests
 */
function runAllTests() {
  console.log('Starting Main Deployment Workflow Tests\n');
  
  let passed = 0;
  let total = 0;
  
  setupTest();
  
  // Run individual tests
  const tests = [
    testMainDeploymentScript,
    testPreDeploymentChecks,
    testPostDeploymentValidation,
    testDeploymentOrchestration,
    testDeploymentLogging,
    testDeploymentErrorHandling,
    testDeploymentConfiguration,
    testRollbackPreparation
  ];
  
  tests.forEach(test => {
    total++;
    if (test()) {
      passed++;
    }
  });
  
  cleanupTest();
  
  // Summary
  console.log('\n=== Main Deployment Test Summary ===');
  console.log(`Passed: ${passed}/${total}`);
  
  if (passed === total) {
    console.log('🎉 All main deployment tests passed!');
    process.exit(0);
  } else {
    console.log('❌ Some main deployment tests failed');
    process.exit(1);
  }
}

// Run tests if called directly
if (require.main === module) {
  runAllTests();
}

module.exports = {
  runAllTests,
  testMainDeploymentScript,
  testPreDeploymentChecks,
  testPostDeploymentValidation,
  testDeploymentOrchestration,
  testDeploymentLogging,
  testDeploymentErrorHandling,
  testDeploymentConfiguration,
  testRollbackPreparation
};