#!/usr/bin/env bash
set -euo pipefail

# Fix OpenClaw LaunchAgent install on macOS Tahoe/beta setups where
# launchd rejects plist under /Volumes/... with:
#   Path had bad ownership/permissions
#
# What it does:
# 1) Locates user LaunchAgent plist (or creates it via `openclaw gateway install` attempt)
# 2) Copies plist to /Library/LaunchAgents
# 3) Sets root:wheel + 0644
# 4) Bootstraps into current user's GUI domain
# 5) Enables + kickstarts service
# 6) Prints verification info

LABEL="ai.openclaw.gateway"
USER_UID="$(id -u)"
USER_PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
GLOBAL_PLIST="/Library/LaunchAgents/${LABEL}.plist"

log() { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[warn] %s\n" "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd launchctl
require_cmd openclaw
require_cmd sudo

log "Preflight: verify GUI launchd domain exists (gui/${USER_UID})"
if ! launchctl print "gui/${USER_UID}" >/dev/null 2>&1; then
  echo "Error: gui/${USER_UID} domain is unavailable from this shell." >&2
  echo "This usually causes: Bootstrap failed: 125 (Domain does not support specified action)." >&2
  echo "Run this from an interactive Terminal in the logged-in desktop session (not headless SSH)." >&2
  exit 1
fi

log "Checking for user plist: ${USER_PLIST}"
if [[ ! -f "${USER_PLIST}" ]]; then
  warn "User plist not found. Attempting to generate it via: openclaw gateway install"
  # This may fail with bootstrap error, but often still writes plist.
  set +e
  openclaw gateway install >/tmp/openclaw-gateway-install.out 2>&1
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warn "openclaw gateway install returned non-zero (expected on affected systems)."
    warn "Output:"
    sed -n '1,120p' /tmp/openclaw-gateway-install.out || true
  fi
fi

if [[ ! -f "${USER_PLIST}" ]]; then
  echo "Could not find ${USER_PLIST}. Aborting." >&2
  echo "Run: openclaw gateway install, then rerun this script." >&2
  exit 1
fi

log "Copying plist to global LaunchAgents path"
sudo cp "${USER_PLIST}" "${GLOBAL_PLIST}"
sudo chown root:wheel "${GLOBAL_PLIST}"
sudo chmod 644 "${GLOBAL_PLIST}"

log "Bootout any existing job in gui/${USER_UID} (safe if absent)"
launchctl bootout "gui/${USER_UID}" "${GLOBAL_PLIST}" >/dev/null 2>&1 || true

log "Bootstrap service into gui/${USER_UID}"
launchctl bootstrap "gui/${USER_UID}" "${GLOBAL_PLIST}"

log "Enable + kickstart"
launchctl enable "gui/${USER_UID}/${LABEL}"
launchctl kickstart -k "gui/${USER_UID}/${LABEL}"

log "Verification: launchctl print"
launchctl print "gui/${USER_UID}/${LABEL}" | sed -n '1,80p'

log "Verification: openclaw status"
openclaw status | sed -n '1,80p'

log "Done. If it survives reboot, you're golden."
