const SUPABASE_URL = 'https://mycgdissxzsizoywcwps.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im15Y2dkaXNzeHpzaXpveXdjd3BzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxNzkyNDEsImV4cCI6MjA4NTc1NTI0MX0.1-3qDwNwFeqlHjn-jCACOtV5U2yhgEsQ1yUM-m2TKZg';

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: 'dispatch-orbit-auth-v1' }
});
const HQ_ADDRESS = '4741 Boulevard des Laurentides #204, Laval, Quebec H7K 2Z6';

const state = { user: null, profile: null, jobs: [], month: '', selectedDate: '', editJobId: null };
const REGION_OPTIONS = [
  'Abitibi-Temiscamingue',
  'Bas-Saint-Laurent',
  'Capitale-Nationale',
  'Cote-Nord / Gaspesie',
  'Estrie',
  'Lanaudiere',
  'Laurentides',
  'Laval',
  'Mauricie',
  'Monteregie',
  'Montreal',
  'Outaouais',
  'Saguenay-Lac-Saint-Jean'
];

function qs(id) { return document.getElementById(id); }
function esc(v) { return String(v || '').replace(/[&<>\"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m])); }
function fmtPostal(v) {
  const s = String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (!/^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$/.test(s)) return '';
  return `${s.slice(0, 3)} ${s.slice(3)}`;
}
function destinationText(job) {
  return [job.address, job.city, job.province, fmtPostal(job.postal_code)].filter(Boolean).join(', ');
}
function buildMapLink(job) {
  return `https://www.google.com/maps/dir/?api=1&origin=${encodeURIComponent(HQ_ADDRESS)}&destination=${encodeURIComponent(destinationText(job))}&travelmode=driving`;
}
function buildDirectionsLink(job) {
  return `https://www.google.com/maps/dir/?api=1&origin=${encodeURIComponent(HQ_ADDRESS)}&destination=${encodeURIComponent(destinationText(job))}&travelmode=driving`;
}
function monthLabel(ym) {
  const [y, m] = String(ym || '').split('-').map(Number);
  if (!y || !m) return ym;
  return new Date(y, m - 1, 1).toLocaleDateString(undefined, { month: 'long' });
}
function inferAdminRegion(v) {
  const s = String(v || '').trim().toLowerCase();
  if (!s) return '';
  if (['montreal', 'st-laurent', 'saint-laurent', 'dorval', 'lasalle', 'anjou', 'pierrefonds', 'pointe-claire', 'kirkland', 'dollard', 'verdun', 'lachine'].some((x) => s.includes(x))) return 'Montreal';
  if (['laval'].some((x) => s.includes(x))) return 'Laval';
  if (['longueuil', 'brossard', 'chambly', 'carignan', 'saint-jean', 'st-hubert', 'saint-hubert'].some((x) => s.includes(x))) return 'Monteregie';
  if (['quebec', 'levis', 'beauport', 'charlesbourg'].some((x) => s.includes(x))) return 'Capitale-Nationale';
  if (['laurentides', 'blainville', 'mirabel', 'saint-jerome'].some((x) => s.includes(x))) return 'Laurentides';
  if (['lanaudiere', 'joliette', 'mascouche', 'repentigny'].some((x) => s.includes(x))) return 'Lanaudiere';
  if (['gatineau', 'outaouais', 'aylmer'].some((x) => s.includes(x))) return 'Outaouais';
  if (['sherbrooke', 'estrie', 'magog', 'granby'].some((x) => s.includes(x))) return 'Estrie';
  if (['saguenay', 'chicoutimi', 'alma', 'lac-saint-jean'].some((x) => s.includes(x))) return 'Saguenay-Lac-Saint-Jean';
  if (['mauricie', 'trois-rivieres', 'shawinigan'].some((x) => s.includes(x))) return 'Mauricie';
  if (['abitibi', 'temiscamingue', 'rouyn', 'val-dor'].some((x) => s.includes(x))) return 'Abitibi-Temiscamingue';
  if (['rimouski', 'bas-saint-laurent', 'riviere-du-loup'].some((x) => s.includes(x))) return 'Bas-Saint-Laurent';
  if (['gasp', 'gaspesie', 'cote-nord', 'sept-iles', 'baie-comeau'].some((x) => s.includes(x))) return 'Cote-Nord / Gaspesie';
  return '';
}
function techColor(name) {
  const s = String(name || '').trim().toLowerCase();
  if (!s) return '#94a3b8';
  let h = 0;
  for (let i = 0; i < s.length; i++) h = ((h << 5) - h) + s.charCodeAt(i);
  return ['#0ea5e9', '#22c55e', '#f97316', '#a855f7', '#ef4444', '#334155'][Math.abs(h) % 6];
}
function getJobGroup(j) {
  const n = Array.isArray(j.assignees) ? j.assignees.length : 0;
  if (!n) return 'UNASSIGNED';
  return n === 1 ? 'SOLO' : 'TEAM';
}
function monthCount(ym) { return state.jobs.filter((j) => String(j.scheduled_date || '').slice(0, 7) === ym).length; }

function applyFilters() {
  const client = qs('clientFilter').value;
  const status = qs('statusFilter').value;
  const tech = qs('techFilter').value;
  const region = qs('regionFilter').value;
  const group = qs('groupFilter').value;
  const unassignedMode = qs('unassignedFilter').value;
  return state.jobs.filter((j) => {
    if (state.month && String(j.scheduled_date || '').slice(0, 7) !== state.month) return false;
    if (client !== 'ALL' && String(j.client_code || '').toUpperCase() !== client) return false;
    if (status !== 'ALL' && String(j.status || '').toLowerCase() !== status) return false;
    if (tech !== 'ALL') {
      const names = Array.isArray(j.assignees) ? j.assignees : [];
      if (!names.some((n) => String(n || '').toLowerCase() === tech.toLowerCase())) return false;
    }
    if (region !== 'ALL' && inferAdminRegion(j.city || '') !== region) return false;
    if (group !== 'ALL') {
      const g = getJobGroup(j);
      if (group === 'SOLO' && g !== 'SOLO') return false;
      if (group === 'TEAM' && g !== 'TEAM') return false;
    }
    if (unassignedMode === 'UNASSIGNED_ONLY' && getJobGroup(j) !== 'UNASSIGNED') return false;
    return true;
  });
}
function buildDayMap(rows) {
  const out = {};
  rows.forEach((j) => {
    const iso = String(j.scheduled_date || '');
    if (!iso) return;
    out[iso] = out[iso] || [];
    out[iso].push(j);
  });
  return out;
}
function dayTintClass(jobs) {
  if (!jobs.length) return '';
  if (jobs.every((j) => j.status === 'completed')) return ' tint-complete';
  if (jobs.some((j) => getJobGroup(j) === 'UNASSIGNED')) return ' tint-unassigned';
  const clients = Array.from(new Set(jobs.map((j) => String(j.client_code || '').toUpperCase()).filter(Boolean)));
  if (clients.length > 1) return ' tint-mixed';
  if (clients[0] === 'GOCO') return ' tint-goco';
  if (clients[0] === 'MCN') return ' tint-mcn';
  return '';
}

function renderMonthTabs(months) {
  const host = qs('monthTabs');
  host.innerHTML = '';
  months.forEach((m) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'month-tab' + (state.month === m ? ' active' : '');
    b.textContent = `${monthLabel(m)} (${monthCount(m)})`;
    b.onclick = () => {
      state.month = m;
      state.selectedDate = '';
      renderMonthTabs(months);
      renderCalendar();
      renderWeekly();
      renderDayPanel([], '');
    };
    host.appendChild(b);
  });
}

function renderCalendar() {
  const rows = applyFilters();
  const dayMap = buildDayMap(rows);
  const grid = qs('calendarGrid');
  grid.innerHTML = '';
  if (!state.month) return;
  const [yy, mm] = state.month.split('-').map(Number);
  const first = new Date(yy, mm - 1, 1);
  const days = new Date(yy, mm, 0).getDate();
  const startDow = (first.getDay() + 6) % 7;
  for (let i = 0; i < startDow; i++) {
    const off = document.createElement('div');
    off.className = 'day-cell off';
    grid.appendChild(off);
  }
  for (let d = 1; d <= days; d++) {
    const iso = new Date(yy, mm - 1, d).toISOString().slice(0, 10);
    const jobs = dayMap[iso] || [];
    const completed = jobs.filter((x) => String(x.status) === 'completed').length;
    const techFreq = {};
    jobs.forEach((j) => (Array.isArray(j.assignees) ? j.assignees : []).forEach((n) => { const k = String(n || '').trim(); if (k) techFreq[k] = (techFreq[k] || 0) + 1; }));
    const topTech = Object.keys(techFreq).sort((a, b) => techFreq[b] - techFreq[a]).slice(0, 3);
    const cell = document.createElement('div');
    cell.className = 'day-cell' + dayTintClass(jobs) + (state.selectedDate === iso ? ' active' : '');
    cell.innerHTML = `<div class="day-num">${d}</div><div class="day-count">${jobs.length}</div><div class="day-meta">${completed} done</div><div class="tech-dots">${topTech.map((t) => `<span class=\"tech-dot\" title=\"${esc(t)}\" style=\"background:${techColor(t)}\"></span>`).join('')}</div>`;
    cell.onclick = () => { state.selectedDate = iso; renderCalendar(); renderDayPanel(jobs, iso); };
    grid.appendChild(cell);
  }
}

function renderWeekly() {
  const host = qs('weeklyHost');
  const rows = applyFilters();
  if (!state.month || !rows.length) {
    host.innerHTML = '<div class="muted">No weekly rows.</div>';
    qs('weeklyTitle').textContent = 'Weekly view';
    return;
  }

  const [yy, mm] = state.month.split('-').map(Number);
  const first = new Date(yy, mm - 1, 1);
  const days = new Date(yy, mm, 0).getDate();
  const startDow = (first.getDay() + 6) % 7;
  const weekCount = Math.ceil((startDow + days) / 7);
  qs('weeklyTitle').textContent = `Weekly view (${weekCount} weeks)`;

  const byDate = buildDayMap(rows);
  const weekNames = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  let html = '';
  for (let w = 0; w < weekCount; w++) {
    html += `<section class="week-block"><div class="week-label">Week ${w + 1}</div><div class="week-grid">`;
    for (let dow = 0; dow < 7; dow++) {
      const d = w * 7 + dow - startDow + 1;
      const iso = (d >= 1 && d <= days) ? new Date(yy, mm - 1, d).toISOString().slice(0,10) : '';
      const items = iso ? (byDate[iso] || []) : [];
      html += `<div class="week-col"><div class="week-col-head">${weekNames[dow]}</div><div class="week-col-body">`;
      if (!iso) {
        html += '<div class="muted">-</div>';
      } else {
        for (const j of items) {
          const tech = String(j.primary_assignee || '').trim() || 'UNASSIGNED';
          const unassigned = tech.toUpperCase() === 'UNASSIGNED';
          html += `<article class="wjob ${j.status==='completed' ? 'topline' : ''}"><div class="row1"><span class="pill">${esc(j.scheduled_slot)}</span><span class="pill ${unassigned ? 'warn' : ''}">${esc(tech)}</span><span class="pill">${esc(j.client_code || '-')}</span></div><div class="row2">${fmtPostal(j.postal_code) ? `${esc(fmtPostal(j.postal_code))} | ` : ''}WO ${esc(j.work_order || '-')}</div></article>`;
        }
      }
      html += '</div></div>';
    }
    html += '</div></section>';
  }
  host.innerHTML = html;
}

function renderDayPanel(jobs, iso) {
  qs('dayTitle').textContent = iso ? `Jobs - ${iso}` : 'Select a date';
  const host = qs('dayList');
  if (!jobs || !jobs.length) {
    host.className = 'day-list muted';
    host.textContent = 'No jobs on this date.';
    return;
  }
  host.className = 'day-list';
  host.innerHTML = jobs.map((j) => {
    const postal = fmtPostal(j.postal_code);
    const mainTech = String(j.primary_assignee || '').trim() || 'UNASSIGNED';
    const grp = getJobGroup(j);
    const isUnassigned = grp === 'UNASSIGNED';
    const canEdit = state.profile && state.profile.role === 'admin';
    return `<div class="job-card day-card ${isUnassigned ? 'is-unassigned' : ''}"><div><div class="v1-top"><span class="tiny-badge slot-chip">${esc(j.scheduled_slot)}</span><span class="tiny-badge ${isUnassigned ? 'warn-chip' : ''}">${esc(mainTech)}</span><span class="tiny-badge">${esc(j.client_code || '-')}</span><span class="muted city-chip">${esc(j.city || '')}</span></div><div class="v1-mid">${postal ? `<span class=\"tiny-badge\">${esc(postal)}</span>` : ''}<span>WO ${esc(j.work_order || '-')}</span></div><div class="muted">${esc(j.address || '')}</div><div class="muted">Status: ${esc(String(j.status || '').toUpperCase())}</div><div class="muted">Execution + checklist are available on Onsite page only.</div></div><div class="action-col"><div class="muted" style="font-weight:700">Onsite execution</div><a class="btn ghost" href="onsite.html?job_id=${encodeURIComponent(j.id)}">Onsite page</a><a class="btn ghost" target="_blank" href="${buildMapLink(j)}">Open Map</a>${canEdit ? `<button class=\"btn ghost\" data-edit=\"${j.id}\">Edit</button>` : ''}</div></div>`;
  }).join('');
  host.querySelectorAll('button[data-edit]').forEach((b) => {
    b.onclick = () => {
      const id = b.getAttribute('data-edit');
      const job = state.jobs.find((x) => String(x.id) === String(id));
      if (job) openEditModal(job);
    };
  });
}

function seedFilters() {
  const clientSel = qs('clientFilter');
  const techSel = qs('techFilter');
  const regionSel = qs('regionFilter');
  const months = Array.from(new Set(state.jobs.map((j) => String(j.scheduled_date || '').slice(0, 7)).filter(Boolean))).sort();
  const clients = Array.from(new Set(state.jobs.map((j) => String(j.client_code || '').toUpperCase()).filter(Boolean))).sort();
  const techs = Array.from(new Set(state.jobs.flatMap((j) => Array.isArray(j.assignees) ? j.assignees : []).map((x) => String(x || '').trim()).filter(Boolean))).sort();
  const regions = REGION_OPTIONS.slice();
  if (!state.month || !months.includes(state.month)) state.month = months[0] || '';
  renderMonthTabs(months);
  const cv = clientSel.value || 'ALL'; clientSel.innerHTML = `<option value="ALL">All</option>` + clients.map((c) => `<option value="${c}">${c}</option>`).join(''); clientSel.value = clients.includes(cv) ? cv : 'ALL';
  const tv = techSel.value || 'ALL'; techSel.innerHTML = `<option value="ALL">All</option>` + techs.map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join(''); techSel.value = techs.includes(tv) ? tv : 'ALL';
  const rv = regionSel.value || 'ALL'; regionSel.innerHTML = `<option value="ALL">All</option>` + regions.map((r) => `<option value="${r}">${r}</option>`).join(''); regionSel.value = regions.includes(rv) ? rv : 'ALL';
}

function openEditModal(job) {
  state.editJobId = job.id;
  qs('editTitle').textContent = `WO ${job.work_order || '-'} | ${job.scheduled_date || ''}`;
  qs('editDate').value = job.scheduled_date || '';
  qs('editSlot').value = job.scheduled_slot || 'AM';
  qs('editStatus').value = job.status || 'scheduled';
  qs('editClient').value = job.client_code || '';
  qs('editCity').value = job.city || '';
  qs('editPostal').value = fmtPostal(job.postal_code || '');
  qs('editAddress').value = job.address || '';
  qs('editModal').style.display = 'flex';
}
function closeEditModal() { state.editJobId = null; qs('editModal').style.display = 'none'; }
async function saveEditModal() {
  if (!state.editJobId) return;
  if (!state.profile || state.profile.role !== 'admin') return alert('Admin only');
  const payload = {
    scheduled_date: qs('editDate').value,
    scheduled_slot: qs('editSlot').value,
    status: qs('editStatus').value,
    client_code: String(qs('editClient').value || '').trim().toUpperCase() || null,
    city: String(qs('editCity').value || '').trim() || null,
    postal_code: String(qs('editPostal').value || '').trim() || null,
    address: String(qs('editAddress').value || '').trim() || null
  };
  const { error } = await sb.from('dispatch_v2_jobs').update(payload).eq('id', state.editJobId);
  if (error) return alert(error.message);
  closeEditModal();
  await loadJobs();
}
function findAndEditWo() {
  const wo = String(qs('woSearch').value || '').trim();
  if (!wo) return;
  const hits = state.jobs.filter((j) => String(j.work_order || '').toLowerCase().includes(wo.toLowerCase()));
  if (!hits.length) return alert('No work order found');
  const job = hits[0];
  state.month = String(job.scheduled_date || '').slice(0, 7);
  state.selectedDate = job.scheduled_date;
  seedFilters();
  renderCalendar();
  renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate);
  if (state.profile && state.profile.role === 'admin') openEditModal(job);
}

async function loadJobs() {
  const { data, error } = await sb.rpc('dispatch_v2_list_visible_jobs', { p_include_cancelled: true });
  if (error) throw error;
  state.jobs = Array.isArray(data) ? data : [];
  seedFilters();
  renderCalendar();
  renderWeekly();
  if (state.selectedDate) renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate);
}
async function loadProfile() {
  const { data, error } = await sb.rpc('dispatch_v2_current_profile');
  if (error) throw error;
  state.profile = Array.isArray(data) ? data[0] : null;
}
async function afterSignIn(user) {
  state.user = user;
  await loadProfile();
  const isAdmin = !!(state.profile && state.profile.role === 'admin');
  qs('searchZone').style.display = isAdmin ? '' : 'none';
  qs('filterZone').style.display = isAdmin ? '' : 'none';
  qs('authStatus').textContent = `Signed in: ${user.email || ''}${state.profile ? ` | ${state.profile.display_name} (${state.profile.role})` : ''}`;
  qs('loginForm').style.display = 'none';
  qs('btnLogout').style.display = '';
  await loadJobs();
}
async function restoreSession() {
  const { data } = await sb.auth.getUser();
  if (data?.user) await afterSignIn(data.user);
}

qs('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const { error, data } = await sb.auth.signInWithPassword({ email: qs('email').value.trim(), password: qs('password').value });
  if (error) return alert(error.message);
  await afterSignIn(data.user);
});
qs('btnLogout').onclick = async () => { await sb.auth.signOut(); location.reload(); };
qs('btnReload').onclick = () => loadJobs().catch((e) => alert(e.message));
qs('clientFilter').onchange = () => { renderCalendar(); renderWeekly(); if (state.selectedDate) renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate); };
qs('statusFilter').onchange = () => { renderCalendar(); renderWeekly(); if (state.selectedDate) renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate); };
qs('techFilter').onchange = () => { renderCalendar(); renderWeekly(); if (state.selectedDate) renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate); };
qs('regionFilter').onchange = () => { renderCalendar(); renderWeekly(); if (state.selectedDate) renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate); };
qs('groupFilter').onchange = () => { renderCalendar(); renderWeekly(); if (state.selectedDate) renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate); };
qs('unassignedFilter').onchange = () => { renderCalendar(); renderWeekly(); if (state.selectedDate) renderDayPanel((buildDayMap(applyFilters())[state.selectedDate] || []), state.selectedDate); };
qs('btnFindWo').onclick = findAndEditWo;
qs('btnCloseEdit').onclick = closeEditModal;
qs('btnSaveEdit').onclick = () => saveEditModal().catch((e) => alert(e.message));
qs('btnClearDay').onclick = () => { state.selectedDate = ''; renderCalendar(); renderDayPanel([], ''); };

restoreSession().catch((e) => { qs('authStatus').textContent = `Init error: ${e.message}`; });
