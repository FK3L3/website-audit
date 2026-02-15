#!/usr/bin/env bash
set -euo pipefail

DEFAULT_URL="https://dropsites.biz/"
SUMMARY_ONLY=0
SECURITY_MODE=0
URL="$DEFAULT_URL"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
TS="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="$REPORT_DIR/$TS"

usage() {
  cat <<'EOF'
Usage:
  ./audit.sh [--summary] [--security] [url]

Options:
  --summary   Print a compact summary (scores + issue counts)
  --security  Run extra security checks (headers, TLS, optional ZAP)
  -h, --help  Show help
EOF
}

while (($#)); do
  case "$1" in
    --summary)
      SUMMARY_ONLY=1
      shift
      ;;
    --security)
      SECURITY_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      URL="$1"
      shift
      ;;
  esac
done

mkdir -p "$RUN_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd npm
require_cmd npx

if [ ! -f "$SCRIPT_DIR/package.json" ]; then
  npm init -y >/dev/null 2>&1
fi

if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
  echo "Installing audit dependencies..."
  npm i -D lighthouse pa11y playwright broken-link-checker >/dev/null
  npx playwright install chromium >/dev/null
fi

run_security_checks() {
  local security_file="$RUN_DIR/security.txt"
  local host
  host="$(node -e "console.log(new URL(process.argv[1]).hostname)" "$URL")"
  local headers_file="$RUN_DIR/security-headers.txt"
  local tls_file="$RUN_DIR/tls-cert.txt"
  local zap_dir="$RUN_DIR/zap"
  local docker_prefix=""

  : >"$security_file"
  echo "Security checks for $URL" >>"$security_file"
  echo >>"$security_file"

  echo "[headers]" >>"$security_file"
  if command -v curl >/dev/null 2>&1; then
    curl -sSIL "$URL" >"$headers_file"
    local required_headers=(
      "strict-transport-security"
      "content-security-policy"
      "x-frame-options"
      "x-content-type-options"
      "referrer-policy"
      "permissions-policy"
    )
    local missing=0
    for h in "${required_headers[@]}"; do
      if ! grep -qi "^$h:" "$headers_file"; then
        echo "MISSING: $h" >>"$security_file"
        missing=$((missing + 1))
      fi
    done
    echo "missing_headers: $missing" >>"$security_file"
  else
    echo "SKIPPED: curl not installed" >>"$security_file"
    echo "missing_headers: unknown" >>"$security_file"
  fi

  echo >>"$security_file"
  echo "[tls]" >>"$security_file"
  if command -v openssl >/dev/null 2>&1; then
    if openssl s_client -connect "$host:443" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -dates -issuer -subject >"$tls_file"; then
      cat "$tls_file" >>"$security_file"
      local not_after
      not_after="$(sed -n 's/^notAfter=//p' "$tls_file")"
      if [ -n "$not_after" ]; then
        local expiry_epoch now_epoch days_left
        expiry_epoch="$(date -d "$not_after" +%s 2>/dev/null || true)"
        now_epoch="$(date +%s)"
        if [ -n "$expiry_epoch" ]; then
          days_left="$(((expiry_epoch - now_epoch) / 86400))"
          echo "cert_days_left: $days_left" >>"$security_file"
        fi
      fi
    else
      echo "FAILED: TLS certificate fetch failed for $host:443" >>"$security_file"
    fi
  else
    echo "SKIPPED: openssl not installed" >>"$security_file"
  fi

  echo >>"$security_file"
  echo "[zap_baseline]" >>"$security_file"
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      docker_prefix=""
    elif command -v sg >/dev/null 2>&1; then
      docker_prefix="sg docker -c"
    fi
    mkdir -p "$zap_dir"
    if [ -n "$docker_prefix" ]; then
      if $docker_prefix "docker run --rm -v \"$zap_dir:/zap/wrk\" ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t \"$URL\" -J zap.json -r zap.html -m 2" >"$RUN_DIR/zap.txt" 2>&1; then
        echo "status: completed" >>"$security_file"
      elif grep -qE 'WARN-NEW:|FAIL-NEW:' "$RUN_DIR/zap.txt"; then
        echo "status: completed_with_findings (see $RUN_DIR/zap.txt)" >>"$security_file"
      else
        echo "status: issues_or_errors (see $RUN_DIR/zap.txt)" >>"$security_file"
      fi
    elif docker run --rm -v "$zap_dir:/zap/wrk" ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t "$URL" -J zap.json -r zap.html -m 2 >"$RUN_DIR/zap.txt" 2>&1; then
      echo "status: completed" >>"$security_file"
    elif grep -qE 'WARN-NEW:|FAIL-NEW:' "$RUN_DIR/zap.txt"; then
      echo "status: completed_with_findings (see $RUN_DIR/zap.txt)" >>"$security_file"
    else
      echo "status: issues_or_errors (see $RUN_DIR/zap.txt)" >>"$security_file"
    fi
  elif command -v zap.sh >/dev/null 2>&1; then
    if zap.sh -cmd -silent -quickurl "$URL" -quickprogress -quickout "$RUN_DIR/zap-quick.html" >"$RUN_DIR/zap.txt" 2>&1; then
      echo "status: completed_local_quick_scan" >>"$security_file"
    elif grep -qE 'WARN-NEW:|FAIL-NEW:' "$RUN_DIR/zap.txt"; then
      echo "status: completed_local_with_findings (see $RUN_DIR/zap.txt)" >>"$security_file"
    else
      echo "status: issues_or_errors_local (see $RUN_DIR/zap.txt)" >>"$security_file"
    fi
  else
    echo "status: skipped (docker and local zap.sh not installed)" >>"$security_file"
  fi
}

print_summary() {
  local lh_json="$RUN_DIR/lighthouse/report.report.json"
  local pa11y_file="$RUN_DIR/pa11y.txt"
  local bl_file="$RUN_DIR/broken-links.txt"
  local smoke_file="$RUN_DIR/smoke.txt"

  local scores
  scores="$(node -e "const fs=require('fs');const j=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));const c=j.categories;console.log([Math.round(c.performance.score*100),Math.round(c.accessibility.score*100),Math.round(c['best-practices'].score*100),Math.round(c.seo.score*100)].join(' '));" "$lh_json")"
  local perf acc bp seo
  read -r perf acc bp seo <<<"$scores"

  local pa11y_status="PASS"
  if grep -q "No issues found" "$pa11y_file"; then
    pa11y_status="PASS"
  else
    pa11y_status="ISSUES"
  fi

  local broken_count="0"
  broken_count="$(sed -nE 's/.* ([0-9]+) broken\..*/\1/p' "$bl_file" | tail -n1)"
  broken_count="${broken_count:-0}"

  local smoke_status="PASS"
  if grep -q "^Issues found:" "$smoke_file"; then
    smoke_status="ISSUES"
  fi

  echo
  echo "Summary"
  echo "URL: $URL"
  echo "Run: $RUN_DIR"
  echo "Lighthouse: perf=$perf a11y=$acc best_practices=$bp seo=$seo"
  echo "Pa11y: $pa11y_status"
  echo "Broken links: $broken_count"
  echo "Smoke: $smoke_status"
  if [ "$SECURITY_MODE" -eq 1 ] && [ -f "$RUN_DIR/security.txt" ]; then
    local sec_missing sec_zap sec_days
    sec_missing="$(sed -n 's/^missing_headers: //p' "$RUN_DIR/security.txt" | tail -n1)"
    sec_zap="$(sed -n 's/^status: //p' "$RUN_DIR/security.txt" | tail -n1)"
    sec_days="$(sed -n 's/^cert_days_left: //p' "$RUN_DIR/security.txt" | tail -n1)"
    sec_missing="${sec_missing:-unknown}"
    sec_zap="${sec_zap:-unknown}"
    sec_days="${sec_days:-unknown}"
    echo "Security: missing_headers=$sec_missing cert_days_left=$sec_days zap=$sec_zap"
  fi
}

echo "Running website audit for: $URL"
echo "Report directory: $RUN_DIR"

echo "[1/4] Lighthouse"
mkdir -p "$RUN_DIR/lighthouse"
npx lighthouse "$URL" \
  --only-categories=performance,accessibility,best-practices,seo \
  --output=html --output=json \
  --output-path="$RUN_DIR/lighthouse/report" \
  --chrome-flags="--headless" >/dev/null

echo "[2/4] Accessibility (pa11y)"
if ! npx pa11y "$URL" --reporter cli --standard WCAG2AA > "$RUN_DIR/pa11y.txt" 2>&1; then
  echo "pa11y found issues. See $RUN_DIR/pa11y.txt"
fi

echo "[3/4] Broken links"
if ! npx blc "$URL" -ro > "$RUN_DIR/broken-links.txt" 2>&1; then
  echo "Broken link checker reported issues. See $RUN_DIR/broken-links.txt"
fi

echo "[4/4] Playwright smoke"
if ! node "$SCRIPT_DIR/smoke.mjs" "$URL" "$RUN_DIR" > "$RUN_DIR/smoke.txt" 2>&1; then
  echo "Smoke test found issues. See $RUN_DIR/smoke.txt"
fi

if [ "$SECURITY_MODE" -eq 1 ]; then
  echo "[5/5] Security checks"
  run_security_checks
fi

echo

echo "Audit complete."
echo "- Lighthouse HTML: $RUN_DIR/lighthouse/report.report.html"
echo "- Lighthouse JSON: $RUN_DIR/lighthouse/report.report.json"
echo "- Pa11y report:    $RUN_DIR/pa11y.txt"
echo "- Broken links:    $RUN_DIR/broken-links.txt"
echo "- Smoke report:    $RUN_DIR/smoke.txt"
echo "- Screenshot:      $RUN_DIR/homepage.png"
if [ "$SECURITY_MODE" -eq 1 ]; then
  echo "- Security report: $RUN_DIR/security.txt"
  if [ -f "$RUN_DIR/zap.txt" ]; then
    echo "- ZAP output:      $RUN_DIR/zap.txt"
  fi
fi

if [ "$SUMMARY_ONLY" -eq 1 ]; then
  print_summary
fi
