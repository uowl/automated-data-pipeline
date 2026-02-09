<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>All logs</title>
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
    </nav>
    <p>Automated Data Pipeline — 4 steps: Data Pull → Extract → Transform → Migrate</p>
  </header>

  <p><a href="${pageContext.request.contextPath}/">← Back to runs</a></p>
  <h2 style="margin: 0 0 1rem;">All pipeline logs</h2>
  <div style="display: flex; gap: 1rem; margin-bottom: 1rem; align-items: center; flex-wrap: wrap;">
    <select id="filterLevel">
      <option value="">All levels</option>
      <option value="Info">Info</option>
      <option value="Warning">Warning</option>
      <option value="Error">Error</option>
    </select>
    <select id="filterLimit">
      <option value="100">Last 100</option>
      <option value="200" selected>Last 200</option>
      <option value="500">Last 500</option>
    </select>
  </div>
  <div class="log-box" id="logsBox" style="max-height: 70vh;">
    <p style="color: #71767b;">Loading logs…</p>
  </div>

  <script>
    var API = '<%= request.getContextPath() %>/api';
    function levelClass(level) {
      if (level === 'Error') return 'log-level-error';
      if (level === 'Warning') return 'log-level-warning';
      return 'log-level-info';
    }
    function loadLogs() {
      var level = document.getElementById('filterLevel').value;
      var limit = document.getElementById('filterLimit').value;
      var url = API + '/logs?limit=' + encodeURIComponent(limit);
      if (level) url += '&level=' + encodeURIComponent(level);
      fetch(url)
        .then(function(r) { return r.json(); })
        .then(function(data) {
          var logs = Array.isArray(data) ? data.reverse() : [];
          var box = document.getElementById('logsBox');
          if (logs.length === 0) {
            box.innerHTML = '<p style="color:#71767b">No logs found. Run a pipeline to see logs.</p>';
            return;
          }
          box.innerHTML = logs.map(function(l) {
            var time = new Date(l.LogAt).toLocaleString();
            var link = '<a href="run-detail.jsp?runId=' + encodeURIComponent(l.RunId) + '" style="color:#1d9bf0;flex-shrink:0" title="' + (l.RunId || '') + '">' + (l.PipelineName || (l.RunId ? l.RunId.slice(0, 8) + '…' : '')) + '</a>';
            var step = l.StepNumber != null ? '<span style="color:#1d9bf0">Step' + l.StepNumber + '</span>' : '';
            var details = l.Details ? ' <span style="color:#71767b" title="' + (l.Details.replace(/"/g, '&quot;')) + '">' + (l.Details.length > 80 ? l.Details.slice(0, 80) + '…' : l.Details) + '</span>' : '';
            return '<div class="log-line"><span class="log-time">' + time + '</span><span class="' + levelClass(l.Level) + '" style="min-width:48px">' + (l.Level || 'Info') + '</span>' + link + step + '<span style="color:#e7e9ea">' + (l.Message || '') + '</span>' + details + '</div>';
          }).join('');
        })
        .catch(function() {
          document.getElementById('logsBox').innerHTML = '<p style="color:#71767b">Failed to load logs.</p>';
        });
    }
    document.getElementById('filterLevel').addEventListener('change', loadLogs);
    document.getElementById('filterLimit').addEventListener('change', loadLogs);
    loadLogs();
  </script>
</body>
</html>
