# Blocks: a planner that lives on your Mac

A native macOS to-do list that pulls action items from Fathom, syncs with Google Tasks, and drops work onto Google Calendar in four sizes. Originally planned as two focused days.

The four block sizes, drawn to scale — the origin of the app's name:

```
15m  ██
30m  ████
1h   ████████
2h   ████████████████
```

---

## What "hosted on my Mac" means

There's no server. Blocks is a normal Mac app that keeps its data in a file on your disk and talks straight to Google and Fathom. Credentials sit in the macOS Keychain.

```
          Your MacBook Pro
  ┌──────────────┬──────────────┬──────────────────┐
  │ SwiftUI app  │  SwiftData   │     Keychain     │
  │  One window  │ Task database│ Tokens, API keys │
  └──────────────┴──────────────┴──────────────────┘
                        │
              HTTPS, straight from the app
                        │
  ┌──────────────┬──────────────┬──────────────────┐
  │ Google Tasks │Google Calendar│     Fathom      │
  │  Two-way sync│ Blocks, today │ Action items    │
  └──────────────┴──────────────┴──────────────────┘
```

---

## Stack

| Layer | Choice | Why |
|---|---|---|
| Language and UI | Swift, SwiftUI, Xcode 27 | Native to macOS Tahoe, Mac only |
| Storage | SwiftData | Apple's built-in local database |
| Google sign-in | GoogleSignIn SDK | The biggest time saver in the plan |
| Google APIs | Plain `URLSession` | Tasks and Calendar are simple JSON APIs |
| Fathom | REST with an API key | API access included on every Fathom plan |
| Building it | Guided walkthrough, Claude Code | Code and explanations supplied; you run and review |

---

## Three facts that shaped the design

**Google Tasks can't store a time.** The Tasks API only keeps the date, and any time you send is discarded. Google keeps two separate due-date fields — the API's and the one Calendar uses — and the API's is always rounded to midnight UTC. So the calendar event owns the time, the task carries the day, and Blocks links them by storing the task's ID in the event's `extendedProperties.private`.

**Fathom webhooks need a public web address.** Your Mac isn't reachable from the internet, so Blocks asks Fathom for new meetings instead, using a created-after filter. This happens on launch and on refresh.

**Your personal Gmail needs one extra setting.** On the consent screen, choose "External," then set the publishing status to "In production" without submitting for verification. Leaving it in Testing means Google signs you out every seven days. *Still outstanding — blocked on needing a home page and privacy policy.*

---

## The two-day plan, as written

### Day 1: a working list that talks to Google

| Planned | Task |
|---|---|
| 1h | Set up the workshop — Xcode, Claude Code, the repo |
| 1h | Google Cloud project — APIs, OAuth client, consent screen |
| 15m | Fathom test call |
| 2h | The local list — three sections, quick add, completion |
| 2h | Google sign-in |
| 1h | Push to Google Tasks |
| 30m | Buffer |

**Done when** a task added in Blocks appears in Google Tasks on your phone.

### Day 2: blocks, meetings, and the full loop

| Planned | Task |
|---|---|
| 2h | Time blocks — 15m, 30m, 1h, 2h on Google Calendar |
| 1h | Walkthrough buffer |
| 2h | Fathom inbox |
| 1h | Pull from Google Tasks |
| 1h | Install and test |
| 1h | Buffer |

**Done when** a Fathom action item becomes a task, gets a time block, and checking it off marks it done in Google Tasks.

---

## How it actually went

**Setup ran about five hours instead of one.** Xcode 27 removed the new-project form the plan assumed, a Sign In with Apple capability got added by accident and broke the build, and a first pass through Terminal took longer than budgeted. Everything after setup ran closer to plan.

**Both days' goals were met**, and a number of items from the "later" list were built along the way.

### Built beyond the original plan

- Sync across all Google task lists, not just one
- Moving tasks between lists (using the API's `destinationTasklist` — no copy-and-delete needed)
- Automatic sync on window focus and every 5 minutes
- Rename in the right-click menu
- A Chrome-style find bar with match highlighting and counts
- Column sorting by task, due date, or list, with a return to manual order
- A Personal section, hideable entirely for screen shares
- Launch at login
- Global quick-add hotkey (Command-Shift-A)
- A second Fathom account, with assignee names shown on inbox rows
- Pulling calendar changes back into Blocks

### Considered and rejected

- **Drag and drop to reorder** — too substantial given its interaction with sorting, sections, and persistence
- **Filtering Fathom items by assignee** — seeing what teammates committed to has its own value

---

## Still open

**Deadline-bound**

1. **Apple Developer Program** — enrollment submitted, awaiting approval. Once active: sign out and back in to Xcode's Apple Accounts, select the new team, rebuild. Removes the seven-day signing expiry and enables notarizing for sharing.
2. **Publish the Google app** — stops the weekly Google sign-out. Needs a simple home page and privacy policy, plus adding the domain under Branding.

**In progress**

3. **Move time blocks to their own "Blocks" calendar** — separates planned work from real commitments, and lets you toggle it off. Pair with unchecking Tasks in Google Calendar's sidebar to remove duplicate chips.

**Deferred, to revisit after real use**

4. **Past-due blocks** — a scheduled time that passed without completion is a distinct state needing re-decision, not a task sitting in limbo.
5. **A cap on Top priorities** (~5 slots), where adding another forces completing or dropping one. Wait until the real number reveals itself.
6. **Fathom assignee filtering** — only if triage becomes a burden.

**Original later list, still available**

Menu bar popover with today's blocks, notifications before a block starts, a Today calendar column, database backups, on-device AI for tidying action items, Shortcuts and Siri, a desktop widget.
