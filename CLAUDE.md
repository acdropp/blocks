# Blocks

A minimal, native macOS to-do app. Runs only on Aaron's Mac; no server, no cloud hosting.
Full product description: specs/product.md

## Stack
- Xcode 27, Swift, SwiftUI. Mac only (macOS 27 minimum).
- SwiftData for local storage.
- Keychain for all secrets (Google tokens, Fathom API key).
- GoogleSignIn SDK (Swift Package Manager) for Google OAuth.
- Plain URLSession for Google Tasks, Google Calendar, and Fathom REST calls.

## Rules
- Never put secrets, API keys, or tokens in code or in the repo.
- Do not change signing, team, bundle ID (com.acdropp.Blocks), or App Sandbox settings unless asked.
- App Sandbox allows outgoing network connections only.
- Sync runs on app launch, on Refresh (Command-R in the app), when the window becomes active, and every 5 minutes while the app is open. Never more than one sync runs at a time.
- Keep the UI minimal: one window, three sections, no extra panels unless asked.

## Integration facts
- Google Tasks stores only a due date; any time is discarded. The Calendar event owns the time.
- Link a time block to its task by storing the task ID in the event's extendedProperties.private.
- Time block sizes: 15 min, 30 min, 1 hour, 2 hours only.
- Fathom: no webhooks (no public URL). Fetch new meetings with action items using a created-after filter. Check the current Fathom API docs before writing this code.
- Google account is a personal Gmail.
- The Google OAuth client ID (iOS client type) is not a secret. It goes in the app's Info settings as GIDClientID, with the reversed client ID as a URL scheme. The downloaded client plist is stored outside the repo.

## How to work with Aaron
- Aaron is new to Xcode and Swift and wants a step-by-step walkthrough.
- Make one small change at a time. Before editing, say what you will change and why, in plain language.
- After each change, build to confirm it compiles:
  xcodebuild -project Blocks.xcodeproj -scheme Blocks -destination 'platform=macOS' build
- Then tell Aaron exactly what to click or check in the running app.
- Suggest a git commit with a clear message after each working step.
