# 🚨 Quick Fix for Production Search Issue

## Run This Command Now

Execute this single command to fix the search indexing issue in production:

```bash
render psql dpg-d1gsdjjipnbc73b509f0-a < scripts/deployment/orama-analytics-tables.sql
```

## Or Step by Step

If you prefer to run it step by step:

### Step 1: Connect to the database
```bash
render psql dpg-d1gsdjjipnbc73b509f0-a
```

### Step 2: Once connected, paste this SQL:

```sql
-- Create orama_search_analytics table
CREATE TABLE IF NOT EXISTS orama_search_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query TEXT NOT NULL,
    user_ip VARCHAR(45),
    user_agent TEXT,
    results_count INTEGER NOT NULL DEFAULT 0,
    response_time INTEGER NOT NULL,
    search_mode VARCHAR(20) DEFAULT 'fulltext',
    collection_name VARCHAR(100),
    clicked_result_id VARCHAR(255),
    clicked_position INTEGER,
    session_id UUID,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create orama_search_queries table
CREATE TABLE IF NOT EXISTS orama_search_queries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    query_text TEXT NOT NULL,
    query_hash VARCHAR(64) NOT NULL UNIQUE,
    search_count INTEGER DEFAULT 1,
    last_searched TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    avg_response_time INTEGER,
    avg_results_count INTEGER,
    success_rate DECIMAL(5,2) DEFAULT 100.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create orama_user_sessions table
CREATE TABLE IF NOT EXISTS orama_user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_hash VARCHAR(64) NOT NULL,
    user_ip VARCHAR(45),
    user_agent TEXT,
    search_count INTEGER DEFAULT 0,
    first_search TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_search TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    total_response_time INTEGER DEFAULT 0,
    avg_response_time INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create orama_index_snapshots table
CREATE TABLE IF NOT EXISTS orama_index_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_name VARCHAR(255) NOT NULL,
    collections TEXT NOT NULL,
    document_count INTEGER NOT NULL,
    index_size_bytes BIGINT NOT NULL,
    file_path TEXT NOT NULL,
    compression_type VARCHAR(20) DEFAULT 'binary',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT FALSE
);

-- Create all indexes
CREATE INDEX IF NOT EXISTS idx_orama_search_analytics_timestamp ON orama_search_analytics(timestamp);
CREATE INDEX IF NOT EXISTS idx_orama_search_analytics_query ON orama_search_analytics USING hash(query);
CREATE INDEX IF NOT EXISTS idx_orama_search_analytics_session ON orama_search_analytics(session_id);
CREATE INDEX IF NOT EXISTS idx_orama_search_analytics_mode ON orama_search_analytics(search_mode);
CREATE INDEX IF NOT EXISTS idx_orama_search_analytics_collection ON orama_search_analytics(collection_name);

CREATE INDEX IF NOT EXISTS idx_orama_search_queries_hash ON orama_search_queries(query_hash);
CREATE INDEX IF NOT EXISTS idx_orama_search_queries_count ON orama_search_queries(search_count);
CREATE INDEX IF NOT EXISTS idx_orama_search_queries_last_searched ON orama_search_queries(last_searched);
CREATE INDEX IF NOT EXISTS idx_orama_search_queries_success_rate ON orama_search_queries(success_rate);

CREATE INDEX IF NOT EXISTS idx_orama_user_sessions_hash ON orama_user_sessions(session_hash);
CREATE INDEX IF NOT EXISTS idx_orama_user_sessions_last_search ON orama_user_sessions(last_search);
CREATE INDEX IF NOT EXISTS idx_orama_user_sessions_search_count ON orama_user_sessions(search_count);

CREATE INDEX IF NOT EXISTS idx_orama_index_snapshots_active ON orama_index_snapshots(is_active, created_at);
CREATE INDEX IF NOT EXISTS idx_orama_index_snapshots_name ON orama_index_snapshots(snapshot_name);
CREATE INDEX IF NOT EXISTS idx_orama_index_snapshots_created ON orama_index_snapshots(created_at);
```

### Step 3: Verify the tables were created
```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name LIKE 'orama_%';
```

You should see:
- orama_search_analytics
- orama_search_queries
- orama_user_sessions
- orama_index_snapshots

### Step 4: Exit psql
```sql
\q
```

## What This Fixes

✅ Enables search query tracking
✅ Fixes search indexing issues
✅ Allows analytics collection
✅ Restores full search functionality

## After Deployment

The search functionality should start working immediately after creating these tables. No restart required!