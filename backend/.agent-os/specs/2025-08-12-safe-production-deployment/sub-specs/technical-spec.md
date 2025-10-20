# Technical Specification

This is the technical specification for the spec detailed in @.agent-os/specs/2025-08-12-safe-production-deployment/spec.md

> Created: 2025-08-12
> Version: 1.0.0

## Technical Requirements

### Backup Strategy
- Implement automated database backup using Directus CLI or direct PostgreSQL/MySQL dump
- Create timestamped backup directories for each deployment
- Backup all files from the uploads directory (typically `/uploads` or cloud storage)
- Store backups in a separate location from production data
- Implement backup verification to ensure data integrity

### Deployment Mechanism
- Use git-based deployment for code changes only
- Implement file exclusion patterns to prevent overwriting production data
- Deploy custom extensions from `/extensions` directory
- Update Directus configuration files without affecting database
- Implement atomic deployments to prevent partial updates

### Data Preservation
- Maintain production database connection strings
- Preserve environment variables for production
- Keep production file storage paths intact
- Exclude `/uploads` directory from deployment sync
- Maintain user sessions during deployment when possible

### Rollback System
- Create deployment tags/versions for each release
- Implement quick rollback to previous code version
- Maintain backup catalog for data restoration
- Create rollback scripts that can restore both code and data if needed
- Log all deployment and rollback operations

### Monitoring and Validation
- Implement pre-deployment health checks
- Validate backup completion before proceeding
- Post-deployment verification of data integrity
- Check that all images and files are accessible after deployment
- Monitor for missing assets or broken references

## External Dependencies

**rsync** - For selective file synchronization
- Justification: Efficiently sync only code changes while excluding data directories

**Directus CLI** - For schema migrations and backups
- Justification: Native Directus tooling for safe schema updates

**AWS CLI or similar** - If using cloud storage for assets
- Justification: Required for backing up cloud-stored files