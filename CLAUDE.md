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
- Command-Shift-A is a global hotkey (works even when Blocks isn't the active app) that opens a small floating quick-add field. Closing the main window no longer quits Blocks — it keeps running so the hotkey still works. Quit via Command-Q or the Dock menu.

## Integration facts
- Google Tasks stores only a due date; any time is discarded. The Calendar event owns the time.
- Link a time block to its task by storing the task ID in the event's extendedProperties.private.
- Time block sizes: 15 min, 30 min, 1 hour, 2 hours only.
- Fathom: no webhooks (no public URL). Fetch new meetings with action items using a created-after filter. Check the current Fathom API docs before writing this code.
- Google account is a personal Gmail.
- The Google OAuth client ID (iOS client type) is not a secret. It goes in the app's Info settings as GIDClientID, with the reversed client ID as a URL scheme. The downloaded client plist is stored outside the repo.
- On each sync, Calendar changes flow back into Blocks for any task with a block: if the event's time changed, Blocks updates to match; if the event was deleted, the task's block is cleared (the task itself is kept). Calendar always wins if it disagrees with Blocks or Tasks.
- New time blocks are created on a secondary "Blocks" calendar, not the primary calendar, using the calendar.app.created OAuth scope. That scope only covers creating/managing calendars this app made — it does NOT cover listing the user's full calendar list (that needs a separate, broader scope), so Blocks creates the calendar once and remembers its ID locally rather than ever searching for an existing one; there's deliberately no "pick a different calendar" picker in Settings for this reason. Each TodoItem stores which calendar its event is on (calendarID; nil means primary, for blocks created before this existed). Event reads/updates/deletes always use that stored calendar ID. Each event's description is set to the task's Google Tasks list name. Settings offers to move any blocks still on the primary calendar over to the Blocks calendar.
- GoogleSignIn's `signOut()` only clears local session state — it does NOT revoke the grant with Google, so it won't force a fresh consent screen after adding a new OAuth scope. Use `disconnect()` instead when a real re-consent is needed (that's what Sign Out in Settings does).
- A task's calendar event is deleted whenever the task itself is deleted, from any source: in-app delete, or sync detecting the task was removed directly on Google Tasks. If the event is deleted directly on Google Calendar instead, the task is kept, its block is cleared, and it moves to the Opt-out list (Settings). A completed task's calendar event title is prefixed "✓ "; un-completing removes it. The title is always recomputed from the task's own title + completion state (never edited in place), so it can't double up.
- Command-Z/Command-Shift-Z (the app's native Edit menu Undo/Redo, no custom menu code) cover delete, rename, and moving a task between sections or Google Tasks lists — not completion toggles or time-block scheduling. Each of these functions registers its own reversal on `Environment(\.undoManager)`, and the reversal registers the original action back, which is what makes redo work. Undoing a delete recreates the task with fresh Google Tasks/Calendar IDs (the originals are gone), not a byte-for-byte restore.

## How to work with Aaron
- Aaron is new to Xcode and Swift and wants a step-by-step walkthrough.
- Make one small change at a time. Before editing, say what you will change and why, in plain language.
- After each change, build to confirm it compiles:
  xcodebuild -project Blocks.xcodeproj -scheme Blocks -destination 'platform=macOS' build
- Then tell Aaron exactly what to click or check in the running app.
- Suggest a git commit with a clear message after each working step.
