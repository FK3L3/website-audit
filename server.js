import express from 'express';
import { spawn } from 'child_process';
import { existsSync, readFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.PORT ?? 3000;
const SCRIPT = path.join(__dirname, 'audit.sh');
const REPORTS_DIR = path.join(__dirname, 'reports');

// runId → { lines, exitCode, clients }
const runs = new Map();

function makeRunId() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
app.use('/reports', express.static(REPORTS_DIR));

app.post('/api/run', (req, res) => {
  const { url, summary, security } = req.body ?? {};

  try { new URL(url); } catch {
    return res.status(400).json({ error: 'Invalid URL' });
  }
  if (!/^https?:\/\//.test(url)) {
    return res.status(400).json({ error: 'URL must start with http:// or https://' });
  }

  const runId = makeRunId();
  const state = { lines: [], exitCode: null, clients: new Set() };
  runs.set(runId, state);

  const scriptArgs = [];
  if (summary) scriptArgs.push('--summary');
  if (security) scriptArgs.push('--security');
  scriptArgs.push(url);

  const proc = spawn('bash', [SCRIPT, ...scriptArgs], {
    cwd: __dirname,
    env: { ...process.env, AUDIT_TS: runId },
  });

  const emit = (type, data) => {
    const chunk = `event: ${type}\ndata: ${JSON.stringify(data)}\n\n`;
    state.lines.push(chunk);
    for (const client of state.clients) client.write(chunk);
  };

  const onData = (chunk, isErr) => {
    for (const line of chunk.toString().split('\n')) {
      if (line.trim()) emit('log', { text: line, err: isErr });
    }
  };

  proc.stdout.on('data', (c) => onData(c, false));
  proc.stderr.on('data', (c) => onData(c, true));
  proc.on('close', (code) => {
    state.exitCode = code ?? 0;
    emit('done', { exitCode: state.exitCode, runId });
    for (const client of state.clients) client.end();
    state.clients.clear();
  });

  res.json({ runId });
});

app.get('/api/stream/:runId', (req, res) => {
  const state = runs.get(req.params.runId);
  if (!state) return res.status(404).end();

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });

  for (const chunk of state.lines) res.write(chunk);

  if (state.exitCode !== null) return res.end();

  state.clients.add(res);
  req.on('close', () => state.clients.delete(res));
});

app.get('/api/results/:runId', (req, res) => {
  const { runId } = req.params;
  const runDir = path.join(REPORTS_DIR, runId);
  if (!existsSync(runDir)) return res.status(404).json({ error: 'Run not found' });

  const result = { runId };

  try {
    const lhPath = path.join(runDir, 'lighthouse', 'report.report.json');
    if (existsSync(lhPath)) {
      const j = JSON.parse(readFileSync(lhPath, 'utf8'));
      const c = j.categories;
      result.lighthouse = {
        performance:   Math.round(c.performance.score * 100),
        accessibility: Math.round(c.accessibility.score * 100),
        bestPractices: Math.round(c['best-practices'].score * 100),
        seo:           Math.round(c.seo.score * 100),
        reportUrl:     `/reports/${runId}/lighthouse/report.report.html`,
      };
    }
  } catch (_) {}

  try {
    const txt = readFileSync(path.join(runDir, 'pa11y.txt'), 'utf8');
    result.pa11y = { pass: txt.includes('No issues found'), text: txt.trim() };
  } catch (_) {}

  try {
    const txt = readFileSync(path.join(runDir, 'broken-links.txt'), 'utf8');
    const m = txt.match(/(\d+) broken/);
    result.brokenLinks = { count: m ? parseInt(m[1], 10) : 0, text: txt.trim() };
  } catch (_) {}

  try {
    const txt = readFileSync(path.join(runDir, 'smoke.txt'), 'utf8');
    result.smoke = {
      pass:          !txt.includes('Issues found:'),
      text:          txt.trim(),
      screenshotUrl: `/reports/${runId}/homepage.png`,
    };
  } catch (_) {}

  try {
    const txt = readFileSync(path.join(runDir, 'security.txt'), 'utf8');
    result.security = { text: txt.trim() };
  } catch (_) {}

  res.json(result);
});

app.listen(PORT, () => {
  console.log(`Website Audit  →  http://localhost:${PORT}`);
});
