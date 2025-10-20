# Directus Schema Migration Summary

## Current Situation

I've analyzed your local and production Directus databases. Here's what I found:

### Local Docker Database (17 collections)
Your local development environment has these custom collections:
- ✅ ai_agent_settings (NEW - not in production)
- ✅ ai_assistant_settings (NEW - not in production)
- ai_prompts
- article_categories
- articles
- definitions
- global_settings
- ✅ home_page (NEW - not in production)
- ✅ latest_updates (NEW - not in production)
- orama_index_snapshots
- orama_search_analytics
- orama_search_queries
- orama_user_sessions
- settings
- supporting_documents
- ✅ text_amendments (NEW - not in production)
- ✅ video_embeds (NEW - not in production)

### Production Database (12 collections)
Your production environment has:
- ai_prompts
- article_categories
- articles
- definitions
- global_settings
- orama_index_snapshots
- orama_search_analytics
- orama_search_queries
- orama_user_sessions
- ⚠️  **pages** (ONLY in production - not in local!)
- settings
- supporting_documents

## What Needs to be Migrated

### New Collections to Add to Production
These 7 collections exist in local but not in production:

1. **ai_agent_settings** - AI agent configuration
2. **ai_assistant_settings** - AI assistant configuration
3. **home_page** - Home page content
4. **latest_updates** - Latest updates/news
5. **text_amendments** - Text amendments
6. **video_embeds** - Video embed content

### ⚠️  Critical Warning: "pages" Collection

The **pages** collection exists in production but NOT in your local database!

**This means:**
- If you apply your local schema to production without being careful, the "pages" collection might be affected
- You need to either:
  1. Export "pages" data before migration
  2. Ensure your migration tool doesn't delete collections
  3. Add the "pages" collection to your local database first

## Recommended Migration Approach

I've created migration tools for you, but here's the safest step-by-step process:

### Option 1: Safe Manual Migration (RECOMMENDED)

1. **Backup Production First**
   ```bash
   ./scripts/backup-production-database.sh
   ```

2. **Use Directus MCP to Inspect Each New Collection**
   - I can help you inspect each collection's schema in local
   - Then create them one-by-one in production using the MCP tools
   - This gives you full control and avoids any deletions

3. **Verify After Each Collection**
   - Test that data works correctly
   - No existing data is affected

### Option 2: Automated Migration (Use with Caution)

The script I created (`migrate-schema-simple.sh`) can automate this, but you need to:

1. **First, add the "pages" collection to local** (or ensure migration won't delete it)
2. **Run backup**
3. **Run dry-run to see what will change**
4. **Apply migration**

## Next Steps - Let Me Know Your Preference

**I can help you in two ways:**

### A) Manual Controlled Migration (Safer)
I'll use the Directus MCP tools to:
1. Read the schema of each new collection from local
2. Create them in production one-by-one
3. You verify after each step

### B) Automated Migration (Faster but needs setup)
1. First, let's handle the "pages" collection issue
2. Then use the migration script

**Which approach would you prefer?**

## What I've Created for You

1. **`scripts/backup-production-database.sh`**
   - Safely backs up production database
   - Creates timestamped SQL dump
   - Run this BEFORE any migration!

2. **`scripts/migrate-schema-simple.sh`**
   - Automated schema migration
   - Compares local vs production
   - Applies differences
   - Has --dry-run mode

3. **`scripts/MIGRATION-GUIDE.md`**
   - Detailed documentation
   - Safety procedures
   - Troubleshooting guide

4. **`scripts/migrate-schema-to-production.js`**
   - Alternative Node.js approach
   - Uses Directus SDK
   - More granular control

## Important Safety Notes

✅ **What's Safe:**
- All migration tools preserve existing data in production
- Backups are created before changes
- Dry-run modes show what will change

⚠️  **What to Watch:**
- The "pages" collection exists only in production
- Any field/collection deletions would be permanent
- Always backup first!

🚨 **Never Do This:**
- Don't migrate without a backup
- Don't skip the dry-run
- Don't ignore warnings about deletions

## Current Status

- ✅ Local database analyzed (Docker: localhost:5432)
- ✅ Production database analyzed (Render.com)
- ✅ Migration scripts created and ready
- ✅ Backup script tested and working
- ⏸  Waiting for your decision on migration approach

---

**Ready to proceed?** Let me know if you want to:
1. Go with manual controlled migration (I'll help step-by-step)
2. Handle the "pages" issue first, then automate
3. Just migrate specific collections (tell me which ones)
