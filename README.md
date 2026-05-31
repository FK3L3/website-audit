# Website Audit

Runs Lighthouse, Pa11y (WCAG2AA), broken-link scanning, and a Playwright smoke test against any URL. Optional security mode adds HTTP header checks, TLS cert inspection, and an OWASP ZAP baseline scan.

Three ways to run it — pick whichever fits your workflow.

---

## 1. GitHub Actions

No local setup required. Go to **Actions → Website Audit → Run workflow**, enter a URL, and click **Run**.

**Inputs**

| Input | Default | Description |
|---|---|---|
| `url` | `https://example.com/` | Target URL to audit |
| `summary` | off | Print a compact score summary at the end |
| `security` | off | Run security checks (headers, TLS, ZAP) |

**What you get**

- A job summary in the Actions run with Lighthouse score indicators (🟢/🟡/🔴), and pass/fail rows for Pa11y, broken links, smoke, and (optionally) security
- The full Lighthouse HTML report, all result text files, and a full-page screenshot uploaded as a downloadable artifact (30-day retention)

No secrets or extra configuration needed — push the repo to GitHub and the workflow is ready.

---

## 2. Web UI (local)

A local Express server with a browser dashboard. Enter a URL, click **Run Audit**, and watch live output stream in. Results render automatically when the audit finishes: Lighthouse score rings, status cards, screenshot, and a link to the full Lighthouse HTML report.

**Start**

```bash
npm install    # first time only
npm start      # → http://localhost:3000
```

Use `npm run dev` for auto-restart on file changes (requires Node 18+).

---

## 3. CLI

Run the audit script directly from your terminal.

**Requirements:** `npm` and `npx` must be in your PATH. Dependencies install automatically on first run.

```bash
chmod +x audit.sh
./audit.sh [--summary] [--security] [url]
```

**Options**

| Flag | Description |
|---|---|
| `[url]` | Target URL (must start with `http://` or `https://`). Defaults to `https://example.com/` |
| `--summary` | Print a compact score/issue summary at the end |
| `--security` | Run security checks: HTTP headers, TLS cert, optional OWASP ZAP scan |
| `-h`, `--help` | Show usage |

Flags can be combined in any order. If multiple URLs are passed, the last one wins.

**Exit code:** `0` when all checks pass, `1` when any check finds issues — suitable for use in CI pipelines.

**Examples**

```bash
# Audit the default URL
./audit.sh

# Audit a specific URL
./audit.sh https://mysite.com/

# Compact summary
./audit.sh --summary https://mysite.com/

# Full security scan with summary
./audit.sh --security --summary https://mysite.com/
```

---

## Security checks (`--security`)

Checks three things:

1. **HTTP headers** — presence of `Strict-Transport-Security`, `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`
2. **TLS certificate** — expiry date, issuer, days remaining (requires `openssl`)
3. **OWASP ZAP baseline scan** — passive scan via Docker (`ghcr.io/zaproxy/zaproxy:stable`); falls back to local `zap.sh` if Docker is unavailable; skipped if neither is present

**Docker setup for ZAP (Debian/Ubuntu)**

```bash
sudo apt-get update && sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# Log out and back in, then verify:
docker info
```

---

## Output

Each run creates a timestamped folder at `reports/YYYYMMDD-HHMMSS/`:

| File | Contents |
|---|---|
| `lighthouse/report.report.html` | Full interactive Lighthouse report |
| `lighthouse/report.report.json` | Machine-readable Lighthouse data |
| `pa11y.txt` | Accessibility issues (WCAG2AA) |
| `broken-links.txt` | Broken link scan results |
| `smoke.txt` | Console errors, page errors, HTTP 4xx/5xx on load |
| `homepage.png` | Full-page screenshot |
| `security.txt` | Header and TLS results (`--security` only) |
| `zap.txt`, `zap/` | ZAP scan output (`--security` + Docker only) |

The `reports/` directory is excluded from git.

---

## Responsible use

This tool can perform active scanning (ZAP baseline, broken-link crawling). Only run it against sites you own or have explicit written permission to test. Unauthorized scanning may be illegal and can trigger abuse alerts.
