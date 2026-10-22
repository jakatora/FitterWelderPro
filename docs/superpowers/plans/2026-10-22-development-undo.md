# Development undo acceptance — 2026-10-22

Native `development.undo` restores up to 20 assistant edits of the current cone/transition calculator. Geometry snapshots retain raw controller text and selected shape/mode/reference/seam options. Manual form edits and unit changes invalidate history; account identity/session revision changes clear it before the next operation. No database record is deleted or reverted. The source guard accepts explicit undo wording only.

Validation: 22 tests passed across development undo, export and height suites; fatal-info analysis of four changed Dart files passed. New widget coverage includes all three shapes, cross-shape restoration, manual edit preservation and account-service replacement. No hardware, live AI, Railway deployment or production acceptance claimed.

Cheap model configuration already present in backend: AI_CHAT_MODEL and AI_INTENT_MODEL default to claude-haiku-5-5. Exact local commands avoid provider calls. Production configuration remains unverified while Railway authentication is pending.
