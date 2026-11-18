// data/trajectory.json (tools/trajectory_digest.py): the user's messages, each with Claude's reply and steps.
const list = document.getElementById('turns');
const fmt = (s) => new Date(s).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'UTC' }) + ' UTC';

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

function item(t) {
  const li = el('li', 'turn');
  const btn = el('button');
  btn.setAttribute('aria-expanded', 'false');
  btn.append(el('span', 'n', String(t.n)), el('span', 'p', t.prompt + (t.images ? `\n[${t.images} image${t.images > 1 ? 's' : ''}]` : '')), el('span', 't', fmt(t.t)));
  const body = el('div', 'body');
  let filled = false;
  btn.addEventListener('click', () => {
    const open = li.classList.toggle('open');
    btn.setAttribute('aria-expanded', String(open));
    if (open && !filled) {
      filled = true;
      if (t.reply) body.append(el('div', 'reply', t.reply));
      if (t.calls && t.calls.length) {
        const ul = el('ul', 'calls');
        t.calls.forEach((c) => ul.append(el('li', null, c)));
        body.append(ul);
      }
    }
  });
  li.append(btn, body);
  return li;
}

fetch('data/trajectory.json').then((r) => r.json()).then((d) => list.append(...d.turns.map(item)));
