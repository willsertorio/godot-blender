// 3D gallery: every V2 model in the game's materials, with its animation clips.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { clone as cloneSkinned } from 'three/addons/utils/SkeletonUtils.js';
import { MaterialLib, setAnisotropy, tick } from './materials.js';

const params = new URLSearchParams(location.search);
const SHOT = params.has('shot');
if (SHOT) document.body.classList.add('shot-mode');

const $ = (id) => document.getElementById(id);
const canvas = $('view');
const stage = canvas.parentElement;

// ---------------------------------------------------------------------------------- renderer
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: SHOT });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.toneMapping = THREE.AgXToneMapping;
renderer.toneMappingExposure = 1.05;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
setAnisotropy(Math.min(8, renderer.capabilities.getMaxAnisotropy()));

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.55;

const hemi = new THREE.HemisphereLight(0xf4f7f8, 0x5a6064, 0.9);
scene.add(hemi);
const key = new THREE.DirectionalLight(0xffffff, 2.6);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.bias = -0.0004;
key.shadow.normalBias = 0.02;
scene.add(key, key.target);
const rim = new THREE.DirectionalLight(0xdfefff, 1.2);
scene.add(rim);

const ground = new THREE.Mesh(new THREE.CircleGeometry(1, 64), new THREE.ShadowMaterial({ opacity: 0.22 }));
ground.rotation.x = -Math.PI / 2;
ground.receiveShadow = true;
scene.add(ground);

const camera = new THREE.PerspectiveCamera(35, 1, 0.01, 500);
const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.08;

// ---------------------------------------------------------------------------------- data
const [catalog, matData] = await Promise.all([
  fetch('data/assets.json').then((r) => r.json()),
  fetch('data/materials.json').then((r) => r.json()),
]);
const mats = new MaterialLib(matData);
const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
const files = new Map();   // file -> Promise<gltf>
const clipTables = new Map();
const items = [];
for (const g of catalog.groups) for (const it of g.items) items.push({ ...it, group: g });

function loadFile(file) {
  if (!files.has(file)) files.set(file, loader.loadAsync('models/' + file));
  return files.get(file);
}
async function clipTable(asset) {
  if (!clipTables.has(asset)) {
    clipTables.set(asset, fetch(`models/${asset}_clips.json`).then((r) => (r.ok ? r.json() : null)).catch(() => null));
  }
  return clipTables.get(asset);
}

// ---------------------------------------------------------------------------------- list UI
const list = $('list');
const pick = $('pick');
for (const g of catalog.groups) {
  const h = document.createElement('h3');
  h.textContent = g.title;
  list.append(h);
  const og = document.createElement('optgroup');
  og.label = g.title;
  for (const it of g.items) {
    const b = document.createElement('button');
    b.dataset.id = it.id;
    b.innerHTML = `<span></span>${it.kind === 'robot' || it.kind === 'view' ? '<small>animated</small>' : ''}`;
    b.firstChild.textContent = it.name;
    b.addEventListener('click', () => select(it.id));
    list.append(b);
    const o = document.createElement('option');
    o.value = it.id;
    o.textContent = it.name;
    og.append(o);
  }
  pick.append(og);
}
pick.addEventListener('change', () => select(pick.value));

// ---------------------------------------------------------------------------------- state
let current = null;     // { item, root, mixer, actions, clip, eye, kick, bounds }
let mode = 'lit';
let camMode = 'orbit';
let playing = true;
let speed = 1;
let token = 0;
const clay = new THREE.MeshStandardMaterial({ color: 0xb7bcbe, roughness: 0.62, metalness: 0 });
const wire = new THREE.MeshBasicMaterial({ color: 0x111416, wireframe: true });
const wireBase = new THREE.MeshStandardMaterial({ color: 0xe6e9ea, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: 1, polygonOffsetUnits: 1 });

function stats(root) {
  let tris = 0, verts = 0, meshes = 0;
  const m = new Set();
  root.traverse((o) => {
    if (!o.isMesh) return;
    meshes++;
    const g = o.geometry;
    verts += g.attributes.position.count;
    tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
    (Array.isArray(o.material) ? o.material : [o.material]).forEach((x) => m.add(x.name));
  });
  return { tris: Math.round(tris), verts, meshes, materials: m.size };
}

function setMode(m) {
  mode = m;
  for (const b of $('modes').children) b.setAttribute('aria-pressed', String(b.dataset.mode === m));
  if (!current) return;
  const extra = [];
  current.root.traverse((o) => {
    if (!o.isMesh || o.userData.wireCopy) return;
    if (!o.userData.lit) o.userData.lit = o.material;
    const transparent = o.userData.lit.transparent;
    if (m === 'lit') o.material = o.userData.lit;
    else if (m === 'clay') o.material = transparent ? o.userData.lit : clay;
    else o.material = transparent ? o.userData.lit : wireBase;
    if (m === 'wire' && !transparent && !o.userData.wire) extra.push(o);
    if (o.userData.wire) o.userData.wire.visible = m === 'wire';
  });
  for (const o of extra) {
    const w = o.isSkinnedMesh ? new THREE.SkinnedMesh(o.geometry, wire) : new THREE.Mesh(o.geometry, wire);
    if (o.isSkinnedMesh) w.bind(o.skeleton, o.bindMatrix);
    w.userData.wireCopy = true;
    w.raycast = () => {};
    o.add(w);
    o.userData.wire = w;
  }
}

function setCam(c) {
  camMode = c;
  for (const b of $('cams').children) b.setAttribute('aria-pressed', String(b.dataset.cam === c));
  controls.enabled = c === 'orbit';
  ground.visible = c === 'orbit' && current && current.item.kind !== 'scene';
  if (c === 'orbit') { camera.matrixAutoUpdate = true; frame(); }
  else camera.matrixAutoUpdate = false;
  resize();
}

// frame the camera on the model (front = -Z: Blender +Y faces into the room / forward)
function frame() {
  if (!current) return;
  const b = current.bounds;
  const size = b.getSize(new THREE.Vector3());
  const center = b.getCenter(new THREE.Vector3());
  const r = Math.max(size.length() * 0.5, 0.05);
  const it = current.item;
  camera.near = r / 100;
  camera.far = r * 60;
  camera.fov = 35;
  if (it.kind === 'scene') {
    controls.target.set(center.x, Math.min(b.min.y + 1.6, center.y), center.z);
    camera.position.set(center.x + size.x * 0.32, b.min.y + 2.2, center.z - size.z * 0.38);
    camera.fov = 60;
  } else {
    const dir = it.below ? new THREE.Vector3(0.55, -0.55, 1) : new THREE.Vector3(0.75, 0.42, 1);
    if (it.kind === 'view') dir.set(-0.9, 0.35, -0.6);
    const dist = r / Math.sin(THREE.MathUtils.degToRad(camera.fov * 0.5)) * 1.05;
    controls.target.copy(center);
    camera.position.copy(center).add(dir.normalize().multiplyScalar(dist));
  }
  camera.updateProjectionMatrix();
  controls.update();
  // lights follow the model's size
  key.position.copy(center).add(new THREE.Vector3(r * 2.2, r * 4, -r * 2.6));
  key.target.position.copy(center);
  const sc = key.shadow.camera;
  sc.left = sc.bottom = -r * 1.6; sc.right = sc.top = r * 1.6; sc.near = 0.01; sc.far = r * 12;
  sc.updateProjectionMatrix();
  rim.position.copy(center).add(new THREE.Vector3(-r * 3, r * 1.5, r * 3));
  ground.position.set(center.x, b.min.y - 0.001, center.z);
  ground.scale.setScalar(r * 3);
}

// ---------------------------------------------------------------------------------- select
async function select(id, { replace = false } = {}) {
  const it = items.find((x) => x.id === id) || items[0];
  const my = ++token;
  for (const b of list.querySelectorAll('button')) b.setAttribute('aria-current', String(b.dataset.id === it.id));
  pick.value = it.id;
  if (location.hash !== '#' + it.id) {
    history[replace ? 'replaceState' : 'pushState'](null, '', location.pathname + location.search + '#' + it.id);
  }
  info(it, null);
  $('loading').hidden = false;
  let gltf;
  try { gltf = await loadFile(it.file); } catch (e) { $('loading').textContent = 'Could not load ' + it.file; return; }
  if (my !== token) return;
  const asset = it.file.replace('.glb', '');

  if (current) { scene.remove(current.holder); current.mixer && current.mixer.stopAllAction(); }
  const holder = new THREE.Group();
  let root;
  let eye = null, kick = null;
  if (it.node) {
    const src = gltf.scene.getObjectByName(it.node);
    root = src.clone(true);
    root.position.set(0, 0, 0);
    holder.add(root);
  } else {
    root = cloneSkinned(gltf.scene);
    holder.add(root);
  }
  mats.apply(root, it.node ? '' : asset);
  root.traverse((o) => { if (o.isMesh) { o.castShadow = !o.material.transparent; o.receiveShadow = true; o.frustumCulled = it.kind !== 'view'; } });

  if (it.kind === 'view') {
    // Godot hangs the view from the camera through its Eye node: transform = Rx(90) * Eye^-1
    eye = root.getObjectByName('Eye');
    kick = root.getObjectByName('CamKick');
    eye.updateMatrix();
    root.matrixAutoUpdate = false;
    root.matrix.copy(new THREE.Matrix4().makeRotationX(Math.PI / 2).multiply(eye.matrix.clone().invert()));
  }
  scene.add(holder);
  holder.updateMatrixWorld(true);

  // animation clips (the export bakes one "Scene" animation; <asset>_clips.json cuts it)
  let mixer = null;
  const actions = {};
  const table = (it.kind === 'robot' || it.kind === 'view') ? await clipTable(asset) : null;
  if (my !== token) { scene.remove(holder); return; }
  if (table && gltf.animations.length) {
    mixer = new THREE.AnimationMixer(root);
    const src = gltf.animations[0];
    for (const [name, [a, b]] of Object.entries(table.clips)) {
      const loops = table.loops.includes(name);
      const clip = THREE.AnimationUtils.subclip(src, name, a, b + 1, table.fps);
      if (loops) clip.duration = (b - a + 1) / table.fps;
      actions[name] = mixer.clipAction(clip);
      actions[name].setLoop(THREE.LoopRepeat);
    }
  }

  // bounds from a still pose (first frame of the default clip)
  const startClip = it.clip && actions[it.clip] ? it.clip : Object.keys(actions)[0];
  if (startClip) { actions[startClip].play(); mixer.update(0); holder.updateMatrixWorld(true); }
  const bounds = new THREE.Box3();
  root.traverse((o) => {
    if (!o.isMesh || o.material.transparent) return;
    const s = new THREE.Vector3(); o.getWorldScale(s);
    if (s.x < 0.01) return; // hidden flash meshes
    o.geometry.computeBoundingBox();
    bounds.union(o.geometry.boundingBox.clone().applyMatrix4(o.matrixWorld));
  });

  current = { item: it, holder, root, mixer, actions, clip: startClip, eye, kick, bounds };
  $('loading').hidden = true;
  setMode(mode);

  $('cams').hidden = it.kind !== 'view';
  setCam(it.kind === 'view' ? 'player' : 'orbit');
  buildClips();
  info(it, stats(root), table);
}

function buildClips() {
  const box = $('clips');
  box.innerHTML = '';
  const names = Object.keys(current.actions);
  $('anim').hidden = names.length === 0;
  for (const n of names) {
    const b = document.createElement('button');
    b.textContent = n.replace(/([a-z])([A-Z])/g, '$1 $2');
    b.dataset.clip = n;
    b.addEventListener('click', () => playClip(n));
    box.append(b);
  }
  if (current.clip) playClip(current.clip);
}

function playClip(name) {
  const c = current;
  for (const [n, a] of Object.entries(c.actions)) { if (n !== name) a.stop(); }
  const a = c.actions[name];
  a.reset().play();
  c.clip = name;
  setPlaying(true);
  for (const b of $('clips').children) b.setAttribute('aria-pressed', String(b.dataset.clip === name));
}

function setPlaying(p) {
  playing = p;
  $('playpause').textContent = p ? '❚❚' : '▶';
  $('playpause').setAttribute('aria-label', p ? 'Pause' : 'Play');
}

function info(it, st, table) {
  $('i-group').textContent = it.group.title;
  $('i-name').textContent = it.name;
  $('i-text').textContent = it.text || it.group.blurb;
  const f = $('i-facts');
  f.innerHTML = '';
  const add = (k, v) => { const dt = document.createElement('dt'); dt.textContent = k; const dd = document.createElement('dd'); dd.textContent = v; f.append(dt, dd); };
  if (st) {
    add('Triangles', st.tris.toLocaleString('en'));
    add('Vertices', st.verts.toLocaleString('en'));
    add('Meshes', st.meshes);
    add('Materials', st.materials);
    if (current && current.bounds) {
      const s = current.bounds.getSize(new THREE.Vector3());
      add('Size', `${s.x.toFixed(2)} x ${s.y.toFixed(2)} x ${s.z.toFixed(2)} m`);
    }
    if (table) add('Clips', `${Object.keys(table.clips).length} at ${table.fps} fps`);
  }
  add('Source', it.node ? `${it.node} in set.glb` : it.file);
  $('i-script').innerHTML = '';
  const script = it.script || (it.node ? 'v2/scripts/set_structure.py, set_cover.py, set_equipment.py, set_pickups.py; export_set.py' : '');
  if (script) { $('i-script').append('Built by '); const c = document.createElement('code'); c.textContent = script; $('i-script').append(c); }
}

// ---------------------------------------------------------------------------------- controls
$('modes').addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) setMode(b.dataset.mode); });
$('cams').addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) setCam(b.dataset.cam); });
$('reset').addEventListener('click', () => { if (camMode === 'orbit') frame(); });
$('playpause').addEventListener('click', () => setPlaying(!playing));
$('speed').addEventListener('change', (e) => { speed = parseFloat(e.target.value); });
const scrub = $('scrub');
let scrubbing = false;
scrub.addEventListener('input', () => {
  if (!current || !current.clip) return;
  scrubbing = true;
  setPlaying(false);
  const a = current.actions[current.clip];
  a.time = (scrub.value / 1000) * a.getClip().duration;
  current.mixer.update(0);
});
scrub.addEventListener('change', () => { scrubbing = false; });
window.addEventListener('popstate', () => select(location.hash.slice(1), { replace: true }));
document.addEventListener('keydown', (e) => {
  if (e.target.closest('input, select, textarea')) return;
  if (e.code === 'Space' && current && current.mixer) { e.preventDefault(); setPlaying(!playing); }
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    const i = items.findIndex((x) => x.id === current?.item.id);
    const n = items[(i + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length];
    e.preventDefault();
    select(n.id);
  }
});

// ---------------------------------------------------------------------------------- loop
function resize() {
  const w = stage.clientWidth, h = stage.clientHeight;
  if (!w || !h) return;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  if (camMode === 'player') {
    // the game's camera: 80 degrees across (Godot KEEP_WIDTH)
    camera.fov = THREE.MathUtils.radToDeg(2 * Math.atan(Math.tan(THREE.MathUtils.degToRad(40)) / camera.aspect));
    camera.near = 0.01; camera.far = 50;
  }
  camera.updateProjectionMatrix();
}
new ResizeObserver(resize).observe(stage);

const clock = new THREE.Clock();
const rx = new THREE.Matrix4().makeRotationX(-Math.PI / 2);
function loop() {
  const dt = Math.min(clock.getDelta(), 0.1);
  tick(clock.elapsedTime);
  if (current && current.mixer && playing) current.mixer.update(dt * speed);
  if (current && current.clip && current.actions[current.clip] && !scrubbing) {
    const a = current.actions[current.clip];
    const d = a.getClip().duration;
    scrub.value = String(Math.round(((a.time % d) / d) * 1000));
    $('time').textContent = (a.time % d).toFixed(2) + ' s';
  }
  if (camMode === 'player' && current && current.kick) {
    current.holder.updateMatrixWorld(true);
    camera.matrix.copy(current.kick.matrixWorld).multiply(rx);
    camera.matrix.decompose(camera.position, camera.quaternion, camera.scale);
    camera.matrixWorld.copy(camera.matrix);
    camera.matrixWorldInverse.copy(camera.matrixWorld).invert();
  } else controls.update();
  renderer.render(scene, camera);
  requestAnimationFrame(loop);
}
resize();
await select(location.hash.slice(1) || params.get('id') || items[0].id, { replace: true });
if (params.has('mode')) setMode(params.get('mode'));
if (params.has('cam') && current.item.kind === 'view') setCam(params.get('cam'));
requestAnimationFrame(loop);
window.galleryReady = true;
if (params.has('debug')) window.__g = { scene, get current() { return current; }, mats, THREE };
