#!/bin/sh
# Runs before server.js. Locates the Playwright-installed Chromium and
# exports it as CHROME_PATH (read by Lighthouse's chrome-launcher) and
# PUPPETEER_EXECUTABLE_PATH (read by pa11y/puppeteer). Both vars are
# then inherited by every audit.sh subprocess.
set -e

CHROMIUM_PATH=$(node --input-type=module \
  -e "import{chromium}from'playwright';process.stdout.write(chromium.executablePath());" \
  2>/dev/null || true)

if [ -n "$CHROMIUM_PATH" ] && [ -f "$CHROMIUM_PATH" ]; then
  export CHROME_PATH="$CHROMIUM_PATH"
  export PUPPETEER_EXECUTABLE_PATH="$CHROMIUM_PATH"
  echo "info: Chromium → $CHROMIUM_PATH"
else
  echo "warn: Playwright Chromium not found — audits requiring Chrome may fail"
fi

exec "$@"
