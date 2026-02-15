# Website Audit Runner

Reusable URL audit script for:
- Lighthouse (performance, accessibility, best practices, SEO)
- Pa11y accessibility checks (WCAG2AA)
- Broken internal/external link scan
- Playwright smoke checks (console errors, page errors, HTTP 4xx/5xx)
- Optional security checks (`--security`): header presence, TLS cert, optional OWASP ZAP baseline via Docker

## Default target
`https://dropsites.biz/`

## Usage
From this folder:

```bash
chmod +x audit.sh
./audit.sh
```

Optional URL override:

```bash
./audit.sh https://example.com/
```

Summary view (scores + issue counts):

```bash
./audit.sh --summary
./audit.sh --summary https://example.com/
```

Security mode:

```bash
./audit.sh --security
./audit.sh --security --summary
./audit.sh --security --summary https://example.com/
```

## Output
Each run creates a timestamped folder in `reports/` with:
- Lighthouse HTML and JSON reports
- `pa11y.txt`
- `broken-links.txt`
- `smoke.txt`
- `homepage.png`
- `security.txt` (when `--security` is used)
- `zap.txt` and `zap/` artifacts (when `--security` and Docker are available)
