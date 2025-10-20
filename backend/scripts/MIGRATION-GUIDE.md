# Directus Schema Migration Guide

## Safe Migration from Local to Production

This guide will help you safely migrate your Directus schema (collections, fields, relations) from your local development environment to production **without losing any data**.

## ⚠️ Important Safety Information

**What This Migration Does:**
- ✅ Migrates schema changes (collections, fields, relations)
- ✅ Preserves all existing production data
- ✅ Creates backups before making changes
- ✅ Shows you exactly what will change before applying

**What This Migration Does NOT Do:**
- ❌ Does not migrate content/data from local to production
- ❌ Does not delete production data (unless you delete a field/collection)
- ❌ Does not affect files/assets

## Prerequisites

Before starting the migration, ensure you have:

1. ✅ Node.js installed (v18 or higher)
2. ✅ PostgreSQL client tools installed (`pg_dump`, `psql`, `pg_isready`)
3. ✅ Local Directus instance running on `http://localhost:8056`
4. ✅ Access to production Directus at `https://udo-backend-y1w0.onrender.com`
5. ✅ Admin credentials for both local and production

### Install PostgreSQL Client Tools

**macOS:**
```bash
brew install postgresql
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install postgresql-client
```

## Migration Process

Follow these steps in order to safely migrate your schema:

### Step 1: Backup Production Database

**Always create a backup before making changes!**

```bash
./scripts/backup-production-database.sh
```

This will create a timestamped backup in `backups/production/`.

**What to expect:**
- Script tests connection to production database
- Creates a complete SQL dump
- Shows backup file size and location
- Takes 1-5 minutes depending on database size

**Output:**
```
✅ Backup completed successfully!
Backup file: backups/production/production-backup-2025-10-19T14-30-00.sql
Backup size: 15M
```

### Step 2: Run Migration in Dry-Run Mode

**See what changes will be made without applying them:**

```bash
node scripts/migrate-schema-to-production.js --dry-run
```

**What to expect:**
- Connects to both local and production Directus
- Takes snapshots of both schemas
- Generates a detailed diff
- Shows summary of changes
- **No changes are applied in this mode**

**Example output:**
```
=================================================================
SCHEMA MIGRATION SUMMARY
=================================================================

Total changes: 12

Collections:
  ➕ Create: 2
  ✏️  Update: 0
  ❌ Delete: 0

Fields:
  ➕ Create: 8
  ✏️  Update: 2
  ❌ Delete: 0

Relations:
  ➕ Create: 2
  ✏️  Update: 0
  ❌ Delete: 0

-----------------------------------------------------------------
DETAILED CHANGES
-----------------------------------------------------------------

➕ create collection: new_collection_name
➕ create field: articles.new_field
✏️  update field: pages.existing_field
...
```

### Step 3: Review the Changes

**Carefully review the dry-run output:**

1. **Green (➕) Create operations** - New collections/fields/relations being added
   - ✅ Safe - adds new schema without affecting existing data

2. **Blue (✏️) Update operations** - Existing items being modified
   - ⚠️  Review carefully - may affect how existing data is displayed/validated

3. **Red (❌) Delete operations** - Items being removed
   - 🚨 **DANGEROUS** - Will permanently delete fields/collections and their data
   - Only proceed if you're absolutely sure

### Step 4: Apply the Migration

**After reviewing and confirming the changes are correct:**

```bash
node scripts/migrate-schema-to-production.js
```

**What to expect:**
- Same steps as dry-run
- Asks for confirmation before applying
- Applies changes to production
- Shows success message

**Interactive confirmation:**
```
⚠️  IMPORTANT SAFETY CHECKS:
   1. Have you backed up your production database?
   2. Have you reviewed all changes above?
   3. Are you sure you want to proceed?

Apply these changes to production? (yes/no):
```

**Type `yes` to proceed, anything else to cancel.**

**Skip confirmation (use with caution):**
```bash
node scripts/migrate-schema-to-production.js --force
```

### Step 5: Verify the Migration

**After the migration completes successfully:**

1. **Check the production Directus admin panel:**
   - Visit: https://admin.charlotteudo.org
   - Login with your credentials
   - Navigate to Settings → Data Model
   - Verify all new collections and fields are present

2. **Test your application:**
   - Check that existing data is still accessible
   - Verify new fields/collections work as expected
   - Test any forms or interfaces that use the new schema

3. **Monitor logs:**
   - Check Render.com logs for any errors
   - Watch for any API errors in your application

## Troubleshooting

### Migration Script Fails

**Connection errors:**
```
❌ Failed to connect to local Directus
```

**Solution:**
- Ensure local Directus is running: `docker compose -f docker-compose.local.yml up -d`
- Check that it's accessible at http://localhost:8056
- Verify credentials in the migration script

**Schema diff errors:**
```
❌ Failed to generate diff
```

**Solution:**
- Both Directus instances should be on the same version
- Check console output for specific error messages
- Try updating Directus to the latest version

### Restore from Backup

**If something goes wrong, restore from your backup:**

```bash
# Set your production database password
export PGPASSWORD="00N0rXxlwSL25CoLxxwcW6r6jTFdrkeB"

# Restore the backup
psql -h dpg-d1gsdjjipnbc73b509f0-a.oregon-postgres.render.com \
     -p 5432 \
     -U admin \
     -d cltudo_postgres \
     < backups/production/production-backup-YYYY-MM-DDTHH-MM-SS.sql
```

**Replace `YYYY-MM-DDTHH-MM-SS` with your backup timestamp.**

## Best Practices

1. **Always backup first** - Never skip Step 1
2. **Always dry-run first** - Review changes before applying
3. **Migrate during low traffic** - Minimize impact on users
4. **Test in staging** - If you have a staging environment, test there first
5. **Incremental changes** - Migrate smaller changes more frequently
6. **Document changes** - Keep notes on what was migrated and when

## Common Scenarios

### Adding New Collections

**Safe operation** - No risk to existing data

Example:
```
➕ create collection: blog_posts
➕ create field: blog_posts.id
➕ create field: blog_posts.title
➕ create field: blog_posts.content
```

### Adding Fields to Existing Collections

**Safe operation** - Existing data is preserved

Example:
```
➕ create field: articles.featured_image
➕ create relation: articles.featured_image → directus_files
```

### Modifying Field Types

**Potentially risky** - May cause data conversion issues

Example:
```
✏️  update field: articles.publish_date (string → timestamp)
```

**What to check:**
- Ensure existing data is compatible with new type
- Test data conversion before migration
- Consider creating a new field and migrating data manually

### Deleting Collections or Fields

**DANGEROUS** - Will permanently delete data

Example:
```
❌ delete field: articles.old_field
❌ delete collection: deprecated_table
```

**What to do:**
1. Export data you want to keep
2. Confirm you want to delete
3. Have a backup ready
4. Consider hiding/deprecating instead of deleting

## File Structure

After migration, you'll have:

```
backups/
├── production/
│   ├── production-backup-2025-10-19T14-30-00.sql
│   └── production-backup-2025-10-19T15-45-00.sql
schema-snapshots/
├── local-1729350000000.json
├── production-1729350000000.json
└── diff-1729350000000.json
```

**Keep these files for reference and disaster recovery!**

## Additional Resources

- [Directus Schema Migration Docs](https://docs.directus.io/guides/migration.html)
- [Directus API Documentation](https://docs.directus.io/reference/introduction.html)
- [PostgreSQL Backup Best Practices](https://www.postgresql.org/docs/current/backup.html)

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review the Directus documentation
3. Check Render.com logs for production issues
4. Restore from backup if needed

---

**Last Updated:** 2025-10-19
**Directus Version:** 11.x
**Script Version:** 1.0.0
