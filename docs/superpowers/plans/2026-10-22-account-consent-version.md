# Registration consent version — 2026-10-22

The displayed app documents are version 6, updated 2026-10-22. Registration previously sent a hardcoded version 4. A pure legal_version.dart metadata module now supplies both the document exports and AccountService registration payload. Login does not manufacture a new consent record.

The backend accepts known historical versions 4, 5 and 6 and stores the exact submitted value. Existing records are not upgraded. Unknown versions and role injection remain rejected. Public-page update metadata comes from the same backend legal config.

Verification: 34 app tests passed, including the mounted registration form refusing submission without consent, opening its actual terms page and sending version 6 after acceptance. Full backend suite: 220 passed. Five-file fatal Flutter analysis: clean.

Rollout dependency: the deployed older backend accepts only version 4. Deploy the updated backend before distributing this app change. Do not silently fall back to version 4 or claim existing users accepted version 6. No new APK is delivered for this change before backend compatibility is available. Live deployment remains pending Railway authentication.
