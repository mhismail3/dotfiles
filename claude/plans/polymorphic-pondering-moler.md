# Fix: Transcribe folder created at wrong location

## Problem
When testing transcription from the iOS app, directories were created at `~/.tron/transcribe` instead of the correct `~/.tron/mods/transcribe`.

## Root Cause
The transcription Python sidecar process (PID 47750) has been running since **Friday Jan 17**, before the migration commit (`c9b7bc7`) on **Saturday Jan 18** that moved the path from `~/.tron/transcribe` to `~/.tron/mods/transcribe`.

The Python process loaded `DEFAULT_BASE_DIR` at startup and cached the old value in memory. When transcription was tested on Monday Jan 20, the stale process created directories at the old path.

## Evidence
- Wrong directory created: `~/.tron/transcribe` (timestamp: Jan 20 00:57)
- Correct directory exists: `~/.tron/mods/transcribe` (timestamp: Jan 8)
- Running process environment: `PYTHONPATH=/Users/moose/Downloads/projects/tron`
- Process started: Friday (before migration)
- Migration commit: `c9b7bc7` on Sat Jan 18 19:52

## Why restarting Tron servers alone won't fix it
The transcription sidecar is **shared** between prod (port 8080) and beta (port 8082) servers. Both servers check if the sidecar is already healthy before starting a new one:

```typescript
// transcription-sidecar.ts:36
if (await isSidecarHealthy(settings.baseUrl)) {
  return;  // Sidecar already running, skip starting new one
}
```

Since the stale sidecar (PID 47750) is still running on port 8787, restarting the Tron servers will just detect it's healthy and won't start a new one.

## Solution
Kill the stale Python sidecar process. It will be automatically restarted by the Tron server on the next transcription request, loading the correct `~/.tron/mods/transcribe` path from the updated code.

## Steps

1. **Kill the stale transcription sidecar**
   ```bash
   kill 47750
   ```

2. **Clean up cached Python bytecode** (precautionary)
   ```bash
   find /Users/moose/Downloads/projects/tron/services/transcribe/__pycache__ -name "*.pyc" -delete
   ```

3. **Remove the wrongly-created directory**
   ```bash
   rm -rf ~/.tron/transcribe
   ```

4. **Verify the correct directory still has content**
   ```bash
   ls -la ~/.tron/mods/transcribe
   ```

## Files Involved (no code changes needed)
- `services/transcribe/config.py:9` - Already has correct path: `DEFAULT_BASE_DIR = Path("~/.tron/mods/transcribe")`
- `packages/server/src/transcription-sidecar.ts:83` - Already has correct path

## Verification
1. Trigger a transcription request from iOS (or restart a Tron server)
2. Confirm new process starts with correct config:
   ```bash
   ps aux | grep transcribe
   ```
3. Verify no new directories created at `~/.tron/transcribe`
4. Test transcription from iOS app - audio should process successfully

## Note
The deployed app at `~/.tron/app` is 36 commits behind (commit `2caf91f6`), but this doesn't affect the Python sidecar since the sidecar loads code from the repo via `PYTHONPATH`, not from the deployed bundle.
