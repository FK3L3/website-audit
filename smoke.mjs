import { chromium } from 'playwright';

const url = process.argv[2];
const runDir = process.argv[3];

if (!url || !runDir) {
  throw new Error('Usage: node smoke.mjs <url> <run_dir>');
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const issues = [];

page.on('console', (msg) => {
  if (msg.type() === 'error') issues.push(`console.error: ${msg.text()}`);
});

page.on('response', (res) => {
  if (res.status() >= 400) issues.push(`HTTP ${res.status()}: ${res.url()}`);
});

page.on('pageerror', (err) => {
  issues.push(`pageerror: ${err.message}`);
});

await page.goto(url, { waitUntil: 'networkidle' });
await page.screenshot({ path: `${runDir}/homepage.png`, fullPage: true });

if (issues.length) {
  console.log('Issues found:');
  for (const issue of issues) console.log(`- ${issue}`);
  process.exitCode = 1;
} else {
  console.log('No console/page/HTTP>=400 issues detected on initial load.');
}

await browser.close();
