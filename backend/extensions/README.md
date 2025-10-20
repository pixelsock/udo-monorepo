# Directus to Webflow Sync Extension

This Directus hook extension automatically syncs articles and article categories to Webflow when their status is set to "published".

## Features

- Real-time synchronization of articles and article categories
- Automatic creation, update, and deletion based on publish status
- Error handling with exponential backoff retry logic
- Rate limiting compliance (60 requests/minute)
- Tracks items using directus-id field to prevent duplicates

## Installation

1. Install the extension in your Directus instance
2. Configure the required environment variables
3. Restart Directus

## Environment Variables

Add these to your Directus `.env` file:

```env
# Webflow API Configuration
WEBFLOW_SITE_ID=6491f0508c10fba102cd93ea
WEBFLOW_SITE_API_TOKEN=your_webflow_api_token_here
```

### Getting Your Webflow API Token

1. Log in to your Webflow account
2. Go to Account Settings > API Access
3. Generate a new API token with the following scopes:
   - `cms:read` - Read CMS data
   - `cms:write` - Write CMS data

## How It Works

### Sync Triggers

The extension listens for the following Directus events:

#### Article Categories
- `article_categories.items.create` - When a new category is created
- `article_categories.items.update` - When a category is updated
- `article_categories.items.delete` - When a category is deleted

#### Articles
- `articles.items.create` - When a new article is created
- `articles.items.update` - When an article is updated
- `articles.items.delete` - When an article is deleted

### Sync Behavior

1. **Publishing**: When an item's status is set to "published", it will be synced to Webflow
2. **Unpublishing**: When status changes from "published" to "draft" or "archived", the item is removed from Webflow
3. **Updating**: Published items are updated in Webflow when modified in Directus
4. **Deleting**: Items deleted in Directus are also removed from Webflow

### Field Mappings

#### Article Categories
| Directus Field | Webflow Field | Type |
|---------------|---------------|------|
| name | name | PlainText |
| slug | slug | PlainText |
| description | description | PlainText |
| display_order | display-order | Number |
| id | directus-id | PlainText |

#### Articles
| Directus Field | Webflow Field | Type |
|---------------|---------------|------|
| title | name | PlainText |
| slug | slug | PlainText |
| content | content | RichText |
| article_category | article-category | Reference |
| order | order | Number |
| style_guide | style-guide | RichText |
| variables | variables | RichText |
| id | directus-id | PlainText |

## Error Handling

- Automatic retry with exponential backoff (max 3 retries)
- Delays: 1s, 2s, 4s between retries
- All errors are logged to Directus logs
- Failed syncs don't block other operations

## Development

### Building the Extension

```bash
npm run build
```

### Development Mode

```bash
npm run dev
```

### Testing

Create a test article or category in Directus and set its status to "published" to trigger the sync.

## Troubleshooting

### Common Issues

1. **Missing API Token**: Check that `WEBFLOW_SITE_API_TOKEN` is set in your `.env` file
2. **Permission Errors**: Ensure your API token has `cms:read` and `cms:write` scopes
3. **Rate Limiting**: The extension respects Webflow's 60 requests/minute limit
4. **Network Issues**: Check Directus logs for connection errors

### Viewing Logs

Sync operations are logged to the Directus logger. Check your Directus logs for:
- Sync success messages
- Error details
- Retry attempts

## API Endpoints Used

- `GET /beta/collections/{collection_id}/items/live` - List items
- `POST /beta/collections/{collection_id}/items/live` - Create item
- `PATCH /beta/collections/{collection_id}/items/live` - Update items
- `DELETE /beta/collections/{collection_id}/items/live` - Delete items

## Support

For issues or questions, check the Directus logs for detailed error messages.