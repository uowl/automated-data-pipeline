<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Pipeline Monitor</title>
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

  <div style="display: flex; gap: 1rem; margin-bottom: 1rem; align-items: center;">
    <input type="text" id="filterPipeline" placeholder="Filter by pipeline name">
    <select id="filterStatus">
      <option value="">All statuses</option>
      <option value="Running">Running</option>
      <option value="Success">Success</option>
      <option value="Failed">Failed</option>
      <option value="Failed-TimeOut-6Hours">Failed (timeout 6h)</option>
    </select>
  </div>

  <div id="loading">Loading runs…</div>
  <div id="empty" style="display: none; color: #71767b;">No runs found. <a href="${pageContext.request.contextPath}/manual-run.jsp">Trigger a pipeline run</a>.</div>
  <table id="runsTable" style="display: none;">
    <thead>
      <tr>
        <th>#</th>
        <th>Pipeline</th>
        <th>Run ID</th>
        <th>Status</th>
        <th>Started</th>
        <th>Finished</th>
        <th></th>
      </tr>
    </thead>
    <tbody id="runsBody"></tbody>
  </table>

  <script>
    var API = '<%= request.getContextPath() %>/api';
    function statusClass(s) {
      if (s === 'Success') return 'status-success';
      if (s === 'Failed') return 'status-failed';
      if (s === 'Running') return 'status-running';
      if (s === 'Cancelled' || s === 'Failed-TimeOut-6Hours') return 'status-failed';
      return 'status-pending';
    }
    function loadRuns() {
      var pipeline = document.getElementById('filterPipeline').value;
      var status = document.getElementById('filterStatus').value;
      var url = API + '/runs?';
      if (pipeline) url += 'pipeline=' + encodeURIComponent(pipeline) + '&';
      if (status) url += 'status=' + encodeURIComponent(status) + '&';
      fetch(url).then(function(r) { return r.json(); }).then(function(data) {
        var runs = Array.isArray(data) ? data : [];
        document.getElementById('loading').style.display = 'none';
        if (runs.length === 0) {
          document.getElementById('empty').style.display = 'block';
          document.getElementById('runsTable').style.display = 'none';
          return;
        }
        document.getElementById('empty').style.display = 'none';
        document.getElementById('runsTable').style.display = 'table';
        var tbody = document.getElementById('runsBody');
        tbody.innerHTML = runs.map(function(r) {
          var num = r.RunNumber != null ? '#' + r.RunNumber : '—';
          var started = r.StartedAt ? new Date(r.StartedAt).toLocaleString() : '—';
          var finished = r.FinishedAt ? new Date(r.FinishedAt).toLocaleString() : '—';
          return '<tr><td class="status-pending" style="font-weight:600">' + num + '</td><td>' + (r.PipelineName || '') + '</td><td class="mono">' + (r.RunId || '') + '</td><td><span class="' + statusClass(r.Status) + '">' + (r.Status || '') + '</span></td><td style="color:#71767b;font-size:0.875rem">' + started + '</td><td style="color:#71767b;font-size:0.875rem">' + finished + '</td><td><a href="run-detail.jsp?runId=' + encodeURIComponent(r.RunId) + '">View steps</a></td></tr>';
        }).join('');
      }).catch(function() { document.getElementById('loading').textContent = 'Failed to load runs.'; });
    }
    document.getElementById('filterPipeline').addEventListener('input', loadRuns);
    document.getElementById('filterStatus').addEventListener('change', loadRuns);
    loadRuns();
  </script>
</body>
</html>
