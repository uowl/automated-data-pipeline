<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Schedules</title>
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
    <p>Automated Data Pipeline — 4 steps: Data Pull, Extract, Transform, Migrate</p>
  </header>

  <div class="card">
    <h3 style="margin: 0 0 0.5rem; font-size: 1rem;">Add schedule</h3>
    <form id="addForm" style="display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: flex-end;">
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Name</label>
        <input type="text" id="addName" required placeholder="e.g. Daily sync">
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Type</label>
        <select id="addType">
          <option value="daily">Daily</option>
          <option value="weekly">Weekly</option>
          <option value="monthly">Monthly</option>
        </select>
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Run at (HH:mm)</label>
        <input type="time" id="addRunAt" value="09:00" required>
      </div>
      <div id="addDayOfWeekWrap" style="display: none;">
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Day of week</label>
        <select id="addDayOfWeek">
          <option value="0">Sunday</option>
          <option value="1">Monday</option>
          <option value="2">Tuesday</option>
          <option value="3">Wednesday</option>
          <option value="4">Thursday</option>
          <option value="5">Friday</option>
          <option value="6">Saturday</option>
        </select>
      </div>
      <div id="addDayOfMonthWrap" style="display: none;">
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Day of month (1–31)</label>
        <input type="number" id="addDayOfMonth" min="1" max="31" value="1" style="width: 4rem;">
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">CSV or JSON file</label>
        <input type="file" id="addFile" accept=".csv,.json" required>
      </div>
      <button type="submit" id="addBtn">Add schedule</button>
    </form>
    <p id="addError" class="error-msg" style="display: none;"></p>
  </div>

  <div class="card" id="editCard" style="display: none;">
    <h3 style="margin: 0 0 0.5rem; font-size: 1rem;">Edit schedule</h3>
    <form id="editForm" style="display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: flex-end;">
      <input type="hidden" id="editId">
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Name</label>
        <input type="text" id="editName" required placeholder="e.g. Daily sync">
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Type</label>
        <select id="editType">
          <option value="daily">Daily</option>
          <option value="weekly">Weekly</option>
          <option value="monthly">Monthly</option>
        </select>
      </div>
      <div>
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Run at (HH:mm)</label>
        <input type="time" id="editRunAt" value="09:00" required>
      </div>
      <div id="editDayOfWeekWrap" style="display: none;">
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Day of week</label>
        <select id="editDayOfWeek">
          <option value="0">Sunday</option>
          <option value="1">Monday</option>
          <option value="2">Tuesday</option>
          <option value="3">Wednesday</option>
          <option value="4">Thursday</option>
          <option value="5">Friday</option>
          <option value="6">Saturday</option>
        </select>
      </div>
      <div id="editDayOfMonthWrap" style="display: none;">
        <label style="display: block; font-size: 0.8rem; color: #71767b; margin-bottom: 0.25rem;">Day of month (1–31)</label>
        <input type="number" id="editDayOfMonth" min="1" max="31" value="1" style="width: 4rem;">
      </div>
      <button type="submit" id="editSaveBtn">Save</button>
      <button type="button" id="editCancelBtn">Cancel</button>
    </form>
    <p id="editError" class="error-msg" style="display: none;"></p>
  </div>

  <h2 style="margin: 0 0 1rem;">Scheduled runs</h2>
  <div id="loading">Loading schedules…</div>
  <div id="empty" style="display: none; color: #71767b;">No schedules. Add one above.</div>
  <table id="schedulesTable" style="display: none;">
    <thead>
      <tr>
        <th>Name</th>
        <th>Type</th>
        <th>Run at</th>
        <th>Day</th>
        <th>Next run</th>
        <th>Last run</th>
        <th>Enabled</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody id="schedulesBody"></tbody>
  </table>

  <script>
    var API = '<%= request.getContextPath() %>/api';
    var DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    function showAddTypeOptions() {
      var t = document.getElementById('addType').value;
      document.getElementById('addDayOfWeekWrap').style.display = t === 'weekly' ? 'block' : 'none';
      document.getElementById('addDayOfMonthWrap').style.display = t === 'monthly' ? 'block' : 'none';
    }
    document.getElementById('addType').addEventListener('change', showAddTypeOptions);
    showAddTypeOptions();

    function showEditTypeOptions() {
      var t = document.getElementById('editType').value;
      document.getElementById('editDayOfWeekWrap').style.display = t === 'weekly' ? 'block' : 'none';
      document.getElementById('editDayOfMonthWrap').style.display = t === 'monthly' ? 'block' : 'none';
    }
    document.getElementById('editType').addEventListener('change', showEditTypeOptions);

    document.getElementById('editCancelBtn').addEventListener('click', function() {
      document.getElementById('editCard').style.display = 'none';
    });

    document.getElementById('editForm').addEventListener('submit', function(e) {
      e.preventDefault();
      var id = document.getElementById('editId').value;
      var name = document.getElementById('editName').value.trim() || 'Schedule';
      var scheduleType = document.getElementById('editType').value;
      var runAtEl = document.getElementById('editRunAt');
      var runAtTime = runAtEl.value ? (runAtEl.value.length >= 5 ? runAtEl.value.substring(0, 5) : runAtEl.value) : '09:00';
      var body = { name: name, scheduleType: scheduleType, runAtTime: runAtTime };
      if (scheduleType === 'weekly') body.dayOfWeek = parseInt(document.getElementById('editDayOfWeek').value, 10);
      if (scheduleType === 'monthly') body.dayOfMonth = parseInt(document.getElementById('editDayOfMonth').value, 10);
      var errEl = document.getElementById('editError');
      errEl.style.display = 'none';
      fetch(API + '/schedules/' + encodeURIComponent(id), {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      }).then(function(r) {
        if (r.ok) {
          document.getElementById('editCard').style.display = 'none';
          loadSchedules();
          return;
        }
        return r.json().then(function(data) { throw new Error(data.error || 'Update failed'); });
      }).catch(function(err) {
        errEl.textContent = err.message || 'Failed to update schedule';
        errEl.style.display = 'block';
      });
    });

    function loadSchedules() {
      fetch(API + '/schedules').then(function(r) { return r.json(); }).then(function(data) {
        var list = Array.isArray(data) ? data : [];
        document.getElementById('loading').style.display = 'none';
        if (list.length === 0) {
          document.getElementById('empty').style.display = 'block';
          document.getElementById('schedulesTable').style.display = 'none';
          return;
        }
        document.getElementById('empty').style.display = 'none';
        document.getElementById('schedulesTable').style.display = 'table';
        var tbody = document.getElementById('schedulesBody');
        tbody.innerHTML = list.map(function(s) {
          var day = '—';
          if (s.ScheduleType === 'weekly' && s.DayOfWeek != null) day = DAY_NAMES[Number(s.DayOfWeek)] || ('Day ' + s.DayOfWeek);
          if (s.ScheduleType === 'monthly' && s.DayOfMonth != null) day = 'Day ' + s.DayOfMonth;
          var nextRun = s.NextRunAt ? new Date(s.NextRunAt).toLocaleString() : '—';
          var lastRun = s.LastRunAt ? new Date(s.LastRunAt).toLocaleString() : '—';
          var enabled = s.Enabled ? 'Yes' : 'No';
          var toggleLabel = s.Enabled ? 'Disable' : 'Enable';
          var runAt = (s.RunAtTime || '09:00').substring(0, 5);
          var dow = s.DayOfWeek != null ? String(s.DayOfWeek) : '';
          var dom = s.DayOfMonth != null ? String(s.DayOfMonth) : '1';
          return '<tr data-id="' + s.ScheduleId + '" data-name="' + (s.Name || '').replace(/"/g, '&quot;') + '" data-type="' + (s.ScheduleType || 'daily') + '" data-runat="' + runAt + '" data-dayofweek="' + dow + '" data-dayofmonth="' + dom + '">' +
            '<td>' + (s.Name || '') + '</td>' +
            '<td>' + (s.ScheduleType || '') + '</td>' +
            '<td>' + (s.RunAtTime || '') + '</td>' +
            '<td>' + day + '</td>' +
            '<td style="color:#71767b;font-size:0.875rem">' + nextRun + '</td>' +
            '<td style="color:#71767b;font-size:0.875rem">' + lastRun + '</td>' +
            '<td>' + enabled + '</td>' +
            '<td><button type="button" class="edit-btn">Edit</button> <button type="button" class="toggle-btn" style="background:#e6a800;color:#0d1117;" data-enabled="' + (s.Enabled ? '1' : '0') + '">' + toggleLabel + '</button> <button type="button" class="del-btn" style="background:#f4212e;color:#fff;">Delete</button></td>' +
            '</tr>';
        }).join('');

        tbody.querySelectorAll('.edit-btn').forEach(function(btn) {
          btn.addEventListener('click', function() {
            var row = btn.closest('tr');
            document.getElementById('editId').value = row.getAttribute('data-id');
            document.getElementById('editName').value = row.getAttribute('data-name') || '';
            document.getElementById('editType').value = row.getAttribute('data-type') || 'daily';
            document.getElementById('editRunAt').value = row.getAttribute('data-runat') || '09:00';
            document.getElementById('editDayOfWeek').value = row.getAttribute('data-dayofweek') || '0';
            document.getElementById('editDayOfMonth').value = row.getAttribute('data-dayofmonth') || '1';
            showEditTypeOptions();
            document.getElementById('editError').style.display = 'none';
            document.getElementById('editCard').style.display = 'block';
          });
        });
        tbody.querySelectorAll('.toggle-btn').forEach(function(btn) {
          btn.addEventListener('click', function() {
            var currentlyEnabled = btn.getAttribute('data-enabled') === '1';
            var msg = currentlyEnabled ? 'Disable this schedule?' : 'Enable this schedule?';
            if (!confirm(msg)) return;
            var row = btn.closest('tr');
            var id = row.getAttribute('data-id');
            fetch(API + '/schedules/' + encodeURIComponent(id), {
              method: 'PUT',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ enabled: !currentlyEnabled })
            }).then(function(r) { if (r.ok) loadSchedules(); });
          });
        });
        tbody.querySelectorAll('.del-btn').forEach(function(btn) {
          btn.addEventListener('click', function() {
            if (!confirm('Delete this schedule? This cannot be undone.')) return;
            var id = btn.closest('tr').getAttribute('data-id');
            fetch(API + '/schedules/' + encodeURIComponent(id), { method: 'DELETE' }).then(function(r) { if (r.ok) loadSchedules(); });
          });
        });
      }).catch(function() { document.getElementById('loading').textContent = 'Failed to load schedules.'; });
    }

    document.getElementById('addForm').addEventListener('submit', function(e) {
      e.preventDefault();
      var file = document.getElementById('addFile').files[0];
      var errEl = document.getElementById('addError');
      errEl.style.display = 'none';
      if (!file) {
        errEl.textContent = 'Please select a CSV or JSON file.';
        errEl.style.display = 'block';
        return;
      }
      var scheduleType = document.getElementById('addType').value;
      var runAtEl = document.getElementById('addRunAt');
      var runAtTime = runAtEl.value ? (runAtEl.value.length >= 5 ? runAtEl.value.substring(0, 5) : runAtEl.value) : '09:00';
      var formData = new FormData();
      formData.append('file', file);
      formData.append('name', document.getElementById('addName').value.trim() || 'Schedule');
      formData.append('scheduleType', scheduleType);
      formData.append('runAtTime', runAtTime);
      if (scheduleType === 'weekly') formData.append('dayOfWeek', document.getElementById('addDayOfWeek').value);
      if (scheduleType === 'monthly') formData.append('dayOfMonth', document.getElementById('addDayOfMonth').value);
      fetch(API + '/schedules', {
        method: 'POST',
        body: formData
      }).then(function(r) { return r.json(); }).then(function(data) {
        if (data.scheduleId) {
          document.getElementById('addName').value = '';
          document.getElementById('addFile').value = '';
          loadSchedules();
          return;
        }
        throw new Error(data.error || 'Create failed');
      }).catch(function(err) {
        errEl.textContent = err.message || 'Failed to add schedule';
        errEl.style.display = 'block';
      });
    });

    loadSchedules();
  </script>
</body>
</html>
