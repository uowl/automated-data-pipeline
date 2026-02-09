<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Run detail</title>
  <link rel="stylesheet" href="${pageContext.request.contextPath}/css/style.css">
</head>
<body class="max-w">
  <header>
    <nav>
      <h1>Pipeline Monitor</h1>
      <a href="${pageContext.request.contextPath}/">Runs</a>
      <a href="${pageContext.request.contextPath}/manual-run.jsp">Manual Run</a>
      <a href="${pageContext.request.contextPath}/schedules.jsp">Schedules</a>
      <a href="${pageContext.request.contextPath}/logs.jsp">All logs</a>
      <a href="${pageContext.request.contextPath}/admin.jsp">Admin</a>
    </nav>
    <p>Automated Data Pipeline — 4 steps: Data Pull, Extract, Transform, Migrate</p>
  </header>

  <p><a href="${pageContext.request.contextPath}/">Back to runs</a></p>
  <div id="loading">Loading run…</div>
  <div id="notFound" style="display: none;">Run not found. <a href="${pageContext.request.contextPath}/">Back to list</a></div>
  <div id="content" style="display: none;">
    <div style="margin-bottom: 1.5rem;">
      <h2 id="runTitle" style="margin: 0 0 0.25rem;"></h2>
      <p id="runMeta" style="margin: 0; color: #71767b; font-size: 0.8rem;"></p>
      <p id="runStatus" style="margin: 0.5rem 0 0;"></p>
    </div>
    <h3 style="margin-bottom: 0.75rem; font-size: 1rem;">Four steps</h3>
    <div class="steps-row" id="stepsRow"></div>
    <p id="runningNote" style="margin-top: 1rem; color: #71767b; font-size: 0.875rem; display: none;">Running in background — status and logs refresh every <span id="refreshIntervalSec">30</span>s.</p>
    <p id="nextCheckNote" style="margin-top: 0.25rem; color: #71767b; font-size: 0.8rem; display: none;">Next run &amp; logs refresh in <span id="nextCheckCountdown">—</span>s.</p>
    <h3 style="margin-top: 1.5rem; margin-bottom: 0.5rem; font-size: 1rem;">Logs</h3>
    <div class="log-box" id="logsBox"><p style="color: #71767b; margin: 0; font-size: 0.875rem;">No logs yet.</p></div>
    <p id="nextCheckLogs" style="margin-top: 0.5rem; color: #71767b; font-size: 0.8rem; display: none;">Next logs refresh in <span id="nextCheckLogsCountdown">—</span>s.</p>
  </div>

  <script>
    var API = '<%= request.getContextPath() %>/api';
    var runId = new URLSearchParams(window.location.search).get('runId');
    if (!runId) {
      document.getElementById('loading').style.display = 'none';
      document.getElementById('notFound').style.display = 'block';
    } else {
      function statusClass(s) {
        if (s === 'Success') return 'status-success';
        if (s === 'Failed') return 'status-failed';
        if (s === 'Running') return 'status-running';
        if (s === 'Cancelled') return 'status-failed';
        if (s === 'Failed-TimeOut-6Hours') return 'status-failed';
        return 'status-pending';
      }
      function stepName(n) {
        return n === 1 ? 'Data Pull' : n === 2 ? 'Extract (SP)' : n === 3 ? 'Transform (SP)' : 'Migrate (SP)';
      }
      function renderStep(step, isRunning) {
        var duration = (step.StartedAt && step.FinishedAt) ? ((new Date(step.FinishedAt) - new Date(step.StartedAt)) / 1000).toFixed(1) + 's' : '';
        var cls = 'step-block' + (step.Status === 'Failed' ? ' failed' : step.Status === 'Cancelled' ? ' failed' : step.Status === 'Failed-TimeOut-6Hours' ? ' failed' : isRunning ? ' running' : '');
        var rows = '';
        if (isRunning && step.RowsProcessed != null && step.RowsTotal != null) {
          rows = '<div style="color:#71767b;font-size:0.8rem">' + Number(step.RowsProcessed).toLocaleString() + ' / ' + Number(step.RowsTotal).toLocaleString() + ' done</div>';
        } else if (isRunning && step.RowsProcessed != null) {
          rows = '<div style="color:#71767b;font-size:0.8rem">' + Number(step.RowsProcessed).toLocaleString() + ' done</div>';
        } else if (step.RowsAffected != null) {
          rows = '<div style="color:#71767b;font-size:0.8rem">' + step.RowsAffected + ' rows</div>';
        }
        var err = step.ErrorMessage ? '<div style="margin-top:0.5rem;font-size:0.75rem;color:#f4212e">' + step.ErrorMessage + '</div>' : '';
        var statusLabel = step.Status === 'Running' ? 'In Progress' : (step.Status || 'Pending');
        return '<div class="' + cls + '"><div style="font-weight:600;margin-bottom:0.25rem">' + step.StepNumber + ' — ' + (step.StepName || stepName(step.StepNumber)) + '</div><div class="' + statusClass(step.Status) + '" style="font-size:0.875rem">' + statusLabel + '</div>' + rows + (duration ? '<div style="color:#71767b;font-size:0.8rem">' + duration + '</div>' : '') + err + '</div>';
      }
      function renderRun(run) {
        document.getElementById('runTitle').textContent = run.PipelineName || 'Pipeline';
        document.getElementById('runMeta').innerHTML = (run.RunNumber != null ? '<span style="font-weight:600;margin-right:0.5rem">#' + run.RunNumber + '</span>' : '') + '<span class="mono">' + run.RunId + '</span>';
        var started = run.StartedAt ? new Date(run.StartedAt).toLocaleString() : '—';
        var cancelBtn = run.Status === 'Running' ? ' <button type="button" id="cancelRunBtn" style="margin-left:0.5rem;padding:0.25rem 0.5rem;cursor:pointer;background:#f4212e;color:#fff;border:none;border-radius:4px;font-size:0.8rem;">Cancel run</button>' : '';
        document.getElementById('runStatus').innerHTML = 'Status: <span class="' + statusClass(run.Status) + '">' + run.Status + '</span> · Started: ' + started + cancelBtn;
        var steps = run.steps || [];
        var ordered = [1,2,3,4].map(function(n) { return steps.find(function(s) { return s.StepNumber === n; }); }).filter(Boolean);
        if (ordered.length === 0) ordered = [1,2,3,4].map(function(n) { return { StepNumber: n, StepName: stepName(n), Status: 'Pending' }; });
        document.getElementById('stepsRow').innerHTML = ordered.map(function(s) { return renderStep(s, s.Status === 'Running'); }).join('');
        var note = document.getElementById('runningNote');
        if (note) note.style.display = run.Status === 'Running' ? 'block' : 'none';
      }
      function renderLogs(logs) {
        var box = document.getElementById('logsBox');
        if (!logs || logs.length === 0) { box.innerHTML = '<p style="color:#71767b;margin:0;font-size:0.875rem">No logs yet.</p>'; return; }
        function lc(l) { return l === 'Error' ? 'log-level-error' : l === 'Warning' ? 'log-level-warning' : 'log-level-info'; }
        box.innerHTML = logs.map(function(l) {
          return '<div class="log-line"><span class="log-time">' + new Date(l.LogAt).toLocaleTimeString() + '</span><span class="' + lc(l.Level) + '">' + (l.Level || 'Info') + '</span>' + (l.StepNumber != null ? '<span style="color:#1d9bf0">Step' + l.StepNumber + '</span>' : '') + '<span style="color:#e7e9ea">' + (l.Message || '') + '</span></div>';
        }).join('');
      }
      var REFRESH_INTERVAL_MS = 30000;
      var FAST_REFRESH_INTERVAL_MS = 3000;  // until step 1 is completed
      var tick;
      var countdownTick;
      var nextRefreshAt = 0;
      function step1Completed(run) {
        var steps = run.steps || [];
        var s1 = steps.find(function(s) { return s.StepNumber === 1; });
        return s1 && s1.Status !== 'Pending' && s1.Status !== 'Running';
      }
      function updateCountdown() {
        var runEl = document.getElementById('nextCheckCountdown');
        var logsEl = document.getElementById('nextCheckLogsCountdown');
        if (!runEl && !logsEl) return;
        var now = Date.now();
        if (nextRefreshAt > now) {
          var secs = Math.ceil((nextRefreshAt - now) / 1000);
          if (runEl) runEl.textContent = secs;
          if (logsEl) logsEl.textContent = secs;
        } else {
          if (runEl) runEl.textContent = '0';
          if (logsEl) logsEl.textContent = '0';
        }
      }
      function refresh() {
        fetch(API + '/runs/' + encodeURIComponent(runId)).then(function(r) { return r.ok ? r.json() : null; }).then(function(run) {
          document.getElementById('loading').style.display = 'none';
          if (!run) { document.getElementById('notFound').style.display = 'block'; return null; }
          document.getElementById('content').style.display = 'block';
          renderRun(run);
          var intervalMs = REFRESH_INTERVAL_MS;
          if (run.Status === 'Running') {
            if (!step1Completed(run)) intervalMs = FAST_REFRESH_INTERVAL_MS;
            nextRefreshAt = Date.now() + intervalMs;
            var secEl = document.getElementById('refreshIntervalSec');
            if (secEl) secEl.textContent = intervalMs === FAST_REFRESH_INTERVAL_MS ? '3' : '30';
            if (!tick) {
              var noteEl = document.getElementById('nextCheckNote');
              var logsNoteEl = document.getElementById('nextCheckLogs');
              if (noteEl) noteEl.style.display = 'block';
              if (logsNoteEl) logsNoteEl.style.display = 'block';
              if (!countdownTick) countdownTick = setInterval(updateCountdown, 1000);
            }
            tick = setTimeout(function() { tick = null; refresh(); }, intervalMs);
          } else {
            if (tick) {
              clearTimeout(tick);
              tick = null;
            }
            var noteEl = document.getElementById('nextCheckNote');
            var logsNoteEl = document.getElementById('nextCheckLogs');
            if (noteEl) noteEl.style.display = 'none';
            if (logsNoteEl) logsNoteEl.style.display = 'none';
            if (countdownTick) { clearInterval(countdownTick); countdownTick = null; }
          }
          return fetch(API + '/runs/' + encodeURIComponent(runId) + '/logs').then(function(r) { return r.ok ? r.json() : []; });
        }).then(function(data) {
          if (data != null) renderLogs(Array.isArray(data) ? data : []);
        });
      }
      document.addEventListener('click', function(e) {
        if (e.target && e.target.id === 'cancelRunBtn') {
          e.target.disabled = true;
          e.target.textContent = 'Cancelling…';
          fetch(API + '/runs/' + encodeURIComponent(runId) + '/cancel', { method: 'POST' }).then(function(r) { return r.json(); }).then(function(data) {
            if (data && data.ok) refresh();
            else if (data && data.error) alert(data.error);
          }).catch(function() { alert('Failed to cancel'); }).finally(function() {
            var btn = document.getElementById('cancelRunBtn');
            if (btn) { btn.disabled = false; btn.textContent = 'Cancel run'; }
          });
        }
      });
      refresh();
    }
  </script>
</body>
</html>
