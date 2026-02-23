const SUPABASE_URL = 'https://mycgdissxzsizoywcwps.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im15Y2dkaXNzeHpzaXpveXdjd3BzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxNzkyNDEsImV4cCI6MjA4NTc1NTI0MX0.1-3qDwNwFeqlHjn-jCACOtV5U2yhgEsQ1yUM-m2TKZg';

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: 'dispatch-orbit-auth-v1' }
});
const focusJobId = new URLSearchParams(location.search).get('job_id') || '';

const cancelReasons = [
  ['client_request', 'Client request'],
  ['no_access', 'No access'],
  ['traffic_driving', 'Traffic / driving'],
  ['too_far', 'Too far'],
  ['parts_missing', 'Parts missing'],
  ['weather', 'Weather'],
  ['other', 'Other']
];

function qs(id) { return document.getElementById(id); }
function esc(v) { return String(v || '').replace(/[&<>\"]/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m])); }
function fmtPostal(v) { const s = String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, ''); return /^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$/.test(s) ? `${s.slice(0,3)} ${s.slice(3)}` : ''; }
function todayIso() { return new Date().toISOString().slice(0, 10); }

async function rpc(name, args) {
  const { data, error } = await sb.rpc(name, args || {});
  return { data, error };
}

async function loadChecklist(jobId) {
  await rpc('dispatch_v2_ensure_job_checklist', { p_job_id: jobId });
  const { data, error } = await sb.from('dispatch_v2_job_checklist_items')
    .select('id,segment,sort_order,label,is_required,completed')
    .eq('job_id', jobId)
    .order('sort_order', { ascending: true });
  if (error) return [];
  return data || [];
}

async function pickCancelReason() {
  return new Promise((resolve) => {
    const modal = document.createElement('div');
    modal.style.cssText = 'position:fixed;inset:0;z-index:9999;display:flex;align-items:center;justify-content:center;padding:12px;background:rgba(0,0,0,.28)';
    modal.innerHTML = `
      <div class="card" style="width:min(480px,92vw)">
        <h3 style="margin-bottom:8px">Cancel reason</h3>
        <select id="cancelCode">${cancelReasons.map(([code, label]) => `<option value="${code}">${label}</option>`).join('')}</select>
        <textarea id="cancelNote" placeholder="Optional note"></textarea>
        <div class="onsite-actions">
          <button class="btn ghost" id="cancelClose" type="button">Close</button>
          <button class="btn" id="cancelApply" type="button">Apply</button>
        </div>
      </div>`;
    modal.querySelector('#cancelClose').onclick = () => { modal.remove(); resolve(null); };
    modal.querySelector('#cancelApply').onclick = () => {
      const code = modal.querySelector('#cancelCode').value;
      const note = modal.querySelector('#cancelNote').value || '';
      modal.remove();
      resolve({ code, note });
    };
    document.body.appendChild(modal);
  });
}

async function loadJobs() {
  const host = qs('jobs');
  host.innerHTML = '<div class="card muted">Loading...</div>';
  const mode = qs('dateMode').value;
  const args = mode === 'today'
    ? { p_from: todayIso(), p_to: todayIso(), p_include_cancelled: true }
    : { p_include_cancelled: true };
  const { data, error } = await rpc('dispatch_v2_list_visible_jobs', args);
  if (error) { host.innerHTML = `<div class="card muted">Load failed: ${esc(error.message)}</div>`; return; }
  const jobs = Array.isArray(data) ? data : [];
  const filteredJobs = focusJobId ? jobs.filter((j) => String(j.id) === String(focusJobId)) : jobs;
  if (!filteredJobs.length) { host.innerHTML = '<div class="card muted">No jobs.</div>'; return; }

  host.innerHTML = '';
  for (const j of filteredJobs) {
    const card = document.createElement('article');
    card.className = 'onsite-card';
    const checklist = await loadChecklist(j.id);
    const grouped = checklist.reduce((acc, it) => { acc[it.segment] = acc[it.segment] || []; acc[it.segment].push(it); return acc; }, {});
    const checklistHtml = Object.keys(grouped).map((seg) => `
      <div class="segment">
        <div class="segment-title">${esc(seg)}</div>
        ${grouped[seg].map((it) => `<label><input type="checkbox" data-item="${it.id}" ${it.completed ? 'checked' : ''}/> ${esc(it.label)}${it.is_required ? ' *' : ''}</label>`).join('')}
      </div>`).join('');

    card.innerHTML = `
      <div class="job-row">
        <b>WO ${esc(j.work_order)}</b>
        <span class="status ${esc(j.status)}">${esc(String(j.status || '').toUpperCase())}</span>
      </div>
      <div class="muted">${esc(j.scheduled_date)} ${esc(j.scheduled_slot)} | ${esc(j.primary_assignee || '-')} | ${esc(j.client_code)}</div>
      <div class="muted">${esc(j.address || '')} ${fmtPostal(j.postal_code) ? '| ' + esc(fmtPostal(j.postal_code)) : ''}</div>
      <div class="onsite-actions">
        <button class="btn ghost" data-act="start">Start</button>
        <button class="btn ghost" data-act="end">End session</button>
        <button class="btn" data-act="done">Mark complete</button>
        <button class="btn ghost" data-act="cancel">${j.status === 'cancelled' ? 'Restore' : 'Cancel'}</button>
      </div>
      <div class="checklist">${checklistHtml || '<div class="muted">No checklist</div>'}</div>
      <div class="checklist">
        <div class="segment-title">Important note</div>
        <textarea id="note-${j.id}" placeholder="Write clear onsite note for manager"></textarea>
        <div class="onsite-actions"><button class="btn ghost" data-act="note">Save note</button></div>
      </div>
    `;

    card.querySelector('[data-act="start"]').onclick = async () => {
      const r = await rpc('dispatch_v2_start_job', { p_job_id: j.id, p_note: null });
      if (r.error) return alert(r.error.message);
      loadJobs();
    };
    card.querySelector('[data-act="end"]').onclick = async () => {
      const r = await rpc('dispatch_v2_end_session', { p_job_id: j.id, p_note: null });
      if (r.error) return alert(r.error.message);
      loadJobs();
    };
    card.querySelector('[data-act="done"]').onclick = async () => {
      if (!confirm('Mark as completed?')) return;
      const r = await rpc('dispatch_v2_mark_completed', { p_job_id: j.id, p_note: null });
      if (r.error) return alert(r.error.message);
      loadJobs();
    };
    card.querySelector('[data-act="cancel"]').onclick = async () => {
      if (j.status === 'cancelled') {
        const r = await rpc('dispatch_v2_set_cancelled', { p_job_id: j.id, p_cancelled: false, p_reason_code: null, p_reason_note: null });
        if (r.error) return alert(r.error.message);
        return loadJobs();
      }
      const sel = await pickCancelReason();
      if (!sel) return;
      if (!cancelReasons.find((x) => x[0] === sel.code)) return alert('Invalid reason');
      const r = await rpc('dispatch_v2_set_cancelled', { p_job_id: j.id, p_cancelled: true, p_reason_code: sel.code, p_reason_note: sel.note || null });
      if (r.error) return alert(r.error.message);
      loadJobs();
    };
    card.querySelector('[data-act="note"]').onclick = async () => {
      const note = String(card.querySelector(`#note-${j.id}`).value || '').trim();
      if (!note) return alert('Type a note first');
      const r = await rpc('dispatch_v2_add_note', { p_job_id: j.id, p_note: note });
      if (r.error) return alert(r.error.message);
      card.querySelector(`#note-${j.id}`).value = '';
      alert('Saved');
    };

    card.querySelectorAll('input[type="checkbox"][data-item]').forEach((cb) => {
      cb.onchange = async () => {
        const r = await rpc('dispatch_v2_toggle_checklist_item', { p_item_id: cb.getAttribute('data-item'), p_completed: !!cb.checked, p_note: null });
        if (r.error) { cb.checked = !cb.checked; alert(r.error.message); }
      };
    });

    host.appendChild(card);
  }
}

async function afterSignIn(user) {
  const { data, error } = await rpc('dispatch_v2_current_profile');
  if (error) return alert(error.message);
  const p = Array.isArray(data) ? data[0] : null;
  qs('authStatus').textContent = `Signed in: ${user.email || ''}${p ? ` | ${p.display_name} (${p.role})` : ''}`;
  qs('loginForm').style.display = 'none';
  qs('btnLogout').style.display = '';
  if(focusJobId){
    qs('dateMode').value = 'all';
    qs('dateMode').disabled = true;
  }
  await loadJobs();
}

qs('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const { data, error } = await sb.auth.signInWithPassword({ email: qs('email').value.trim(), password: qs('password').value });
  if (error) return alert(error.message);
  afterSignIn(data.user);
});

qs('btnLogout').onclick = async () => { await sb.auth.signOut(); location.reload(); };
qs('btnReload').onclick = () => loadJobs();
qs('dateMode').onchange = () => loadJobs();

(async () => {
  const { data } = await sb.auth.getUser();
  if (data?.user) await afterSignIn(data.user);
})();
