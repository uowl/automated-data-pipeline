<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Manual Run</title>
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

  <p><a href="${pageContext.request.contextPath}/">← Back to runs</a></p>
  <h2 style="margin: 0 0 1rem;">Trigger pipeline manually</h2>

  <div class="card">
    <h3 style="margin: 0 0 0.5rem; font-size: 1rem;">Database connection (optional)</h3>
    <p style="margin: 0 0 0.75rem; color: #71767b; font-size: 0.8rem;">Leave blank to use environment defaults.</p>
    <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 0.75rem; margin-bottom: 1rem;">
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Hostname</label>
        <input type="text" id="dbHost" name="dbHost" placeholder="localhost">
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Port</label>
        <input type="number" id="dbPort" name="dbPort" placeholder="1433" min="1" max="65535">
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Username</label>
        <input type="text" id="dbUser" name="dbUser" placeholder="sa">
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Password</label>
        <input type="password" id="dbPassword" name="dbPassword" placeholder="••••••••">
      </div>
    </div>

    <h3 style="margin: 0 0 0.5rem; font-size: 1rem;">File path on server (required)</h3>
    <form id="triggerForm" style="display: flex; gap: 0.75rem; align-items: center; flex-wrap: wrap;">
      <input type="text" id="filePath" name="filePath" placeholder="e.g. /path/to/sample_1m.csv" required style="flex: 1; min-width: 200px;">
      <input type="file" id="fileInput" accept=".csv,.json" style="display: none;">
      <button type="button" id="browseBtn">Browse</button>
      <button type="submit" id="triggerBtn">Run pipeline</button>
    </form>
    <p id="triggerError" class="error-msg" style="display: none;"></p>
    <p style="margin: 0.5rem 0 0; color: #71767b; font-size: 0.8rem;">Path to a CSV or JSON file on the server. File must have columns: OrderId, CustomerId, Amount, OrderDate.</p>
  </div>

  <script>
    var API = '<%= request.getContextPath() %>/api';
    document.getElementById('browseBtn').addEventListener('click', function() { document.getElementById('fileInput').click(); });
    document.getElementById('fileInput').addEventListener('change', function() {
      var file = this.files[0];
      if (!file) return;
      var errEl = document.getElementById('triggerError');
      errEl.style.display = 'none';
      var formData = new FormData();
      formData.append('file', file);
      fetch(API + '/pipeline/upload', { method: 'POST', body: formData }).then(function(r) { return r.json(); }).then(function(data) {
        if (data.path) {
          document.getElementById('filePath').value = data.path;
          document.getElementById('fileInput').value = '';
        } else throw new Error(data.error || 'Upload failed');
      }).catch(function(err) {
        errEl.textContent = err.message || 'Upload failed';
        errEl.style.display = 'block';
      });
    });
    document.getElementById('triggerForm').addEventListener('submit', function(e) {
      e.preventDefault();
      var path = document.getElementById('filePath').value.trim();
      var errEl = document.getElementById('triggerError');
      if (!path) { errEl.textContent = 'Please enter the file path on the server.'; errEl.style.display = 'block'; return; }
      errEl.style.display = 'none';
      var btn = document.getElementById('triggerBtn');
      btn.disabled = true;
      btn.textContent = 'Running…';
      var formData = new FormData();
      formData.append('filePath', path);
      var h = document.getElementById('dbHost').value.trim();
      var p = document.getElementById('dbPort').value.trim();
      var u = document.getElementById('dbUser').value.trim();
      var pw = document.getElementById('dbPassword').value;
      if (h) formData.append('dbHost', h);
      if (p) formData.append('dbPort', p);
      if (u) formData.append('dbUser', u);
      if (h || p || u) formData.append('dbPassword', pw || '');
      fetch(API + '/pipeline/trigger', { method: 'POST', body: formData }).then(function(r) { return r.json(); }).then(function(data) {
        if (data.runId) { window.location.href = 'run-detail.jsp?runId=' + encodeURIComponent(data.runId); return; }
        throw new Error(data.error || 'Trigger failed');
      }).catch(function(err) {
        errEl.textContent = err.message || 'Failed to trigger pipeline';
        errEl.style.display = 'block';
      }).finally(function() { btn.disabled = false; btn.textContent = 'Run pipeline'; });
    });
  </script>
</body>
</html>
