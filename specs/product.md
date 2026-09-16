# Blocks: product spec

## What it is
A personal to-do list for Mac that pulls in meeting action items from Fathom,
syncs with Google Tasks, and schedules time blocks on Google Calendar.

## Main window
- Quick-add field at the top. Return adds a task.
- Three sections: Top priorities, Other to-dos, Completed (collapsed by default).
- Checking a task moves it to Completed.
- A keyboard shortcut moves a task between Top priorities and Other to-dos.
- Hovering a task shows four buttons: 15m, 30m, 1h, 2h.

## Time blocks
- Picking a size asks for a start time, defaulting to the next quarter hour.
- Creates a Google Calendar event with the task title and sets the task's date.

## Google Tasks
- Sign in with Google in Settings. Choose one task list to mirror.
- Push: new tasks, renames, completions.
- Pull on launch and Refresh. Most recent edit wins.
- Section (priority vs. other) is stored locally only.

## Fathom
- API key entered in Settings, stored in Keychain.
- On launch and Refresh, fetch new meetings and their action items.
- New items appear in an inbox row labeled with the meeting name.
- One click accepts (into a section) or dismisses. Never import the same item twice.

## Later, not now
Background sync, drag and drop, free-slot suggestions, menu bar, launch at login,
notifications, today calendar column, backups, on-device AI, Shortcuts, widget.
