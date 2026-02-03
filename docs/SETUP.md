# Kiro Setup Guide

This document contains detailed configuration instructions for setting up the Kiro app with all required services.

## Prerequisites

- Xcode 16+
- iOS 17.0+ deployment target
- Apple Developer account (for Sign in with Apple, CloudKit)

## Service Configuration

### 1. Google Sign In

Create a project in [Google Cloud Console](https://console.cloud.google.com/):

1. Enable Google Calendar API and Google Tasks API
2. Create OAuth 2.0 credentials (iOS app type)
3. Add your Bundle ID: `com.kiro.app` (or your custom ID)

Add to `Kiro/Info.plist`:
```xml
<key>GIDClientID</key>
<string>YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_GOOGLE_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

### 2. Supabase

Create a project at [Supabase](https://supabase.com/):

Edit `KiroPackage/Sources/KiroFeature/Core/Storage/SupabaseClient.swift`:
```swift
private let supabaseURL = "https://YOUR_PROJECT.supabase.co"
private let supabaseKey = "YOUR_ANON_KEY"
```

Run the following SQL to create tables:
```sql
-- Pets table
CREATE TABLE pets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT 'Baby Waffle',
    pronouns TEXT DEFAULT 'They/Them',
    adventures_count INTEGER DEFAULT 0,
    age INTEGER DEFAULT 1,
    status TEXT DEFAULT 'Happy',
    mood TEXT DEFAULT 'Happy',
    scene TEXT DEFAULT 'Indoor',
    stage TEXT DEFAULT 'Baby',
    progress FLOAT DEFAULT 0.0,
    weight FLOAT DEFAULT 50,
    height FLOAT DEFAULT 5,
    tail_length FLOAT DEFAULT 2,
    current_form TEXT DEFAULT 'Cat',
    last_interaction TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Streaks table
CREATE TABLE streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_active_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Sync state table
CREATE TABLE sync_state (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    last_sync_time TIMESTAMPTZ,
    calendar_sync_token TEXT,
    tasks_sync_token TEXT,
    pending_changes JSONB DEFAULT '[]',
    status TEXT DEFAULT 'synced',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Enable Row Level Security
ALTER TABLE pets ENABLE ROW LEVEL SECURITY;
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_state ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can manage their own pets"
    ON pets FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own streaks"
    ON streaks FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own sync state"
    ON sync_state FOR ALL USING (auth.uid() = user_id);
```

### 3. OpenAI

Get an API key from [OpenAI Platform](https://platform.openai.com/):

Edit `KiroPackage/Sources/KiroFeature/Core/Network/OpenAIService.swift`:
```swift
private var apiKey: String = "sk-YOUR_OPENAI_API_KEY"
```

Or configure at runtime:
```swift
await OpenAIService.shared.configure(apiKey: "sk-YOUR_OPENAI_API_KEY")
```

**Note**: The app uses `gpt-4o-mini` model for cost-effective Haiku generation.

### 4. Sign in with Apple

Add capability in Xcode:
1. Select Kiro target → Signing & Capabilities
2. Click "+ Capability" → Add "Sign in with Apple"

Or edit `Config/Kiro.entitlements`:
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

### 5. EventKit (Calendar & Reminders)

Add to `Kiro/Info.plist`:
```xml
<key>NSCalendarsUsageDescription</key>
<string>Kiro needs access to your calendar to display events and help your pet track your schedule.</string>
<key>NSRemindersUsageDescription</key>
<string>Kiro needs access to your reminders to sync tasks with your pet companion.</string>
```

### 6. CloudKit (Optional)

For iCloud sync, add capability in Xcode:
1. Select Kiro target → Signing & Capabilities
2. Click "+ Capability" → Add "iCloud"
3. Enable "CloudKit" and create a container

### 7. Bluetooth (E-ink Device)

Add to `Kiro/Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Kiro needs Bluetooth to connect to your E-ink companion device.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Kiro needs Bluetooth to communicate with your E-ink device.</string>
```

## Environment Configuration

### Using xcconfig for Different Environments

Instead of hardcoding API keys, use environment variables:

```swift
// Debug.xcconfig
OPENAI_API_KEY = sk-dev-key
SUPABASE_URL = https://dev-project.supabase.co
SUPABASE_KEY = dev-anon-key

// Release.xcconfig
OPENAI_API_KEY = sk-prod-key
SUPABASE_URL = https://prod-project.supabase.co
SUPABASE_KEY = prod-anon-key
```

## Deployment Checklist

### Before App Store Submission
- [ ] Replace all placeholder API keys with production values
- [ ] Configure App Store Connect with app metadata
- [ ] Set up Supabase production environment
- [ ] Enable Apple Sign In in App Store Connect
- [ ] Configure Google OAuth consent screen for production
- [ ] Test all integrations in TestFlight
- [ ] Verify privacy policy and terms of service URLs
- [ ] Check all Info.plist usage descriptions are accurate
