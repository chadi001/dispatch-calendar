const SUPABASE_URL = 'https://mycgdissxzsizoywcwps.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im15Y2dkaXNzeHpzaXpveXdjd3BzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxNzkyNDEsImV4cCI6MjA4NTc1NTI0MX0.1-3qDwNwFeqlHjn-jCACOtV5U2yhgEsQ1yUM-m2TKZg';

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: 'dispatch-orbit-auth-v1' }
});

function qs(id) { return document.getElementById(id); }

function renderCards(stats) {
  const host = qs('kpiGrid');
  const cards = [
    ['Total', stats.total],
    ['Scheduled', stats.scheduled],
    ['In Progress', stats.in_progress],
    ['Completed', stats.completed],
    ['Cancelled', stats.cancelled]
  ];
  host.innerHTML = cards.map(([label, value]) => `
    <article class="kpi">
      <div class="label">${label}</div>
      <div class="value">${value}</div>
    </article>`).join('');
}

function renderBreakdown(rows) {
  const byClient = {};
  for (const j of rows) {
    const c = String(j.client_code || 'UNKNOWN').toUpperCase();
    byClient[c] = byClient[c] || { total: 0, done: 0 };
    byClient[c].total += 1;
    if (j.status === 'completed') byClient[c].done += 1;
  }
  const items = Object.entries(byClient)
    .sort((a, b) => b[1].total - a[1].total)
    .map(([client, v]) => `${client}: ${v.done}/${v.total} completed`);
  qs('kpiBreakdown').innerHTML = `<h3>Client breakdown</h3><div class="muted">${items.join('<br/>') || 'No rows'}</div>`;
}

async function loadKpi() {
  const { data, error } = await sb.rpc('dispatch_v2_list_visible_jobs', { p_include_cancelled: true });
  if (error) throw error;
  const rows = Array.isArray(data) ? data : [];
  const stats = { total: rows.length, scheduled: 0, in_progress: 0, completed: 0, cancelled: 0 };
  rows.forEach((r) => {
    const k = String(r.status || 'scheduled').toLowerCase();
    if (stats[k] !== undefined) stats[k] += 1;
  });
  renderCards(stats);
  renderBreakdown(rows);
}

async function afterSignIn(user) {
  const { data, error } = await sb.rpc('dispatch_v2_current_profile');
  if (error) return alert(error.message);
  const p = Array.isArray(data) ? data[0] : null;
  qs('authStatus').textContent = `Signed in: ${user.email || ''}${p ? ` | ${p.display_name} (${p.role})` : ''}`;
  qs('loginForm').style.display = 'none';
  qs('btnLogout').style.display = '';
  await loadKpi();
}

qs('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const { data, error } = await sb.auth.signInWithPassword({ email: qs('email').value.trim(), password: qs('password').value });
  if (error) return alert(error.message);
  afterSignIn(data.user);
});

qs('btnLogout').onclick = async () => { await sb.auth.signOut(); location.reload(); };

(async () => {
  const { data } = await sb.auth.getUser();
  if (data?.user) await afterSignIn(data.user);
})();
