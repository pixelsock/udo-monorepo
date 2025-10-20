# Product Roadmap

## Phase 0: Already Completed

The following features have been implemented in the current backend:

- [x] **Directus CMS Installation** - Base Directus installation with PostgreSQL database configured and running locally
- [x] **AI Agent Extension** - PostgreSQL-compatible AI Agent extension installed and configured for content assistance
- [x] **Extensions Marketplace Configuration** - Non-sandboxed extensions enabled for marketplace extension installation
- [x] **Schema Migration Scripts** - Custom migration scripts created for schema backup, restoration, and API-based migration
- [x] **Table Wrapper Removal Tools** - Scripts developed to clean up legacy table wrapper HTML from content
- [x] **Basic Collections** - Core collections for UDO content (pages, articles, regulations) created
- [x] **Git Version Control** - Repository initialized with main branch and commit history

## Phase 1: Render Deployment Optimization `L`

**Goal:** Establish a reliable, repeatable deployment workflow from local development to Render production environment.

**Success Criteria:** Developers can deploy schema changes and content to Render with zero downtime and automated rollback capability.

### Features

- [ ] **Render Environment Configuration** - Configure Render web service with proper environment variables, build commands, and PostgreSQL connection settings `M`
- [ ] **Automated Schema Migration Pipeline** - Create GitHub Actions workflow that automatically runs schema migrations on deployment to Render `L`
- [ ] **Environment Sync Validation** - Build validation scripts that compare local and production schemas to detect drift before deployment `M`
- [ ] **Deployment Documentation** - Write comprehensive deployment guide covering local→staging→production workflow with rollback procedures `S`

### Dependencies

- Render account with web service and PostgreSQL database provisioned
- GitHub Actions access configured for repository

## Phase 2: Content Management Enhancement `L`

**Goal:** Optimize the content editing experience for city staff managing UDO regulations and articles.

**Success Criteria:** Content editors can efficiently create, update, and publish UDO content with AI assistance and validation.

### Features

- [ ] **Custom Field Types for Regulations** - Develop Directus extension with specialized field types for regulation numbers, effective dates, and legal references `M`
- [ ] **Content Validation Rules** - Implement validation hooks to ensure required fields, proper formatting, and legal compliance before publishing `M`
- [ ] **AI-Powered Content Assistance** - Configure AI Agent extension with UDO-specific prompts for drafting summaries and checking regulatory language `L`
- [ ] **Bulk Content Import Tools** - Create scripts to import existing UDO content from legacy sources into Directus collections `M`
- [ ] **Content Workflow & Approvals** - Configure multi-stage approval workflow for content changes requiring legal review `S`

### Dependencies

- Phase 1 deployment workflow completed
- Sample UDO content available for testing

## Phase 3: API Optimization & Documentation `M`

**Goal:** Provide a fast, well-documented API for frontend developers and third-party integrators.

**Success Criteria:** API endpoints deliver sub-200ms response times with comprehensive documentation and stable contracts.

### Features

- [ ] **GraphQL Schema Optimization** - Design efficient GraphQL schema with proper relations and field selections for UDO queries `M`
- [ ] **API Response Caching** - Implement Directus caching layer for frequently accessed regulations and definitions `S`
- [ ] **API Documentation Portal** - Set up Directus API documentation with examples, authentication guides, and GraphQL playground `S`
- [ ] **Rate Limiting & Security** - Configure API rate limits, CORS policies, and access tokens for public and authenticated endpoints `M`

### Dependencies

- Phase 2 content collections finalized
- Frontend API requirements documented

## Phase 4: Advanced Extensions & Automation `XL`

**Goal:** Extend Directus capabilities with custom extensions that automate repetitive tasks and enhance content management.

**Success Criteria:** City staff spend 50% less time on routine content updates through automation and intelligent tooling.

### Features

- [ ] **Automated Cross-Reference Linking** - Build extension that automatically detects and links references between UDO articles (e.g., "See Article 15.2") `L`
- [ ] **Content Change Notifications** - Create webhook-based notification system that alerts stakeholders when specific regulations are updated `M`
- [ ] **Version Comparison Interface** - Develop custom interface panel showing side-by-side comparison of regulation changes over time `L`
- [ ] **Scheduled Content Publishing** - Implement scheduled publishing for regulations with future effective dates `M`
- [ ] **Search Indexing Enhancement** - Integrate full-text search with PDF document content extraction and indexing `L`

### Dependencies

- Phase 3 API optimization completed
- TypeScript extension development workflow established

## Phase 5: Monitoring & Analytics `M`

**Goal:** Provide visibility into system health, API usage, and content engagement to inform improvements.

**Success Criteria:** Operations team has real-time alerts for issues and monthly analytics reports on API and content usage.

### Features

- [ ] **Application Performance Monitoring** - Integrate APM tool (e.g., New Relic, Sentry) for error tracking and performance metrics `M`
- [ ] **API Usage Analytics** - Build analytics dashboard showing endpoint usage, popular content, and API consumer patterns `M`
- [ ] **Content Health Dashboard** - Create custom interface showing outdated content, missing fields, and content quality metrics `S`
- [ ] **Automated Backup Verification** - Implement automated testing of database backups with restoration validation `S`

### Dependencies

- Phase 1 Render deployment stable
- Budget/approval for monitoring service subscription

> Notes
> - Roadmap focuses on backend capabilities and developer workflow optimization
> - Frontend development (../frontend) is tracked separately
> - Phase priorities may shift based on city stakeholder feedback
> - Each phase builds incrementally on previous phase infrastructure
