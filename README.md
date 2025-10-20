# Charlotte UDO Monorepo

Unified Ordinance Code documentation platform powered by Directus and Fumadocs, deployed on Render with private networking for optimal performance.

## Architecture

This monorepo contains two services that communicate over Render's private network:

### Backend (`/backend`)
- **Type**: Private Service (not publicly accessible)
- **Technology**: Directus headless CMS with custom extensions
- **Database**: PostgreSQL (managed by Render)
- **Purpose**: Content management and API
- **Access**: Internal only via `http://directus-backend:8055`

### Frontend (`/frontend`)
- **Type**: Static Site
- **Technology**: Next.js 15 + Fumadocs documentation framework
- **Purpose**: Public documentation website
- **Access**: Public via custom domain

## Key Features

### Private Networking
The backend is deployed as a private service, accessible only from within Render's private network. This provides:
- **30-50% faster** communication between frontend and backend
- **Enhanced security** - backend never exposed to public internet
- **Cost efficiency** - no bandwidth charges for internal traffic

### Monorepo Advantages
- Single repository for easier version control and coordination
- Shared deployment configuration via `render.yaml` Blueprint
- Selective deployment triggers using build filters
- Unified CI/CD pipeline

## Getting Started

### Prerequisites
- Node.js 22 LTS
- npm package manager
- Render account
- GitHub account

### Local Development

1. **Clone the repository**
   ```bash
   git clone https://github.com/pixelsock/udo-monorepo.git
   cd udo-monorepo
   ```

2. **Backend Setup**
   ```bash
   cd backend
   npm install

   # Copy environment variables
   cp .env.example .env.local

   # Configure your .env.local with:
   # - Database credentials
   # - Directus admin credentials
   # - Secret keys

   # Start Directus
   npm start
   ```

3. **Frontend Setup**
   ```bash
   cd frontend
   npm install

   # Copy environment variables
   cp .env.local.example .env.local

   # For local development, use public URL:
   # DIRECTUS_URL=https://admin.charlotteudo.org

   # Or if running backend locally:
   # DIRECTUS_URL=http://localhost:8055

   # Start development server
   npm run dev
   ```

4. **Access the applications**
   - Backend: http://localhost:8055
   - Frontend: http://localhost:3002

## Deployment

### Automatic Deployment via Render Blueprint

This repository uses Render Blueprint (`render.yaml`) for Infrastructure as Code deployment.

1. **Connect Repository to Render**
   - Go to [Render Dashboard](https://dashboard.render.com)
   - Click "New Blueprint"
   - Connect this GitHub repository
   - Render will automatically detect `render.yaml`

2. **Configure Secrets**
   Before deployment, set these environment variables in Render Dashboard:

   **Backend Service:**
   - `ADMIN_EMAIL`: Directus admin email
   - `ADMIN_PASSWORD`: Directus admin password
   - `SECRET`: Directus secret key (auto-generated)

   **Frontend Service:**
   - `DIRECTUS_TOKEN`: Directus API token
   - `DIRECTUS_EMAIL`: Directus API user email
   - `DIRECTUS_PASSWORD`: Directus API user password
   - `NEXT_PUBLIC_ORAMA_ENDPOINT`: Orama Cloud endpoint
   - `NEXT_PUBLIC_ORAMA_API_KEY`: Orama Cloud API key

3. **Deploy**
   - Click "Apply" to deploy all services
   - Render will:
     - Create PostgreSQL database
     - Deploy backend as private service
     - Deploy frontend as static site
     - Configure private networking automatically

### Selective Deployment

The monorepo uses build filters to deploy only when relevant code changes:

- **Backend deploys** when `backend/**` files change
- **Frontend deploys** when `frontend/**` files change

This ensures efficient deployments without rebuilding unchanged services.

## Project Structure

```
udo-monorepo/
├── backend/                  # Directus backend
│   ├── extensions/          # Custom Directus extensions
│   ├── Dockerfile           # Docker configuration
│   └── package.json
├── frontend/                # Fumadocs frontend
│   ├── app/                 # Next.js app directory
│   ├── content/             # MDX documentation content
│   ├── scripts/             # Build and sync scripts
│   └── package.json
├── render.yaml              # Render Blueprint configuration
└── README.md
```

## Environment Variables

### Backend (`/backend`)

```bash
# Database (auto-configured by Render)
DB_CLIENT=pg
DB_HOST=<from-render>
DB_PORT=<from-render>
DB_DATABASE=<from-render>
DB_USER=<from-render>
DB_PASSWORD=<from-render>

# Directus
SECRET=<generate-secure-key>
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=<secure-password>
PUBLIC_URL=https://admin.charlotteudo.org

# CORS (allow frontend)
CORS_ENABLED=true
CORS_ORIGIN=https://charlotteudo.org
CORS_CREDENTIALS=true
```

### Frontend (`/frontend`)

```bash
# Directus (uses private network URL in production)
DIRECTUS_URL=http://directus-backend:8055
DIRECTUS_TOKEN=<your-token>
DIRECTUS_EMAIL=<api-user-email>
DIRECTUS_PASSWORD=<api-user-password>

# Orama Search
NEXT_PUBLIC_ORAMA_ENDPOINT=https://cloud.orama.run/v1/indexes/<your-index>
NEXT_PUBLIC_ORAMA_API_KEY=<your-api-key>

# Next.js
NODE_ENV=production
```

## Private Networking Details

### Internal URLs
When deployed on Render, services communicate using internal hostnames:

- Backend: `http://directus-backend:8055`
- Database: Auto-configured via Blueprint property references

### Benefits
1. **Performance**: Direct container-to-container communication
2. **Security**: Backend never exposed to public internet
3. **Cost**: No bandwidth charges for internal traffic
4. **Simplicity**: No need for authentication between services

### How It Works
1. Frontend static build fetches content from backend at build time
2. Builds use internal URL: `http://directus-backend:8055`
3. No runtime backend requests needed (fully static output)
4. Content sync happens during build process

## Content Management Workflow

1. **Edit Content**: Log into Directus backend to create/edit articles
2. **Publish**: Mark articles as "published" status
3. **Trigger Build**: Push to GitHub or manually trigger deploy in Render
4. **Sync & Build**: Frontend build fetches latest content via private network
5. **Deploy**: Updated static site goes live automatically

## Monitoring & Logs

Access logs and metrics via Render Dashboard:
- **Backend Logs**: Private service activity and API requests
- **Frontend Logs**: Build process and deployment status
- **Database Metrics**: Connection counts, query performance

## Troubleshooting

### Backend Not Accessible
- Verify it's deployed as **private service** (pserv)
- Check internal hostname: `directus-backend`
- Review backend service logs in Render dashboard

### Frontend Build Failures
- Check `DIRECTUS_URL` is set to internal URL
- Verify backend is running and accessible
- Review environment variables configuration

### Database Connection Issues
- Verify database is in same region as backend (us-east)
- Check property references in `render.yaml`
- Review database credentials in Render dashboard

## Performance Optimization

### Current Optimizations
- Private networking for internal API calls (30-50% faster)
- Static site generation (no runtime backend requests)
- PostgreSQL pro plan with connection pooling
- Build filters to avoid unnecessary deployments

### Future Improvements
- CDN configuration for static assets
- Image optimization pipeline
- Redis caching layer for backend
- Incremental static regeneration

## Security

### Current Security Measures
- Backend isolated on private network
- Database IP allowlist (empty = private only)
- CORS restricted to frontend domain
- Environment-specific secrets management
- HTTPS for all public endpoints

### Best Practices
- Never commit `.env.local` files
- Rotate secrets regularly
- Use Render's secret management (sync: false)
- Keep dependencies updated
- Review Directus access policies

## Contributing

1. Create feature branch from `main`
2. Make changes in relevant workspace (`frontend/` or `backend/`)
3. Test locally before pushing
4. Submit pull request with clear description
5. Wait for automated checks to pass

## License

[Your License Here]

## Support

For issues or questions:
- **Bug Reports**: Open GitHub issue
- **Feature Requests**: Discuss in GitHub discussions
- **General Questions**: Contact team via [your contact method]

---

Built with ❤️ using Directus, Next.js, Fumadocs, and Render.
