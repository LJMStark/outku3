-- Outku Supabase Database Schema
-- Run this SQL in your Supabase SQL Editor to create the required tables

-- ==========================================
-- Pets Table
-- ==========================================
CREATE TABLE IF NOT EXISTS pets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    pronouns TEXT DEFAULT 'they/them',
    adventures_count INTEGER DEFAULT 0,
    age INTEGER DEFAULT 1,
    status TEXT DEFAULT 'happy',
    mood TEXT DEFAULT 'happy',
    scene TEXT DEFAULT 'indoor',
    stage TEXT DEFAULT 'baby',
    progress DOUBLE PRECISION DEFAULT 0,
    weight DOUBLE PRECISION DEFAULT 50,
    height DOUBLE PRECISION DEFAULT 5,
    tail_length DOUBLE PRECISION DEFAULT 2,
    current_form TEXT DEFAULT 'cat',
    last_interaction TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- ==========================================
-- Streaks Table
-- ==========================================
CREATE TABLE IF NOT EXISTS streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_active_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- ==========================================
-- Sync State Table
-- ==========================================
CREATE TABLE IF NOT EXISTS sync_state (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    last_sync_time TIMESTAMPTZ,
    calendar_sync_token TEXT,
    tasks_sync_token TEXT,
    pending_changes INTEGER DEFAULT 0,
    status TEXT DEFAULT 'synced',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- ==========================================
-- Row Level Security (RLS)
-- ==========================================

-- Enable RLS on all tables
ALTER TABLE pets ENABLE ROW LEVEL SECURITY;
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_state ENABLE ROW LEVEL SECURITY;

-- Pets policies
CREATE POLICY "Users can view own pets" ON pets
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own pets" ON pets
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own pets" ON pets
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own pets" ON pets
    FOR DELETE USING (auth.uid() = user_id);

-- Streaks policies
CREATE POLICY "Users can view own streaks" ON streaks
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own streaks" ON streaks
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own streaks" ON streaks
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own streaks" ON streaks
    FOR DELETE USING (auth.uid() = user_id);

-- Sync state policies
CREATE POLICY "Users can view own sync_state" ON sync_state
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own sync_state" ON sync_state
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sync_state" ON sync_state
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own sync_state" ON sync_state
    FOR DELETE USING (auth.uid() = user_id);

-- ==========================================
-- Updated At Trigger
-- ==========================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_pets_updated_at
    BEFORE UPDATE ON pets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_streaks_updated_at
    BEFORE UPDATE ON streaks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
