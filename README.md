# FinanceTrackerReminder

FinanceTrackerReminder is an Android-first Flutter app backed by Supabase. The app connects directly to Supabase for authentication and finance data; it does not use Laravel or a separate web server.

## Requirements

- Flutter SDK and Android SDK
- A Supabase project

## Supabase setup

1. Open the Supabase project SQL Editor and run [`supabase/migrations/202611240001_initial_schema.sql`](supabase/migrations/202611240001_initial_schema.sql) once. It creates the app tables, row-level security policies, balance and recurring-transaction functions, and a private avatar bucket.
2. In **Authentication → URL Configuration**, add `personal-finance://auth-callback` to the redirect URL allowlist.
3. Enable email sign-in. Use the project URL and publishable key in the app. Never put a `service_role` or secret key in a mobile app.

## Run from VS Code

Open this repository in VS Code, select **FinanceTrackerReminder (Supabase)** in Run and Debug, then press **F5**. The launch configuration contains this project's Supabase URL and publishable key.

## Run from a terminal

```powershell
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

To run on a physical Android phone, enable Developer options and USB debugging, connect and authorize the phone, then run the command above.

## Project layout

- `lib/` — Flutter app and finance screens
- `android/` — Android app and launcher icon
- `supabase/migrations/` — database schema and security policies

The Android application ID remains `com.example.personal_finance_tracker` until a final publishing ID is chosen. This project uses a fresh Supabase database; existing Railway records are not migrated.
