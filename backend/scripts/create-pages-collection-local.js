#!/usr/bin/env node

/**
 * Create 'pages' collection in local Directus to match production
 * This prevents it from being flagged for deletion during migration
 */

import { createDirectus, authentication, rest, createCollection, createField, createRelation } from '@directus/sdk';

const LOCAL_URL = 'http://localhost:8056';
const LOCAL_EMAIL = 'nick@stump.works';
const LOCAL_PASSWORD = 'admin';

async function main() {
  console.log('🔧 Creating "pages" collection in local Directus...\n');

  // Connect to local Directus
  const client = createDirectus(LOCAL_URL)
    .with(rest())
    .with(authentication());

  try {
    await client.login({ email: LOCAL_EMAIL, password: LOCAL_PASSWORD });
    console.log('✅ Connected to local Directus\n');
  } catch (error) {
    console.error('❌ Failed to connect:', error.message);
    process.exit(1);
  }

  try {
    // Create the collection with system fields
    console.log('Creating pages collection...');
    await client.request(createCollection({
      collection: 'pages',
      meta: {
        icon: 'description',
        sort_field: 'sort',
        accountability: 'all',
        archive_field: 'status',
        archive_value: 'archived',
        unarchive_value: 'draft'
      },
      schema: {},
      fields: [
        // Primary key
        {
          field: 'id',
          type: 'uuid',
          meta: {
            hidden: true,
            readonly: true,
            interface: 'input',
            special: ['uuid']
          },
          schema: {
            is_primary_key: true,
            length: 36,
            has_auto_increment: false
          }
        },
        // Status field
        {
          field: 'status',
          type: 'string',
          meta: {
            width: 'full',
            interface: 'select-dropdown',
            options: {
              choices: [
                { text: 'Published', value: 'published' },
                { text: 'Draft', value: 'draft' },
                { text: 'Archived', value: 'archived' }
              ]
            }
          },
          schema: {
            default_value: 'draft',
            is_nullable: false
          }
        },
        // User created
        {
          field: 'user_created',
          type: 'uuid',
          meta: {
            special: ['user-created'],
            interface: 'select-dropdown-m2o',
            options: {
              template: '{{avatar}} {{first_name}} {{last_name}}'
            },
            display: 'user',
            readonly: true,
            hidden: true,
            width: 'half'
          },
          schema: {}
        },
        // User updated
        {
          field: 'user_updated',
          type: 'uuid',
          meta: {
            special: ['user-updated'],
            interface: 'select-dropdown-m2o',
            options: {
              template: '{{avatar}} {{first_name}} {{last_name}}'
            },
            display: 'user',
            readonly: true,
            hidden: true,
            width: 'half'
          },
          schema: {}
        },
        // Date updated
        {
          field: 'date_updated',
          type: 'timestamp',
          meta: {
            special: ['date-updated'],
            interface: 'datetime',
            readonly: true,
            hidden: true,
            width: 'half',
            display: 'datetime',
            display_options: {
              relative: true
            }
          },
          schema: {}
        },
        // Name field
        {
          field: 'name',
          type: 'string',
          meta: {
            interface: 'input',
            width: 'half',
            required: true
          },
          schema: {
            is_nullable: false
          }
        },
        // Slug field
        {
          field: 'slug',
          type: 'string',
          meta: {
            interface: 'input',
            width: 'half',
            required: true,
            note: 'URL-friendly identifier for the page'
          },
          schema: {
            is_nullable: false,
            is_unique: true
          }
        },
        // Sort field (for manual ordering)
        {
          field: 'sort',
          type: 'integer',
          meta: {
            interface: 'input',
            hidden: true
          },
          schema: {}
        }
      ]
    }));

    console.log('✅ Collection created successfully\n');

    // Create relations for user fields
    console.log('Creating user relations...');

    await client.request(createRelation({
      collection: 'pages',
      field: 'user_created',
      related_collection: 'directus_users',
      schema: { on_delete: 'SET NULL' }
    }));

    await client.request(createRelation({
      collection: 'pages',
      field: 'user_updated',
      related_collection: 'directus_users',
      schema: { on_delete: 'SET NULL' }
    }));

    console.log('✅ Relations created successfully\n');
    console.log('🎉 Done! The "pages" collection now exists in your local database.');
    console.log('   This matches the production schema and prevents deletion during migration.\n');

  } catch (error) {
    console.error('❌ Error:', error.message);
    if (error.errors) {
      console.error('Details:', JSON.stringify(error.errors, null, 2));
    }
    process.exit(1);
  }
}

main();
