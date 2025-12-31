# Plan: Robust Auto-Start After Power Outage

## Goal
Ensure Clauset service automatically runs after power outages without manual intervention.

## Current State
- **Power settings**: Already configured correctly (`autorestart=1`, `auto-boot=true`, `sleep=0`)
- **Gap**: Service uses LaunchAgent (user-level) which requires login to activate
- **Result**: After power outage, Mac boots but sits at login screen - service doesn't start

## Solution: Enable Automatic Login

The simplest approach - enable auto-login so the Mac automatically logs in after boot, which triggers LaunchAgents.

### Implementation Steps

1. **Enable Automatic Login**
   ```bash
   sudo sysadminctl -autologin set -userName moose
   ```
   (Will prompt for password interactively)

2. **Verify Power Settings Are Correct**
   ```bash
   # Confirm these settings (already in place)
   pmset -g | grep autorestart  # Should be 1
   nvram -p | grep auto-boot    # Should be true
   ```

3. **Add ThrottleInterval to Prevent Rapid Restart Loops**

   Update plist to add a 10-second throttle between restart attempts:
   - File: `~/Library/LaunchAgents/com.clauset.server.plist`
   - Add `<key>ThrottleInterval</key><integer>10</integer>` after KeepAlive block

4. **Update Documentation**

   Add "Power Failure Recovery" section to `deployment.md` documenting:
   - Automatic login setup
   - Power management settings
   - What happens during power recovery
   - Security considerations

5. **Test the Setup**
   - Simulate power failure: `sudo shutdown -r now`
   - Verify Mac boots, auto-logs in, and service starts

## Files to Modify
- `~/Library/LaunchAgents/com.clauset.server.plist` - Add ThrottleInterval
- `scripts/clauset` - Update `cmd_install()` to include ThrottleInterval
- `deployment.md` - Add documentation section

## Security Note
Automatic login means anyone with physical access to the Mac can access the logged-in account. Since this is a home server behind your network, this is an acceptable tradeoff for reliability.

## Recovery Chain After Power Outage
```
Power restored
    → Mac auto-boots (auto-boot=true in NVRAM)
    → macOS auto-restarts after power failure (autorestart=1)
    → Auto-login activates (sysadminctl -autologin)
    → LaunchAgent loads (RunAtLoad=true)
    → Service starts
    → If service crashes, launchd restarts it (KeepAlive)
```
