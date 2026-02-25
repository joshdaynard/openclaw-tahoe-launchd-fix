# OpenClaw Gateway LaunchAgent Workaround (macOS Tahoe 26.x beta)

If `openclaw gateway install` fails with either:

- `Bootstrap failed: 125: Domain does not support specified action`
- `Bootstrap failed: 5: Input/output error`

…and/or launchd logs show:

- `Path had bad ownership/permissions`
- plist path under `/Volumes/.../Library/LaunchAgents/...`

this workaround should fix it.

---

## Why this happens

This tends to affect people who moved their macOS home directory onto an external drive.

In that setup, your account path becomes something like:

- `/Volumes/<DriveName>/<username>`

instead of the default:

- `/Users/<username>`

On some Tahoe beta systems, launchd may reject LaunchAgent plists under `/Volumes/...` with a misleading ownership/permissions error, even when the plist itself looks fine.

The same plist usually works when placed on a launchd-trusted local path (for example `/Library/LaunchAgents`).

---

## Quick fix script

From the root of this repo, run this one-shot script:

```bash
./scripts/fix-openclaw-launchagent-tahoe.sh
```

## Post-update quick checklist (30–60 seconds)

After any `openclaw update` on affected Tahoe/external-home setups:

```bash
openclaw update
./scripts/fix-openclaw-launchagent-tahoe.sh
openclaw status
```

Expected result:
- Gateway service shows installed/loaded/running
- No repeated `pairing required` reconnect spam in normal operation
- Cron jobs continue to deliver normally

### What it does

1. Locates/creates `~/Library/LaunchAgents/ai.openclaw.gateway.plist`
2. Copies plist to `/Library/LaunchAgents/ai.openclaw.gateway.plist`
3. Sets ownership/permissions to `root:wheel` + `0644`
4. Boots out stale/duplicate jobs (by label and both plist paths)
5. Bootstraps into your user GUI domain: `gui/$UID` (idempotent-safe)
6. Enables + kickstarts service
7. Verifies with `launchctl print` and `openclaw status`

---

## Manual commands (if you prefer)

```bash
sudo cp ~/Library/LaunchAgents/ai.openclaw.gateway.plist /Library/LaunchAgents/ai.openclaw.gateway.plist
sudo chown root:wheel /Library/LaunchAgents/ai.openclaw.gateway.plist
sudo chmod 644 /Library/LaunchAgents/ai.openclaw.gateway.plist

launchctl bootout gui/$(id -u) /Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) /Library/LaunchAgents/ai.openclaw.gateway.plist
launchctl enable gui/$(id -u)/ai.openclaw.gateway
launchctl kickstart -k gui/$(id -u)/ai.openclaw.gateway
```

Verify:

```bash
launchctl print gui/$(id -u)/ai.openclaw.gateway | head -40
openclaw status
```

---

## Sudo rule of thumb

- `~/Library/LaunchAgents`: usually no sudo for `launchctl` operations in your own `gui/$UID` domain.
- `/Library/LaunchAgents`: use sudo for file writes (`cp/chown/chmod`).
- `launchctl bootstrap gui/$UID ...`: typically run as your user (sudo may still work, but domain is what matters).

---

## Common error patterns

### 1) `Bootstrap failed: 125: Domain does not support specified action`

Usually means launchctl is being invoked from the wrong context/domain.

Most common causes:
- running from a non-GUI shell/session
- trying to load a LaunchAgent into `system` domain
- mixing sudo with the wrong launchctl domain target

Fix:
- run from a logged-in desktop Terminal session
- target `gui/$(id -u)` for LaunchAgent bootstrap
- use sudo for `/Library/LaunchAgents` file writes only (`cp/chown/chmod`)

### 2) `Bootstrap failed: 5: Input/output error`

On affected Tahoe + external-home setups, this is often a generic wrapper over:
- `Path had bad ownership/permissions`
- when plist path is under `/Volumes/...`

Fix:
- use this repo script to stage plist under `/Library/LaunchAgents` and bootstrap in `gui/$UID`

## Troubleshooting

Check launchd logs for the true reason:

```bash
/usr/bin/log show --last 10m --predicate 'process == "launchd"' --style compact | tail -n 200
```

If you still see `bad ownership/permissions`, validate:

```bash
ls -ledO /Library/LaunchAgents/ai.openclaw.gateway.plist
```

Expected-ish:
- owner: `root`
- group: `wheel`
- mode: `-rw-r--r--` (644)
