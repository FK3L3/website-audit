/**
 * Reads the most recent audit run from reports/ and writes a markdown
 * summary to GITHUB_STEP_SUMMARY (or stdout when run locally).
 */
import { readFileSync, existsSync, readdirSync, statSync, appendFileSync } from 'fs';
import { join } from 'path';

const reportsDir = join(process.cwd(), 'reports');
if (!existsSync(reportsDir)) process.exit(0);

const runId = readdirSync(reportsDir)
  .filter((d) => statSync(join(reportsDir, d)).isDirectory())
  .sort()
  .at(-1);

if (!runId) process.exit(0);

const runDir = join(reportsDir, runId);
const url    = process.env.AUDIT_URL ?? '(unknown)';
const lines  = [];

const read = (file) => readFileSync(join(runDir, file), 'utf8');

// ── Header ────────────────────────────────────────────────────────────
lines.push(`## 🔍 Website Audit — ${url}`);
lines.push('');

// ── Lighthouse scores ─────────────────────────────────────────────────
const lhPath = join(runDir, 'lighthouse', 'report.report.json');
if (existsSync(lhPath)) {
  const j = JSON.parse(readFileSync(lhPath, 'utf8'));
  const c = j.categories;
  const fmt = (cat) => {
    const n = Math.round(cat.score * 100);
    const dot = n >= 90 ? '🟢' : n >= 50 ? '🟡' : '🔴';
    return `${dot} **${n}**`;
  };
  lines.push('### Lighthouse');
  lines.push('');
  lines.push('| Performance | Accessibility | Best Practices | SEO |');
  lines.push('|:-----------:|:-------------:|:--------------:|:---:|');
  lines.push(`| ${fmt(c.performance)} | ${fmt(c.accessibility)} | ${fmt(c['best-practices'])} | ${fmt(c.seo)} |`);
  lines.push('');
}

// ── Checks table ──────────────────────────────────────────────────────
lines.push('### Checks');
lines.push('');
lines.push('| Check | Result |');
lines.push('|-------|--------|');

try {
  const t = read('pa11y.txt');
  lines.push(`| Pa11y (WCAG2AA) | ${t.includes('No issues found') ? '✅ Pass' : '❌ Issues found'} |`);
} catch {
  lines.push('| Pa11y | ⚠️ Not run |');
}

try {
  const t  = read('broken-links.txt');
  const m  = t.match(/(\d+) broken/);
  const n  = m ? parseInt(m[1], 10) : 0;
  lines.push(`| Broken links | ${n === 0 ? '✅ None' : `❌ ${n} broken`} |`);
} catch {
  lines.push('| Broken links | ⚠️ Not run |');
}

try {
  const t = read('smoke.txt');
  lines.push(`| Playwright smoke | ${t.includes('Issues found:') ? '❌ Issues detected' : '✅ Clean'} |`);
} catch {
  lines.push('| Playwright smoke | ⚠️ Not run |');
}

// ── Security (only when --security was used) ──────────────────────────
const secPath = join(runDir, 'security.txt');
if (existsSync(secPath)) {
  try {
    const t       = readFileSync(secPath, 'utf8');
    const missing = (t.match(/^missing_headers:\s*(\d+)/m) ?? [])[1] ?? '?';
    const days    = (t.match(/^cert_days_left:\s*(\d+)/m)  ?? [])[1];
    lines.push(`| Security headers | ${missing === '0' ? '✅ All present' : `⚠️ ${missing} missing`} |`);
    if (days) {
      lines.push(`| TLS certificate | ${parseInt(days) > 30 ? '✅' : '⚠️'} ${days} days remaining |`);
    }
  } catch {
    lines.push('| Security | ⚠️ Error reading results |');
  }
}

// ── Footer ────────────────────────────────────────────────────────────
lines.push('');
lines.push(`> Run ID: \`${runId}\` · Full Lighthouse report and screenshot available in **Artifacts** above.`);

const output = lines.join('\n') + '\n';

if (process.env.GITHUB_STEP_SUMMARY) {
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, output);
} else {
  process.stdout.write(output);
}
