const form        = document.getElementById('form');
const urlInput    = document.getElementById('url');
const summaryChk  = document.getElementById('summary');
const securityChk = document.getElementById('security');
const runBtn      = document.getElementById('runBtn');
const logCard     = document.getElementById('logCard');
const logEl       = document.getElementById('log');
const statusText  = document.getElementById('statusText');
const pulse       = document.getElementById('pulse');
const resultsEl   = document.getElementById('results');

function scoreClass(n) {
  return n >= 90 ? 'green' : n >= 50 ? 'orange' : 'red';
}

function setCheck(iconId, subId, pass, passLabel, failLabel) {
  document.getElementById(iconId).textContent = pass ? '✅' : '❌';
  document.getElementById(subId).textContent  = pass ? passLabel : failLabel;
}

function appendLog(text, isErr) {
  const span = document.createElement('span');
  span.className = isErr ? 'log-err' : '';
  span.textContent = text + '\n';
  logEl.appendChild(span);
  logEl.scrollTop = logEl.scrollHeight;
}

function resetUI() {
  logEl.innerHTML = '';
  resultsEl.hidden = true;
  document.getElementById('scoresCard').hidden    = true;
  document.getElementById('secCard').hidden       = true;
  document.getElementById('screenshotCard').hidden = true;
  logCard.hidden = false;
  statusText.textContent = 'Running…';
  pulse.style.display = '';
  runBtn.disabled = true;
}

function renderResults(data) {
  if (data.lighthouse) {
    const labels = { performance: 'Performance', accessibility: 'Accessibility',
                     bestPractices: 'Best Practices', seo: 'SEO' };
    document.getElementById('scores').innerHTML = Object.entries(labels)
      .map(([key, label]) => {
        const val = data.lighthouse[key];
        return `<div class="score-item">
          <div class="score-ring ${scoreClass(val)}">${val}</div>
          <div class="score-label">${label}</div>
        </div>`;
      }).join('');
    document.getElementById('lhLink').href = data.lighthouse.reportUrl;
    document.getElementById('scoresCard').hidden = false;
  }

  if (data.pa11y) {
    setCheck('pa11yIcon', 'pa11ySub', data.pa11y.pass, 'No issues', 'Issues found');
  }

  if (data.brokenLinks) {
    const ok = data.brokenLinks.count === 0;
    setCheck('linksIcon', 'linksSub', ok, 'None found', `${data.brokenLinks.count} broken`);
  }

  if (data.smoke) {
    setCheck('smokeIcon', 'smokeSub', data.smoke.pass, 'Clean load', 'Issues detected');
    if (data.smoke.screenshotUrl) {
      document.getElementById('screenshot').src = data.smoke.screenshotUrl;
      document.getElementById('screenshotCard').hidden = false;
    }
  }

  if (data.security) {
    document.getElementById('secText').textContent = data.security.text;
    document.getElementById('secCard').hidden = false;
  }

  resultsEl.hidden = false;
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  resetUI();

  let runId;
  try {
    const res = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        url:      urlInput.value.trim(),
        summary:  summaryChk.checked,
        security: securityChk.checked,
      }),
    });
    const body = await res.json();
    if (!res.ok) {
      appendLog(`Error: ${body.error}`, true);
      statusText.textContent = 'Failed';
      pulse.style.display = 'none';
      runBtn.disabled = false;
      return;
    }
    runId = body.runId;
  } catch (err) {
    appendLog(`Network error: ${err.message}`, true);
    statusText.textContent = 'Failed';
    pulse.style.display = 'none';
    runBtn.disabled = false;
    return;
  }

  const src = new EventSource(`/api/stream/${runId}`);

  src.addEventListener('log', (e) => {
    const { text, err } = JSON.parse(e.data);
    appendLog(text, err);
  });

  src.addEventListener('done', async (e) => {
    src.close();
    const { exitCode } = JSON.parse(e.data);
    statusText.textContent = exitCode === 0
      ? 'Complete — no issues found'
      : 'Complete — issues detected';
    pulse.style.display = 'none';
    runBtn.disabled = false;

    const r = await fetch(`/api/results/${runId}`);
    if (r.ok) renderResults(await r.json());
  });

  src.onerror = () => {
    src.close();
    statusText.textContent = 'Connection lost';
    pulse.style.display = 'none';
    runBtn.disabled = false;
  };
});
