# Website Audit

Runs Lighthouse, Pa11y (WCAG2AA), broken-link scanning, and a Playwright smoke test against any URL. Optional security mode adds HTTP header checks, TLS cert inspection, and an OWASP ZAP baseline scan.

---

## Deploy to Render (browser only, no commands needed)

Render auto-deploys the app straight from your GitHub repo. The `render.yaml` in this repo configures everything automatically.

1. Go to [render.com](https://render.com) and sign in (GitHub login works)
2. Click **New +** → **Web Service**
3. Select **Build and deploy from a Git repository** → connect this repo
4. Render detects `render.yaml` and fills in all settings automatically
5. Click **Create Web Service**
6. Wait ~5 minutes for the first build (it installs Chromium)
7. Open the URL Render gives you — the audit UI is live

Every time you push to the repo, Render redeploys automatically.

> **Free tier note:** Render's free tier spins the service down after 15 minutes of inactivity. The first request after sleep takes ~30 seconds to wake up. Upgrade to the $7/month Starter plan to keep it always on.

---

## GitHub Actions (no server needed)

Go to **Actions → Website Audit → Run workflow**, enter a URL, and click **Run**.

- Results appear in the job summary with Lighthouse score indicators (🟢/🟡/🔴) and pass/fail rows for each check
- Full Lighthouse HTML report, all result files, and a screenshot are uploaded as a downloadable artifact (30-day retention)

No setup required — just push the repo to GitHub.

---

## Run locally

**Web UI**

```bash
npm install    # first time only
npm start      # → http://localhost:3000
```

**CLI**

```bash
chmod +x audit.sh
./audit.sh [--summary] [--security] [url]
```

---

## CLI reference

| Flag | Description |
|---|---|
| `[url]` | Target URL (`http://` or `https://` required). Defaults to `https://example.com/` |
| `--summary` | Print a compact score/issue summary at the end |
| `--security` | HTTP header check, TLS cert info, optional OWASP ZAP scan |
| `-h`, `--help` | Show usage |

Flags can be combined in any order. Exit code is `0` when all checks pass, `1` when any check finds issues.

**Examples**

```bash
./audit.sh https://mysite.com/
./audit.sh --summary https://mysite.com/
./audit.sh --security --summary https://mysite.com/
```

---

## Security checks (`--security`)

| Check | Tool | Requires |
|---|---|---|
| HTTP security headers | `curl` | `curl` in PATH |
| TLS certificate expiry | `openssl` | `openssl` in PATH |
| OWASP ZAP baseline scan | Docker | Docker running |

Headers checked: `Strict-Transport-Security`, `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`.

ZAP falls back to local `zap.sh` if Docker is unavailable, and skips entirely if neither is present.

**Docker setup (Debian/Ubuntu)**

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
| `lighthouse/report.report.json` | Machine-readable scores |
| `pa11y.txt` | Accessibility issues (WCAG2AA) |
| `broken-links.txt` | Broken link scan results |
| `smoke.txt` | Console errors, page errors, HTTP 4xx/5xx |
| `homepage.png` | Full-page screenshot |
| `security.txt` | Header and TLS results (`--security` only) |
| `zap.txt`, `zap/` | ZAP output (`--security` + Docker only) |

The `reports/` directory is gitignored. On Render, reports are stored in the container and reset on each redeploy — use GitHub Actions artifacts for persistent storage.

---

## Responsible use

Only run this tool against sites you own or have explicit written permission to test. The broken-link crawler and ZAP scan make many outbound requests and may trigger abuse alerts on third-party services.
