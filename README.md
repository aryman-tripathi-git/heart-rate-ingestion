# Heart Rate CSV Importer

Imports WHOOP CSV heart-rate samples into Apple Health using HealthKit.

Expected CSV columns:
`epoch_seconds,datetime_utc,datetime_local,bpm`

Only `epoch_seconds` and `bpm` are used.

## Build
Upload this folder's contents to GitHub. Then go to:
**Actions → Build Heart Rate CSV Importer → Run workflow**

The workflow builds an unsigned IPA on a GitHub-hosted macOS runner. Signing is handled separately with your Apple identity.
