#!/bin/sh
# Runs before server.js. Finds the Playwright Chromium binary at the
# pinned PLAYWRIGHT_BROWSERS_PATH and exports it as:
#   CHROME_PATH              - read by Lighthouse's chrome-launcher
#   PUPPETEER_EXECUTABLE_PATH - read by pa11y/puppeteer
# Both vars are then inherited by every audit.sh subprocess.
set -e

CHROME_BIN=$(find /ms-playwright -name chrome -type f 2>/dev/null | head -1)

if [ -n "$CHROME_BIN" ] && [ -f "$CHROME_BIN" ]; then
  export CHROME_PATH="$CHROME_BIN"
  export PUPPETEER_EXECUTABLE_PATH="$CHROME_BIN"
  echo "info: Chromium → $CHROME_BIN"
else
  echo "error: Chromium binary not found in /ms-playwright — did 'npx playwright install chromium' run?"
  exit 1
fi

exec "$@"
