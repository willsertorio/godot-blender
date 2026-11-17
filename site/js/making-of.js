// The conversation: data/trajectory.json, written by tools/trajectory_digest.py from the session transcript.
const box = document.getElementById('traj');

function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v; else if (k === 'text') e.textContent = v; else e.setAttribute(k, v);
  }
  for (const k of kids) if (k != null) e.append(k);
  return e;
}

const fmtDate = (s) => new Date(s).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'UTC' }) + ' UTC';

function turnItem(t) {
  const li = el('li', { class: 'turn' });
  const btn = el('button', { 'aria-expanded': 'false' },
    el('span', { class: 'n', text: String(t.n) }),
    el('span', { class: 'p', text: t.prompt + (t.images ? `\n[${t.images} image${t.images > 1 ? 's' : ''} attached]` : '') }),
    el('span', { class: 't', text: fmtDate(t.t) }));
  const body = el('div', { class: 'body' });
  let filled = false;
  btn.addEventListener('click', () => {
    const open = li.classList.toggle('open');
    btn.setAttribute('aria-expanded', String(open));
    if (open && !filled) {
      filled = true;
      if (t.reply) body.append(el('div', { class: 'reply', text: t.reply }));
      const tools = Object.entries(t.tools || {});
      if (tools.length) {
        const p = el('p', { class: 'tools' }, 'Tools: ');
        tools.forEach(([k, v], i) => { p.append(el('code', { text: `${k.replace(/^mcp__[^_]+__/, '')} ×${v}` })); if (i < tools.length - 1) p.append(' '); });
        body.append(p);
      }
      if (t.calls && t.calls.length) {
        const ul = el('ul');
        t.calls.forEach((c) => ul.append(el('li', { text: c })));
        body.append(el('details', {}, el('summary', { text: `${t.calls.length} steps` }), ul));
      }
    }
  });
  li.append(btn, body);
  return li;
}

async function main() {
  let d;
  try {
    const r = await fetch('data/trajectory.json');
    if (!r.ok) return;
    d = await r.json();
  } catch { return; }
  box.replaceChildren();
  const days = (new Date(d.end) - new Date(d.start)) / 86400000;
  const stats = el('div', { class: 'stats traj-stats' });
  [[d.turn_count, 'messages from the designer'], [d.tool_calls.toLocaleString('en'), 'tool calls'],
   [Math.round(days * 10) / 10, 'days'], [Object.keys(d.tools).length, 'kinds of tool']]
    .forEach(([v, l]) => stats.append(el('div', {}, el('b', { text: String(v) }), el('span', { text: l }))));
  box.append(stats);
  box.append(el('p', { class: 'muted' },
    'Every message the designer typed, in order. Open one to read Claude\'s reply and the steps it took. Tool output and Claude\'s internal reasoning are left out; e-mail addresses and keys were scrubbed.'));

  const search = el('input', { type: 'search', placeholder: 'Search the messages and replies', 'aria-label': 'Search the conversation' });
  const count = el('span', { class: 'small muted' });
  box.append(el('div', { class: 'traj-tools' }, search, count));
  const list = el('ol', { class: 'turns' });
  const more = el('button', { class: 'btn btn-ghost more', type: 'button', text: 'Show more' });
  box.append(list, more);

  let shown = [];
  let limit = 40;
  function render() {
    list.replaceChildren(...shown.slice(0, limit).map(turnItem));
    more.hidden = shown.length <= limit;
    count.textContent = `${shown.length} of ${d.turns.length}`;
  }
  function filter() {
    const q = search.value.trim().toLowerCase();
    shown = q ? d.turns.filter((t) => (t.prompt + '\n' + t.reply).toLowerCase().includes(q)) : d.turns;
    limit = 40;
    render();
  }
  more.addEventListener('click', () => { limit += 60; render(); });
  let timer;
  search.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(filter, 150); });
  filter();
}
main();
