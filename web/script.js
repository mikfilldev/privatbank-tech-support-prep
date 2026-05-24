const CHECKS = [
    { id: 'web', url: '/', label: 'WEB', ok: (res) => res.status === 200 },
    { id: 'db', url: '/api/health/db', label: 'DB', ok: (res) => res.status === 200 },
];

function $(id) { return document.getElementById(id); }

function setStatus(id, state, msg) {
    const indicator = $(`${id}-indicator`);
    const statusEl = $(`${id}-status`);
    if (indicator) { indicator.className = 'indicator'; indicator.classList.add(state); }
    if (statusEl) { statusEl.className = 'status-text'; statusEl.classList.add(state); statusEl.textContent = msg; }
}

function setBar(id, pct) {
    const bar = $(id);
    if (!bar) return;
    bar.style.width = `${pct}%`;
    bar.className = 'metric-fill';
    if (pct > 80) bar.classList.add('danger');
    else if (pct > 60) bar.classList.add('warning');
}

function fmtMb(mb) {
    if (mb >= 1024) return `${(mb / 1024).toFixed(1)}GB`;
    return `${mb}MB`;
}

function fmtUptime(seconds) {
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (d > 0) return `${d}d ${h}h ${m}m`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
}

function applyMetrics(prefix, d) {
    setBar(`${prefix}-ram-bar`, d.mem_used_pct);
    $(`${prefix}-ram-text`).textContent = `${d.mem_used_pct}% (${fmtMb(d.mem_total_mb - d.mem_avail_mb)}/${fmtMb(d.mem_total_mb)})`;

    setBar(`${prefix}-dsk-bar`, d.disk_used_pct);
    $(`${prefix}-dsk-text`).textContent = `${d.disk_used_pct}% (${d.disk_total_gb - d.disk_free_gb}/${d.disk_total_gb}GB)`;

    $(`${prefix}-load-text`).textContent = `${d.load_1m}  ${d.load_5m}  ${d.load_15m}`;
    $(`${prefix}-uptime`).textContent = fmtUptime(d.uptime_seconds);
}

async function fetchMetrics(url) {
    try {
        const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
        if (res.status !== 200) return null;
        return await res.json();
    } catch { return null; }
}

async function checkWebMetrics() {
    const d = await fetchMetrics('/api/health/web-metrics');
    if (!d) return;
    applyMetrics('web', d);
    $(`web-nginx-text`).textContent = `${d.nginx_procs} procs · ${d.nginx_conn} conn`;
}

async function checkDbMetrics() {
    const d = await fetchMetrics('/api/health/db-metrics');
    if (!d) return;
    applyMetrics('db', d);
    $(`db-pg-text`).textContent = `${d.pg_connections} conn · ${d.process_count} proc`;
}

async function checkDnsMetrics() {
    const d = await fetchMetrics('/api/health/dns-metrics');
    if (!d) { setStatus('dns', 'offline', 'Offline'); return; }
    setStatus('dns', 'online', d.status === 'online' ? 'Online' : d.status);
    applyMetrics('dns', d);
    $(`dns-bind-text`).textContent = `${d.named_procs} proc · ${d.queries} queries`;
}

async function checkSqlStatus() {
    try {
        const res = await fetch('/api/sql-practice/', { signal: AbortSignal.timeout(5000) });
        if (res.status !== 200) { setStatus('sql', 'offline', 'Offline'); return; }
        const d = await res.json();
        setStatus('sql', 'online', `${d.database} · ${d.queries_count} queries`);
        $('sql-info').textContent = `${d.queries_count} examples`;
    } catch { setStatus('sql', 'offline', 'Offline'); }
}

let _sqlCache = {};

async function fetchSqlPreview() {
    const n = parseInt($('sql-query-select').value);
    const preview = $('sql-preview');
    if (_sqlCache[n]) {
        preview.textContent = _sqlCache[n].query;
        return;
    }
    try {
        const res = await fetch(`/api/sql-practice/query/${n}`, { signal: AbortSignal.timeout(10000) });
        if (res.status !== 200) return;
        const d = await res.json();
        _sqlCache[n] = d;
        preview.textContent = d.query;
    } catch {}
}

async function runSqlQuery() {
    const n = parseInt($('sql-query-select').value);
    const btn = $('sql-run-btn');
    const loading = $('sql-loading');
    const thead = $('sql-thead');
    const tbody = $('sql-tbody');
    const explain = $('sql-explain');
    const explainBox = $('sql-explain-box');
    const rowCount = $('sql-row-count');

    btn.textContent = '⏳';
    btn.disabled = true;
    loading.style.display = 'block';
    thead.innerHTML = '';
    tbody.innerHTML = '';
    explain.textContent = '';
    explainBox.style.display = 'none';
    rowCount.textContent = '';

    try {
        const d = _sqlCache[n] || await (await fetch(`/api/sql-practice/query/${n}`, { signal: AbortSignal.timeout(10000) })).json();
        _sqlCache[n] = d;

        // Results table
        if (d.result && d.result.data && d.result.data.length > 0) {
            // First row as header
            const headerRow = d.result.data[0];
            const dataRows = d.result.data.slice(1);

            let h = '<tr>';
            for (const col of headerRow) {
                h += `<th>${escHtml(col)}</th>`;
            }
            h += '</tr>';
            thead.innerHTML = h;

            let b = '';
            for (const row of dataRows) {
                b += '<tr>';
                for (const cell of row) {
                    b += `<td>${escHtml(cell)}</td>`;
                }
                b += '</tr>';
            }
            tbody.innerHTML = b;
            rowCount.textContent = `${dataRows.length} rows`;
        } else if (d.result && d.result.data) {
            rowCount.textContent = '0 rows';
        }

        // EXPLAIN
        if (d.explain && d.explain.data && d.explain.data.length > 0) {
            let x = '';
            for (const row of d.explain.data) {
                x += row.join(' ') + '\n';
            }
            explain.textContent = x;
            explainBox.style.display = 'block';
        }
    } catch(e) {
        tbody.innerHTML = `<tr><td style="color:#f87171;text-align:center;padding:12px;">Error: ${e.message}</td></tr>`;
    }
    btn.textContent = '▶ Run Query';
    btn.disabled = false;
    loading.style.display = 'none';
}

function escHtml(s) {
    const d = document.createElement('div');
    d.textContent = String(s);
    return d.innerHTML;
}

async function checkRedis() {
    try {
        const res = await fetch('/api/redis/', { signal: AbortSignal.timeout(5000) });
        if (res.status !== 200) { setStatus('redis', 'offline', 'Offline'); return; }
        const d = await res.json();
        setStatus('redis', 'online', `${d.version} · ${d.keys} keys`);
        $('redis-keys').textContent = `${d.keys} keys · ${d.memory}`;
        $('redis-hit').textContent = `${d.hit_rate_pct}% hit · ${d.connected_clients} clients`;
    } catch { setStatus('redis', 'offline', 'Offline'); }
}

async function checkRedisMetrics() {
    const d = await fetchMetrics('/api/redis/metrics');
    if (!d) return;
    applyMetrics('redis', d);
}

async function checkElk() {
    try {
        const [esRes, kibanaRes] = await Promise.all([
            fetch('/api/kibana/api/status', { signal: AbortSignal.timeout(5000) }),
            fetch('/api/kibana/', { signal: AbortSignal.timeout(5000) }),
        ]);
        const esOk = esRes.status === 200;
        setStatus('elk', esOk ? 'online' : 'offline', esOk ? 'ES + Kibana' : 'ES error');
        const esData = esOk ? await esRes.json() : {};
        $('elk-es-status').textContent = esOk ? `${esData.version?.number || '?'} · ${esData.status?.overall?.level || '?'}` : 'Offline';
    } catch { setStatus('elk', 'offline', 'Offline'); $('elk-es-status').textContent = 'Offline'; }
}

async function checkGrafana() {
    try {
        const res = await fetch('/api/grafana/api/health', { signal: AbortSignal.timeout(5000) });
        if (res.status !== 200) { setStatus('grafana', 'offline', 'Offline'); return; }
        const d = await res.json();
        setStatus('grafana', 'online', `${d.version} · ${d.database}`);
    } catch { setStatus('grafana', 'offline', 'Offline'); }
}

async function checkZabbix() {
    try {
        const res = await fetch('/api/zabbix/', { signal: AbortSignal.timeout(5000) });
        if (res.status !== 200) { setStatus('zabbix', 'offline', 'Offline'); return; }
        setStatus('zabbix', 'online', 'Apache + PHP');
    } catch { setStatus('zabbix', 'offline', 'Offline'); }
}

async function checkAll() {
    const now = new Date().toLocaleTimeString();

    for (const check of CHECKS) {
        setStatus(check.id, 'loading', 'Checking...');
        try {
            const res = await fetch(check.url, { signal: AbortSignal.timeout(5000) });
            setStatus(check.id, check.ok(res) ? 'online' : 'offline', check.ok(res) ? 'Online' : `Error ${res.status}`);
        } catch { setStatus(check.id, 'offline', 'Offline'); }
    }

    await Promise.all([checkWebMetrics(), checkDbMetrics(), checkDnsMetrics(), checkSqlStatus(), checkGrafana(), checkRedis(), checkRedisMetrics(), checkElk(), checkZabbix()]);

    $('last-checked').textContent = now;
}

checkAll();
setInterval(checkAll, 10000);

$('sql-run-btn').addEventListener('click', runSqlQuery);
$('sql-query-select').addEventListener('change', fetchSqlPreview);
fetchSqlPreview();
