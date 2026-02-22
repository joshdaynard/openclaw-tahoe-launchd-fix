# OpenClaw Gateway LaunchAgent Workaround (macOS Tahoe 26.x beta)

If `openclaw gateway install` fails with:

- `Bootstrap failed: 5: Input/output error`

…and launchd logs show:

- `Path had bad ownership/permissions`
- plist path under `/Volumes/.../Library/LaunchAgents/...`

this workaround should fix it.

---

## Why this happens

On some Tahoe beta setups (especially with home directories under `/Volumes/...`), launchd may reject user LaunchAgent plists at those paths even when file perms look correct.

The same plist usually works if loaded from a more trusted local path.

---

## Quick fix script

Use this one-shot script:

```bash
~/\.openclaw/workspace/scripts/fix-openclaw-launchagent-tahoe.sh
```

(Or full path: `/Volumes/eHome/joshd/.openclaw/workspace/scripts/fix-openclaw-launchagent-tahoe.sh`)

### What it does

1. Locates/creates `~/Library/LaunchAgents/ai.openclaw.gateway.plist`
2. Copies plist to `/Library/LaunchAgents/ai.openclaw.gateway.plist`
3. Sets ownership/permissions to `root:wheel` + `0644`
4. Bootstraps into your user GUI domain: `gui/$UID`
5. Enables + kickstarts service
6. Verifies with `launchctl print` and `openclaw status`

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
