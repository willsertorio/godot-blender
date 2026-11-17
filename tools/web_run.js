// Runs the browser build (build/site/play) in headless Chromium and drives it: for checking the web export here.
//   node tools/web_run.js OUTDIR [--args="--play --seed=33"] [--size=960x540] [--steps="wait:6,shot:title,key:Enter,wait:20,shot:game"]
// Steps: wait:SECONDS, shot:NAME (OUTDIR/NAME.png), key:KEY (press), down:KEY / up:KEY, click (at the middle),
// move:DX,DY (mouse), eval:JS. The game's prints and errors go to OUTDIR/console.log.
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
  const f = path.join(root, p);
  if (!f.startsWith(root) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  let body = fs.readFileSync(f);
  if (p === '/index.html' && opt.args) {          // the game's own arguments
    const args = JSON.stringify(opt.args.split(' ').filter(Boolean));
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
  await page.goto(opt.frame ? url + '__frame' : url);
  for (const s of steps) {
    const i = s.indexOf(':'); const k = i < 0 ? s : s.slice(0, i); const v = i < 0 ? '' : s.slice(i + 1);
    if (k === 'wait') await page.waitForTimeout(parseFloat(v) * 1000);
    else if (k === 'shot') await page.screenshot({ path: path.join(out, v + '.png') });
    else if (k === 'key') await page.keyboard.press(v);
    else if (k === 'down') await page.keyboard.down(v);
    else if (k === 'up') await page.keyboard.up(v);
    else if (k === 'click') await page.mouse.click(W / 2, H / 2);
    else if (k === 'move') { const [dx, dy] = v.split('/').map(Number); await page.mouse.move(W / 2 + dx, H / 2 + dy, { steps: 6 }); }
    else if (k === 'eval') log.write('eval: ' + JSON.stringify(await page.evaluate(v)) + '\n');
    else if (k === 'lock') log.write('pointer lock element: ' + (await page.evaluate(() => document.pointerLockElement ? document.pointerLockElement.tagName : 'none')) + '\n');
  }
  await browser.close(); server.close(); log.end();
})().catch(e => { console.error(e); process.exit(1); });
