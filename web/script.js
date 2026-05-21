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

async function runSqlQuery() {
    const n = parseInt($('sql-query-select').value);
    const btn = $('sql-run-btn');
    const result = $('sql-result');
    btn.textContent = '⏳ Running...';
    btn.disabled = true;
    result.textContent = '';
    try {
        const res = await fetch(`/api/sql-practice/query/${n}`, { signal: AbortSignal.timeout(10000) });
        if (res.status !== 200) { result.textContent = `Error ${res.status}`; return; }
        const d = await res.json();
        let out = `-- ${d.query.split('\n')[0].replace('-- ', '')}\n`;
        if (d.result && d.result.data) {
            for (const row of d.result.data.slice(0, 20)) {
                out += row.join(' │ ') + '\n';
            }
            if (d.result.data.length > 20) out += `... (${d.result.data.length} rows)`;
        }
        if (d.explain && d.explain.data) {
            out += '\n-- EXPLAIN:\n';
            for (const row of d.explain.data) {
                out += row.join(' ') + '\n';
            }
        }
        result.textContent = out;
    } catch(e) {
        result.textContent = `Error: ${e.message}`;
    }
    btn.textContent = '▶ Run Query';
    btn.disabled = false;
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

async function checkAll() {
    const now = new Date().toLocaleTimeString();

    for (const check of CHECKS) {
        setStatus(check.id, 'loading', 'Checking...');
        try {
            const res = await fetch(check.url, { signal: AbortSignal.timeout(5000) });
            setStatus(check.id, check.ok(res) ? 'online' : 'offline', check.ok(res) ? 'Online' : `Error ${res.status}`);
        } catch { setStatus(check.id, 'offline', 'Offline'); }
    }

    await Promise.all([checkWebMetrics(), checkDbMetrics(), checkDnsMetrics(), checkSqlStatus(), checkGrafana(), checkRedis(), checkRedisMetrics(), checkElk()]);

    $('last-checked').textContent = now;
}

checkAll();
setInterval(checkAll, 10000);

$('sql-run-btn').addEventListener('click', runSqlQuery);
