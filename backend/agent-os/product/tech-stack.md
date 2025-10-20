# Technical Stack

## Backend Framework & Runtime

- **Application Framework:** Directus CMS (latest stable)
- **Language:** Node.js v22 LTS
- **Package Manager:** npm
- **TypeScript:** Enabled with full type support

## Database & Storage

- **Primary Database:** PostgreSQL 17+
- **ORM:** Directus native (built on Knex.js)
- **Database Hosting:** Render Managed PostgreSQL
- **Database Backups:** Daily automated via scripts
- **Asset Storage:** Directus native file storage (configurable to S3)

## Directus Extensions

- **AI Agent Extension:** PostgreSQL-compatible version for content assistance
- **Custom Extensions:** Marketplace extensions enabled (non-sandboxed mode)
- **Extension Development:** TypeScript-based with hot reload support

## Frontend Integration

- **API Type:** RESTful + GraphQL endpoints
- **Frontend Framework:** React (in ../frontend directory)
- **Frontend Build Tool:** Vite (assumed based on standards)
- **API Authentication:** Directus token-based authentication

## Hosting & Deployment

- **Application Hosting:** Render (Web Service)
- **Frontend Hosting:** Render (Static Site or Web Service)
- **Database Hosting:** Render Managed PostgreSQL
- **Hosting Region:** US-based (Charlotte proximity)
- **Environment Management:** Environment variables via Render dashboard

## CI/CD & Version Control

- **Code Repository:** GitHub (git-based workflow)
- **CI/CD Platform:** GitHub Actions
- **CI/CD Trigger:** Push to main/production branches
- **Branch Strategy:** Feature branches → main branch
- **Deployment Target:** Render Web Service

## Development Tools

- **Local Database:** Docker PostgreSQL (optional)
- **Migration Tools:** Custom schema migration scripts
- **Backup Scripts:** Production database backup automation
- **Development Scripts:** npm scripts for common tasks

## Schema Management

- **Schema Snapshots:** JSON-based schema exports
- **Migration Strategy:** Snapshot-based with API-driven migrations
- **Schema Versioning:** Git-tracked schema-snapshots directory

## Security & Access

- **Authentication:** Directus native authentication system
- **Authorization:** Role-based access control (RBAC)
- **API Security:** Token-based with configurable permissions
- **Environment Secrets:** Managed via Render environment variables

## Monitoring & Logging

- **Application Logs:** Render native logging
- **Error Tracking:** TBD (future enhancement)
- **Performance Monitoring:** TBD (future enhancement)

## Documentation

- **API Documentation:** Directus auto-generated API docs
- **Schema Documentation:** schema-snapshots directory
- **Migration Guides:** scripts/MIGRATION-GUIDE.md
- **Agent OS Documentation:** agent-os/product/ directory
