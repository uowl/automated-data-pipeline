<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Admin</title>
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
    <p>Automated Data Pipeline — Admin</p>
  </header>

  <p><a href="${pageContext.request.contextPath}/">← Back to runs</a></p>
  <h2 style="margin: 0 0 1rem;">Admin</h2>

  <div class="card">
    <h3 style="margin: 0 0 0.5rem; font-size: 1rem;">Running status check (6h timeout)</h3>
    <p style="margin: 0 0 0.75rem; color: #71767b; font-size: 0.875rem;">Check all runs with status <strong>Running</strong>. Any run that has been running for more than 6 hours will be marked as <strong>Failed-TimeOut-6Hours</strong>.</p>
    <button type="button" id="checkRunningBtn" style="padding: 0.5rem 1rem; cursor: pointer; background: #1d9bf0; color: #fff; border: none; border-radius: 4px; font-size: 0.9rem;">Check running status now</button>
    <p id="checkResult" style="margin: 0.75rem 0 0; font-size: 0.875rem; display: none;"></p>
    <p id="checkError" class="error-msg" style="margin: 0.75rem 0 0; display: none;"></p>
  </div>

  <script>
    var API = '<%= request.getContextPath() %>/api';
    document.getElementById('checkRunningBtn').addEventListener('click', function() {
      var btn = this;
      var resultEl = document.getElementById('checkResult');
      var errEl = document.getElementById('checkError');
      errEl.style.display = 'none';
      resultEl.style.display = 'none';
      btn.disabled = true;
      btn.textContent = 'Checking…';
      fetch(API + '/admin/check-running-status', { method: 'POST' })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          resultEl.style.display = 'block';
          if (data.error) {
            resultEl.textContent = '';
            errEl.textContent = data.error;
            errEl.style.display = 'block';
          } else {
            var n = data.markedTimeout != null ? data.markedTimeout : 0;
            var ids = data.runIdsMarked || [];
            resultEl.textContent = 'Done. Runs marked as Failed-TimeOut-6Hours: ' + n + (ids.length ? ' (' + ids.join(', ') + ')' : '');
            resultEl.style.color = n > 0 ? '#f4212e' : '#71767b';
          }
        })
        .catch(function() {
          errEl.textContent = 'Request failed';
          errEl.style.display = 'block';
        })
        .finally(function() {
          btn.disabled = false;
          btn.textContent = 'Check running status now';
        });
    });
  </script>
</body>
</html>
