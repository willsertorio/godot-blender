// Runs the browser build (build/site/play) in headless Chromium and drives it: for checking the web export here.
//   node tools/web_run.js OUTDIR [--args="--play --seed=33"] [--size=960x540] [--steps="wait:6,shot:title,key:Enter,wait:20,shot:game"]
// Steps: wait:SECONDS, shot:NAME (OUTDIR/NAME.png), key:KEY (press), down:KEY / up:KEY, click (at the middle),
// move:DX,DY (mouse), eval:JS, size:WxH (the window); with --frame (the game in an iframe): hide, show, css:STYLE. The game's prints and errors go to OUTDIR/console.log.
// The game's command line (what follows "--" on the desktop) is given with --args: the page's GODOT_CONFIG.args.
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const out = process.argv[2] || 'captures/web';
const opt = Object.fromEntries(process.argv.slice(3).map(a => { const i = a.indexOf('='); return [a.slice(2, i < 0 ? undefined : i), i < 0 ? '1' : a.slice(i + 1)]; }));
const [W, H] = (opt.size || '960x540').split('x').map(Number);
const steps = (opt.steps || 'wait:8,shot:title').split(',').map(s => s.trim()).filter(Boolean);
const root = path.resolve(opt.dir || 'build/site/play');
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
fs.mkdirSync(out, { recursive: true });
const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]); if (p === '/') p = '/index.html';
  if (p === '/__frame') {                            // --frame: the game in an iframe, as the site has it
    res.writeHead(200, { 'Content-Type': 'text/html' });
    return res.end('<!doctype html><body style="margin:0;background:#123"><iframe id="g" src="/" allow="autoplay; fullscreen" style="border:0;width:100vw;height:100vh;display:block"></iframe></body>');
  }
  const f = path.join(root, p);
  if (!f.startsWith(root) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  let body = fs.readFileSync(f);
  if (p === '/index.html' && opt.args) {          // the game's own arguments
    const args = JSON.stringify(['--'].concat(opt.args.split(' ').filter(Boolean)));   // (what follows "--" is the game's)
    body = Buffer.from(body.toString().replace(/"args":\[[^\]]*\]/, '"args":' + args));
  }
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' }); res.end(body);
});
(async () => {
  await new Promise(r => server.listen(0, r));
  const url = 'http://localhost:' + server.address().port + '/';
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  const log = fs.createWriteStream(path.join(out, 'console.log'));
  const t0 = Date.now();
  page.on('console', m => log.write(`[${((Date.now() - t0) / 1000).toFixed(1)}] ${m.type()}: ${m.text()}\n`));
  page.on('pageerror', e => log.write(`[${((Date.now() - t0) / 1000).toFixed(1)}] PAGEERROR: ${e.message}\n`));
  if (opt.probe) await page.addInitScript(opt_interval => {
    // --probe: what a frame costs on the page's one thread. Every WebGL call is counted and timed (the time is the
    // call itself: encoding it for the GPU process, not its execution there), and so is the whole of each frame's
    // callback (the engine's main loop: scripts, physics, culling, draw submission). Printed once a second.
    const P = { calls: 0, ms: 0, by: {}, frames: 0, cb: 0, worst: 0, seen: 0, traced: false };
    const wrap = proto => { for (const k of Object.getOwnPropertyNames(proto)) {
      const d = Object.getOwnPropertyDescriptor(proto, k);
      if (!d || typeof d.value !== 'function' || k === 'constructor') continue;
      const f = d.value;
      proto[k] = function (...a) { if (k === 'getParameter' && a[0] === 0xc11 && !P.traced && P.seen++ > 40) { P.traced = true; console.log('[probe] getParameter(SCISSOR_TEST) from: ' + new Error().stack.split('\n').slice(1, 14).map(l => l.trim().replace(/https?:\/\/[^/]+\//, '')).join(' <- ')); } const t = performance.now(); try { return f.apply(this, a); } finally { const e = performance.now() - t; P.calls++; P.ms += e; const n = (k === 'getParameter' || k === 'getQueryParameter' || k === 'getError' || k === 'readPixels' || k === 'clientWaitSync' || k === 'finish') ? k + '(0x' + Number(a[a.length > 1 ? 1 : 0] || 0).toString(16) + ')' : k; const b = P.by[n] || (P.by[n] = [0, 0]); b[0]++; b[1] += e; } };
    } };
    wrap(WebGL2RenderingContext.prototype);
    const raf = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = cb => raf(ts => { const t = performance.now(); try { cb(ts); } finally { const e = performance.now() - t; P.frames++; P.cb += e; if (e > P.worst) P.worst = e; } });
    setInterval(() => {
      if (!P.frames) return;
      const top = Object.entries(P.by).sort((a, b) => b[1][1] - a[1][1]).slice(0, 9).map(([k, v]) => `${k} ${(v[0] / P.frames).toFixed(0)}x ${(v[1] / P.frames).toFixed(2)}ms`).join(', ');
      console.log(`[probe] frames ${P.frames}  callback ${(P.cb / P.frames).toFixed(1)} ms a frame (worst ${P.worst.toFixed(0)})  GL calls ${(P.calls / P.frames).toFixed(0)} a frame taking ${(P.ms / P.frames).toFixed(1)} ms  | ${top}`);
      P.calls = 0; P.ms = 0; P.by = {}; P.frames = 0; P.cb = 0; P.worst = 0;
    }, opt_interval);
  }, 1000 * (parseFloat(opt.probe) || 5));
  await page.goto(opt.frame ? url + '__frame' : url);
  for (const s of steps) {
    const i = s.indexOf(':'); const k = i < 0 ? s : s.slice(0, i); const v = i < 0 ? '' : s.slice(i + 1);
    if (k === 'wait') await page.waitForTimeout(parseFloat(v) * 1000);
    else if (k === 'shot') await page.screenshot({ path: path.join(out, v + '.png'), timeout: 120000 }).catch(e => log.write('screenshot ' + v + ' failed: ' + String(e).split('\n')[0] + '\n'));
    else if (k === 'key') await page.keyboard.press(v);
    else if (k === 'down') await page.keyboard.down(v);
    else if (k === 'up') await page.keyboard.up(v);
    else if (k === 'click') await page.mouse.click(W / 2, H / 2);
    else if (k === 'size') { const [w, h] = v.split('x').map(Number); await page.setViewportSize({ width: w, height: h }); }
    else if (k === 'hide' || k === 'show') await page.evaluate(d => { document.getElementById('g').style.display = d; }, k === 'hide' ? 'none' : 'block');
    else if (k === 'css') await page.evaluate(c => { document.getElementById('g').style.cssText += ';' + c; }, v);
    else if (k === 'move') { const [dx, dy] = v.split('/').map(Number); await page.mouse.move(W / 2 + dx, H / 2 + dy, { steps: 6 }); }
    else if (k === 'eval') log.write('eval: ' + JSON.stringify(await page.evaluate(v)) + '\n');
    else if (k === 'lock') log.write('pointer lock element: ' + (await page.evaluate(() => document.pointerLockElement ? document.pointerLockElement.tagName : 'none')) + '\n');
  }
  await browser.close(); server.close(); log.end();
})().catch(e => { console.error(e); process.exit(1); });
