// The game's V2 materials, rebuilt for three.js.
// The glbs carry no images: Godot rebuilds every material by name (scripts/v2/v2_assets.gd) from
// materials.json (the Blender export) and the constants in V2Assets; data/materials.json holds both
// (tools/dump_v2_materials.gd). The custom Godot shaders (v2_worn, v2_set, v2_glove, v2_screen,
// v2_portal, v2_field, v2_flash, v2_hazard) are ported below. Colours are linear, as in Blender.
import * as THREE from 'three';

const TEX = 'textures/';
const loader = new THREE.TextureLoader();
const texCache = new Map();
let maxAniso = 8;

export function setAnisotropy(n) { maxAniso = n; }

function tex(name, srgb) {
  const key = name + (srgb ? '#s' : '');
  if (!texCache.has(key)) {
    const t = loader.load(TEX + name);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
    t.anisotropy = maxAniso;
    t.flipY = false;
    texCache.set(key, t);
  }
  return texCache.get(key);
}
const setTex = (set, kind) => tex(`${set}_${kind}.jpg`, kind === 'color');
const imperfections = () => tex('imperfections.png', false);

// ---------------------------------------------------------------------------------------------
// Shared GLSL: box projection in object space (Godot's object-space triplanar: VERTEX * (1, -1, 1),
// planes xy / xz / zy * (-1, 1)), and a normal map applied per projection plane through a
// cotangent frame built from screen-space derivatives (no mesh tangents needed).
const GLSL_COMMON = /* glsl */`
varying vec3 vObjPos;
varying vec3 vObjNrm;
mat3 v2Cotangent(vec3 N, vec3 p, vec2 uv) {
  vec3 dp1 = dFdx(p), dp2 = dFdy(p);
  vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
  vec3 dp2perp = cross(dp2, N), dp1perp = cross(N, dp1);
  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
  float m = max(dot(T, T), dot(B, B));
  float invmax = m > 0.0 ? inversesqrt(m) : 0.0;
  return mat3(T * invmax, B * invmax, N);
}
vec3 v2Weights(vec3 n, float sharp) {
  vec3 w = pow(abs(n), vec3(sharp));
  return w / max(dot(w, vec3(1.0)), 1e-5);
}
vec4 v2Tri(sampler2D s, vec3 w, vec3 p) {
  return texture(s, p.xy) * w.z + texture(s, p.xz) * w.y + texture(s, p.zy * vec2(-1.0, 1.0)) * w.x;
}
vec3 v2TriNormal(sampler2D s, vec3 w, vec3 p, vec3 N, vec3 viewPos, float strength) {
  vec3 acc = vec3(0.0);
  vec2 uvs[3];
  uvs[0] = p.zy * vec2(-1.0, 1.0); uvs[1] = p.xz; uvs[2] = p.xy;
  float ws[3];
  ws[0] = w.x; ws[1] = w.y; ws[2] = w.z;
  for (int i = 0; i < 3; i++) {
    if (ws[i] < 0.01) continue;
    vec3 t = texture(s, uvs[i]).xyz * 2.0 - 1.0;
    t.xy *= strength;
    acc += v2Cotangent(N, viewPos, uvs[i]) * t * ws[i];
  }
  return dot(acc, acc) > 0.0 ? normalize(acc) : N;
}
`;

const VERT_DECL = 'varying vec3 vObjPos;\nvarying vec3 vObjNrm;\n';
const VERT_BODY = 'vObjPos = position;\nvObjNrm = normal;\n';

function patch(mat, { uniforms = {}, fragDecl = '', diffuse, rough, metal, normal, emissive, ao, vertDecl = '', vertBody = '' }) {
  mat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, uniforms);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\n' + VERT_DECL + vertDecl)
      .replace('#include <begin_vertex>', '#include <begin_vertex>\n' + VERT_BODY + vertBody);
    let f = sh.fragmentShader.replace('#include <common>', '#include <common>\n' + GLSL_COMMON + fragDecl);
    if (diffuse) f = f.replace('#include <map_fragment>', diffuse).replace('#include <color_fragment>', '');
    if (rough) f = f.replace('#include <roughnessmap_fragment>', rough);
    if (metal) f = f.replace('#include <metalnessmap_fragment>', metal);
    if (normal) f = f.replace('#include <normal_fragment_maps>', normal);
    if (emissive) f = f.replace('#include <emissivemap_fragment>', emissive);
    if (ao) f = f.replace('#include <aomap_fragment>', ao);
    sh.fragmentShader = f;
  };
  mat.customProgramCacheKey = () => mat.name + '|' + (mat.userData.key || '');
  return mat;
}

// ---------------------------------------------------------------------------------------------
// Scanned set in a box projection (StandardMaterial3D with uv1_triplanar in Godot)
function pbr(name, d, calm) {
  const m = new THREE.MeshStandardMaterial({ name });
  const tint = new THREE.Vector3(...d.tint);
  let metallic = d.metallic, roughMul = d.rough[1], nStr = Math.min(d.normal, 2.0);
  if (calm) [metallic, roughMul, nStr] = calm;
  m.metalness = metallic;
  m.vertexColors = !!d.vcol;
  return patch(m, {
    uniforms: {
      tAlb: { value: setTex(d.set, 'color') }, tNrm: { value: setTex(d.set, 'normal') },
      tRgh: { value: setTex(d.set, 'rough') }, uTint: { value: tint }, uTile: { value: d.scale },
      uRough: { value: roughMul }, uNrm: { value: nStr },
    },
    fragDecl: 'uniform sampler2D tAlb, tNrm, tRgh; uniform vec3 uTint; uniform float uTile, uRough, uNrm;\n',
    diffuse: `vec3 triW = v2Weights(vObjNrm, 4.0); vec3 triP = vObjPos * vec3(1.0, -1.0, 1.0) / uTile;
      diffuseColor.rgb = v2Tri(tAlb, triW, triP).rgb * uTint;
      ${d.vcol ? 'diffuseColor.rgb *= vColor.rgb;' : ''}`,
    rough: 'float roughnessFactor = clamp(uRough * v2Tri(tRgh, triW, triP).r, 0.04, 1.0);',
    normal: 'normal = v2TriNormal(tNrm, triW, triP, normal, -vViewPosition, uNrm);',
  });
}

// v2_worn.gdshader: guns' and robots' paint, worn by the asset's baked mask (UV: R = AO, G = convex edges)
function worn(name, d, w, asset) {
  const m = new THREE.MeshStandardMaterial({ name });
  m.userData.key = asset;
  m.defines = { USE_UV: '' };
  return patch(m, {
    uniforms: {
      tAlb: { value: setTex(d.set, 'color') }, tNrm: { value: setTex(d.set, 'normal') },
      tRgh: { value: setTex(d.set, 'rough') }, tImp: { value: imperfections() },
      tMask: { value: tex(asset + '_mask.png', false) },
      uTint: { value: new THREE.Vector3(...d.tint) }, uTile: { value: d.scale },
      uDetail: { value: asset.startsWith('view_') ? 0.12 : 0.7 },
      uRR: { value: new THREE.Vector2(d.rough[0], d.rough[1]) }, uMetal: { value: d.metallic },
      uNrm: { value: Math.min(d.normal, 2.0) }, uWear: { value: w[0] },
      uWearCol: { value: new THREE.Vector3(...w[1]) }, uWearMetal: { value: w[2] },
      uCavity: { value: w[3] }, uGrunge: { value: w[4] }, uScratch: { value: 0.35 },
    },
    fragDecl: `uniform sampler2D tAlb, tNrm, tRgh, tImp, tMask; uniform vec3 uTint, uWearCol; uniform vec2 uRR;
      uniform float uTile, uDetail, uMetal, uNrm, uWear, uWearMetal, uCavity, uGrunge, uScratch;
      float gWm, gRough, gAo; vec3 gImp;\n`,
    diffuse: `vec3 triW = v2Weights(vObjNrm, 4.0); vec3 tp = vObjPos * vec3(1.0, -1.0, 1.0);
      vec3 triP = tp / uTile;
      vec3 alb = v2Tri(tAlb, triW, triP).rgb * uTint;
      float rough = mix(uRR.x, uRR.y, v2Tri(tRgh, triW, triP).r);
      vec3 q = tp / uDetail;
      vec3 imp = v2Tri(tImp, triW, q + vec3(0.13)).rgb;
      vec3 impBig = v2Tri(tImp, triW, q * 0.27 + vec3(0.41)).rgb;
      vec2 mk = texture(tMask, vUv).rg;
      float ao = smoothstep(0.05, 0.7, mk.r);
      float edge = smoothstep(0.3, 0.95, mk.g);
      float patchy = smoothstep(0.15, 0.6, impBig.b);
      float wm = edge * (0.45 + 0.9 * imp.b) * mix(0.5, 1.0, patchy) * uWear * 1.7;
      wm += smoothstep(0.25, 0.7, imp.r) * uScratch * uWear * 0.8;
      wm += smoothstep(0.55, 0.95, impBig.g) * uWear * 0.3;
      wm = clamp(wm, 0.0, 1.0);
      float grime = clamp(impBig.b * 0.8 + imp.b * 0.35 - 0.25, 0.0, 1.0) * uGrunge * 2.0 + (1.0 - ao) * uCavity;
      grime = clamp(grime, 0.0, 1.0);
      alb *= 1.0 - 0.6 * grime;
      rough = rough + 0.25 * grime + (imp.g - 0.15) * 0.3 - imp.r * 0.15 * uScratch;
      diffuseColor.rgb = mix(alb, uWearCol * (0.75 + 0.5 * imp.b), wm);
      gWm = wm; gImp = imp; gAo = ao;
      gRough = clamp(mix(rough, 0.3 + 0.2 * imp.g, wm), 0.05, 1.0);`,
    rough: 'float roughnessFactor = gRough;',
    metal: 'float metalnessFactor = mix(uMetal, uWearMetal, gWm);',
    normal: 'normal = v2TriNormal(tNrm, triW, triP, normal, -vViewPosition, uNrm);',
    ao: 'reflectedLight.indirectDiffuse *= mix(1.0, gAo, 0.7); reflectedLight.indirectSpecular *= mix(1.0, gAo, 0.5);',
  });
}

// v2_set.gdshader: the environment set's paint; wear and dirt from the vertex colour (R = AO, G = chamfers)
function setPaint(name, sp, tintOverride) {
  const m = new THREE.MeshStandardMaterial({ name });
  m.vertexColors = true;
  const stripes = name === 'EHazard' ? 1 : 0;
  return patch(m, {
    uniforms: {
      tAlb: { value: setTex('PaintedPlaster017', 'color') }, tNrm: { value: setTex('PaintedPlaster017', 'normal') },
      tImp: { value: imperfections() }, uTint: { value: new THREE.Vector3(...(tintOverride || sp[0])) },
      uWearCol: { value: new THREE.Vector3(...sp[1]) }, uSmudge: { value: sp[2] }, uChips: { value: sp[3] },
      uStripes: { value: stripes },
    },
    fragDecl: `uniform sampler2D tAlb, tNrm, tImp; uniform vec3 uTint, uWearCol; uniform float uSmudge, uChips, uStripes;
      float gWm, gRough, gAo;
      vec2 v2Plane(vec3 p, vec3 n) { vec3 a = abs(n); return a.x > a.y ? (a.x > a.z ? p.zy * vec2(-1.0, 1.0) : p.xy) : (a.y > a.z ? p.xz : p.xy); }\n`,
    diffuse: `vec3 tp = vObjPos * vec3(1.0, -1.0, 1.0);
      vec3 base = uTint;
      if (uStripes > 0.5) {
        float sv = dot(vObjPos, vec3(1.0 / 0.115));
        float sw = clamp(fwidth(sv) * 1.5, 0.001, 0.5);
        float s = smoothstep(0.5 - sw, 0.5 + sw, abs(fract(sv) * 2.0 - 1.0));
        base = mix(vec3(0.6, 0.3, 0.0), vec3(0.03, 0.03, 0.032), s);
      }
      vec2 puv = v2Plane(tp / 0.9, vObjNrm);
      vec3 alb = texture(tAlb, puv).rgb * base;
      vec3 imp = texture(tImp, v2Plane(tp / 0.7 + vec3(0.13), vObjNrm)).rgb;
      vec3 impBig = texture(tImp, v2Plane(tp * vec3(0.6, 0.22, 0.6) + vec3(0.41), vObjNrm)).rgb;
      float rough = mix(0.3, 0.6, 0.35 + 0.5 * imp.g);
      float ao = vColor.r; float edge = vColor.g;
      float wm = edge * smoothstep(0.25, 0.6, imp.b + impBig.b * 0.5) * 0.8 * 1.3;
      wm += smoothstep(1.0 - uChips * 1.6, 1.0 - uChips * 1.6 + 0.1, impBig.g * 0.6 + imp.b * 0.5);
      wm += smoothstep(0.3, 0.75, imp.r) * 0.3 * 0.8;
      wm = clamp(wm, 0.0, 1.0);
      float dirt = smoothstep(0.25, 0.75, impBig.b * 1.3) * uSmudge * 0.55;
      dirt += (1.0 - smoothstep(0.1, 0.85, ao)) * 0.8;
      float up = vObjNrm.y;
      float low = clamp(1.0 - vObjPos.y / 0.3, 0.0, 1.0) * (0.35 + 0.9 * impBig.b) * 0.55 * (1.0 - 0.7 * max(up, 0.0));
      dirt = clamp(dirt + low, 0.0, 1.0);
      alb = mix(alb, vec3(0.1, 0.095, 0.085), dirt * 0.75);
      rough = clamp(rough + 0.3 * dirt + (imp.g - 0.2) * 0.2, 0.05, 1.0);
      diffuseColor.rgb = mix(alb, uWearCol * (0.8 + 0.4 * imp.b), wm);
      gWm = wm; gAo = ao; gRough = mix(rough, 0.38, wm);`,
    rough: 'float roughnessFactor = gRough;',
    metal: 'float metalnessFactor = 0.7 * gWm;',
    normal: `{ vec2 nuv = v2Plane(vObjPos * vec3(1.0, -1.0, 1.0) / 0.9, vObjNrm);
      vec3 t = texture(tNrm, nuv).xyz * 2.0 - 1.0; t.xy *= 0.35;
      normal = normalize(v2Cotangent(normal, -vViewPosition, nuv) * t); }`,
    ao: 'reflectedLight.indirectDiffuse *= mix(1.0, gAo, 0.6); reflectedLight.indirectSpecular *= mix(1.0, gAo, 0.5);',
  });
}

// v2_glove.gdshader: knit back, leather palm, grippy tips; fabrics projected from the REST pose
// (UV = rest x, y; UV2 = rest z, |normal x|; COLOR.b = |normal y|; COLOR.r palm, COLOR.g tips)
function glove(name, box, sleeve) {
  const m = new THREE.MeshStandardMaterial({ name });
  m.userData.key = name + JSON.stringify(box);
  m.vertexColors = true;
  m.defines = { USE_UV: '', USE_UV1: '' };
  return patch(m, {
    uniforms: {
      tKnit: { value: setTex('Fabric045', 'color') }, tKnitN: { value: setTex('Fabric045', 'normal') },
      tLea: { value: setTex('Rubber004', 'color') },
      uMin: { value: new THREE.Vector3(...box.min) }, uSize: { value: new THREE.Vector3(...box.size) },
      uKnitTint: { value: sleeve ? new THREE.Vector3(0.11, 0.12, 0.14).multiplyScalar(1.0) : new THREE.Vector3(0.38, 0.4, 0.43) },
      uKnitScale: { value: sleeve ? 0.16 : 0.11 }, uSleeve: { value: sleeve ? 1 : 0 },
    },
    vertDecl: 'varying vec3 vRest; varying vec3 vRestW;\nuniform vec3 uMin, uSize;\n',
    vertBody: `vRest = vec3(uv.x, 1.0 - uv.y, uv1.x) * uSize + uMin;
      { vec3 rn = vec3(1.0 - uv1.y, color.b, 0.0); rn.z = sqrt(max(0.0, 1.0 - rn.x * rn.x - rn.y * rn.y));
        rn = pow(rn, vec3(4.0)); vRestW = rn / max(rn.x + rn.y + rn.z, 1e-5); }`,
    fragDecl: `uniform sampler2D tKnit, tKnitN, tLea; uniform vec3 uKnitTint; uniform float uKnitScale, uSleeve;
      varying vec3 vRest; varying vec3 vRestW; float gRough;
      vec3 gTri(sampler2D t, vec3 p, float bias) {
        return texture(t, p.yz, bias).rgb * vRestW.x + texture(t, p.xz, bias).rgb * vRestW.y + texture(t, p.xy, bias).rgb * vRestW.z; }\n`,
    diffuse: `vec3 knit = gTri(tKnit, vRest / uKnitScale, 2.5) * uKnitTint;
      vec3 col = knit; float rough = 0.92;
      if (uSleeve < 0.5) {
        float palm = smoothstep(0.49, 0.51, vColor.r);
        float tip = smoothstep(0.49, 0.51, vColor.g);
        vec3 lea = gTri(tLea, vRest / 0.03, 1.5) * vec3(1.95, 2.03, 2.21);
        col = mix(knit, lea, palm);
        col = mix(col, gTri(tLea, vRest / 0.012, 0.0), tip);
        rough = mix(0.92, 0.68, max(palm, tip));
        float seam = 1.0 - smoothstep(0.0, 0.07, min(abs(vColor.r - 0.5), abs(vColor.g - 0.5)));
        col *= 1.0 - 0.6 * seam;
      }
      diffuseColor.rgb = col; gRough = rough;`,
    rough: 'float roughnessFactor = gRough;',
    normal: `{ float nstr = 0.6 * (1.0 - step(0.5, vColor.r) * (1.0 - uSleeve));
      vec3 pr = vRest / uKnitScale; vec3 acc = vec3(0.0);
      vec2 uvs[3]; uvs[0] = pr.yz; uvs[1] = pr.xz; uvs[2] = pr.xy;
      float ws[3]; ws[0] = vRestW.x; ws[1] = vRestW.y; ws[2] = vRestW.z;
      for (int i = 0; i < 3; i++) { if (ws[i] < 0.01) continue;
        vec3 t = texture(tKnitN, uvs[i], 2.5).xyz * 2.0 - 1.0; t.xy *= nstr;
        acc += v2Cotangent(normal, -vViewPosition, uvs[i]) * t * ws[i]; }
      if (dot(acc, acc) > 0.0) normal = normalize(acc); }`,
  });
}

// ---------------------------------------------------------------------------------------------
// Unlit animated materials (Godot's unshaded shaders take ALBEDO as sRGB: converted to linear here)
const timeUniform = { value: 0 };
export function tick(t) { timeUniform.value = t; }

function unlit(name, body, { transparent = false, side = THREE.FrontSide, uniforms = {}, decl = '' } = {}) {
  return new THREE.ShaderMaterial({
    name, transparent, side, depthWrite: !transparent,
    uniforms: { uTime: timeUniform, ...uniforms },
    vertexShader: /* glsl */`varying vec3 vPos; varying vec3 vNrm; varying vec2 vUv2;
      void main() { vPos = position; vNrm = normal; vUv2 = uv;
        #include <begin_vertex>
        #include <project_vertex>
      }`.replace('#include <begin_vertex>', 'vec3 transformed = position;')
      .replace('#include <project_vertex>', 'gl_Position = projectionMatrix * modelViewMatrix * vec4(transformed, 1.0);'),
    fragmentShader: /* glsl */`uniform float uTime; varying vec3 vPos; varying vec3 vNrm; varying vec2 vUv2; ${decl}
      float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
      void main() { vec3 col; float alpha = 1.0; ${body}
        gl_FragColor = vec4(pow(max(col, vec3(0.0)), vec3(2.2)), alpha);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  });
}

function screen(name, tint, cells, strength) {
  return unlit(name, `vec3 a = abs(vNrm);
    vec2 uv = a.y > 0.7 ? vPos.xz : vec2(a.x > a.z ? vPos.z : vPos.x, vPos.y);
    vec2 g = uv * ${cells.toFixed(2)} * 2.0;
    float grid = max(step(0.94, fract(g.x)), step(0.94, fract(g.y))) * 0.22;
    vec2 cell = floor(uv * ${cells.toFixed(2)});
    float lit = step(0.8, hash(cell + floor(uTime * 0.35 + hash(cell) * 5.0)));
    vec2 f = abs(fract(uv * ${cells.toFixed(2)}) - 0.5);
    float frame = lit * step(0.34, max(f.x, f.y));
    float scan = 0.06 * step(0.985, fract(uv.y * 1.3 - uTime * 0.12));
    float v = 0.05 + max(grid, frame) + scan;
    col = (vec3(0.01, 0.03, 0.035) + vec3(${tint.join(',')}) * v * 1.6) * ${strength.toFixed(2)};`);
}

function portal(name) {
  return unlit(name, `vec2 q = vec2(vPos.x, (vPos.y - 1.35) * 0.55);
    float r = length(q); float ang = atan(q.y, q.x);
    float swirl = ang + 2.6 / (r + 0.25) - uTime * 1.1;
    float arms = 0.5 + 0.5 * sin(swirl * 3.0 + sin(r * 9.0 - uTime * 2.0));
    float rings = 0.5 + 0.5 * sin(r * 26.0 - uTime * 5.0 + ang * 2.0);
    float v = pow(arms, 2.2) * (0.55 + 0.45 * rings);
    float spark = step(0.965, hash(vec2(floor(swirl * 5.0), floor(r * 30.0 - uTime * 6.0))));
    col = mix(vec3(0.0, 0.08, 0.14), vec3(0.25, 0.95, 1.0), v) + vec3(1.0, 0.45, 0.08) * spark * 0.9;
    col += vec3(0.6, 1.0, 1.0) * smoothstep(0.35, 0.0, r) * 0.6;
    alpha = clamp(0.72 + 0.28 * v + spark, 0.0, 0.97);`, { transparent: true, side: THREE.DoubleSide });
}

function field(name) {
  return unlit(name, `vec3 p = vPos;
    float bands = 0.5 + 0.5 * sin(p.y * 14.0 - uTime * 3.2);
    float fine = 0.5 + 0.5 * sin(p.y * 90.0 + uTime * 9.0);
    float flick = hash(vec2(floor(p.x * 22.0), floor(p.y * 6.0 - uTime * 2.0)));
    float edge = smoothstep(0.85, 0.55, abs(p.x));
    col = vec3(0.71, 0.55, 1.0) * (0.75 + 0.5 * bands);
    alpha = clamp(0.34 + 0.3 * bands + 0.1 * fine + 0.14 * step(0.9, flick) + 0.25 * (1.0 - edge), 0.0, 0.92);`,
  { transparent: true, side: THREE.DoubleSide });
}

function flash(name, core) {
  return unlit(name, `vec2 b = vec2(vUv2.x, 1.0 - vUv2.y);
    float seed = floor(uTime * 24.0) * 7.31;
    float a;
    if (${core ? 'true' : 'false'}) {
      float reach = mix(0.3, 1.0, smoothstep(0.35, 0.65, hash(floor(normalize(b) * 2.6 + seed))));
      a = pow(clamp(1.0 - length(b) / reach, 0.0, 1.0), 1.7);
    } else {
      float v = clamp(b.y, 0.0, 1.0);
      float edge = max(sqrt(v) * pow(1.0 - v, 1.2) * 2.3, 0.001);
      a = pow(clamp(1.0 - abs(b.x) / edge, 0.0, 1.0), 1.3);
    }
    a = clamp(a, 0.0, 1.0);
    col = pow(mix(vec3(1.0, 0.27, 0.04), vec3(1.0, 0.86, 0.55), pow(a, 0.6)), vec3(1.0 / 2.2)) * (1.0 + 5.0 * pow(a, 1.2));
    alpha = clamp(a * 1.25, 0.0, 1.0);`, { transparent: true, side: THREE.DoubleSide });
}

function hazard(name) {
  const m = new THREE.MeshStandardMaterial({ name, roughness: 0.5 });
  return patch(m, {
    diffuse: `float f = 0.5 + 0.5 * sin((vObjPos.x + vObjPos.y - vObjPos.z) * 90.0 - 1.5708);
      float w = max(fwidth(f), 0.001);
      diffuseColor.rgb = mix(vec3(0.02), vec3(0.8, 0.55, 0.02), smoothstep(0.5 - w, 0.5 + w, f));`,
  });
}

function grid(name) {
  const m = new THREE.MeshStandardMaterial({ name, roughness: 0.8 });
  return patch(m, {
    diffuse: `vec2 g = abs(fract(vObjPos.xz) - 0.5); float l = 1.0 - smoothstep(0.47, 0.49, max(g.x, g.y));
      diffuseColor.rgb = mix(vec3(0.6), vec3(0.75), l);`,
  });
}

function standard(name, d) {
  const m = new THREE.MeshStandardMaterial({ name });
  m.color.setRGB(d.color[0], d.color[1], d.color[2], THREE.LinearSRGBColorSpace);
  m.roughness = d.rough;
  m.metalness = d.metal || 0;
  const a = d.color.length > 3 ? d.color[3] : 1;
  if (a < 1) { m.transparent = true; m.opacity = a; m.depthWrite = false; }
  if (d.emit) {
    m.emissive.setRGB(d.emit[0], d.emit[1], d.emit[2], THREE.LinearSRGBColorSpace);
    m.emissiveIntensity = d.energy;
  }
  return m;
}

function plain(name, d) {
  const m = new THREE.MeshStandardMaterial({ name });
  m.color.setRGB(d.color[0], d.color[1], d.color[2], THREE.LinearSRGBColorSpace);
  m.roughness = d.rough;
  m.metalness = d.metallic;
  if (d.emit_strength > 0 && d.emit[0] + d.emit[1] + d.emit[2] > 0) {
    m.emissive.setRGB(d.emit[0], d.emit[1], d.emit[2], THREE.LinearSRGBColorSpace);
    m.emissiveIntensity = d.emit_strength >= 1 ? Math.min(Math.max(d.emit_strength * 0.3, 1), 6) : d.emit_strength;
  }
  let alpha = d.alpha;
  if (d.transmission > 0) { alpha = 0.22; m.roughness = 0.05; }
  if (alpha < 1) { m.transparent = true; m.opacity = alpha; m.depthWrite = false; }
  return m;
}

// ---------------------------------------------------------------------------------------------
export class MaterialLib {
  constructor(data) { this.d = data; this.cache = new Map(); }

  // the material for a Blender material name on a mesh (mirrors V2Assets.material)
  get(name, { mesh = '', asset = '', hasUv = false } = {}) {
    const d = this.d;
    let key = name;
    if (d.wear[name] && asset && hasUv && ASSETS_WITH_MASK.has(asset)) key = name + '@' + asset;
    else if (name === 'Glove' || name === 'JacketSleeve') key = name + '/' + mesh;
    if (this.cache.has(key)) return this.cache.get(key);
    const m = this.make(name, key, mesh, asset);
    this.cache.set(key, m);
    return m;
  }

  make(name, key, mesh, asset) {
    const d = this.d;
    const mat = d.materials[name] || {};
    if (key.includes('@')) return worn(name, mat, d.wear[name], asset);
    if (name === 'Glove' || name === 'JacketSleeve') {
      const box = d.gloves[mesh] || { min: [0, 0, 0], size: [1, 1, 1] };
      return glove(name, box, name === 'JacketSleeve');
    }
    if (d.set_paint[name]) return setPaint(name, d.set_paint[name]);
    if (name === 'EScreen') return screen(name, [0.2, 0.9, 0.85], 13, 1);
    if (name === 'EPanelScreen') return screen(name, [0.3, 0.6, 0.52], 4, 0.45);
    if (name === 'EPortal') return portal(name);
    if (name === 'ExitField') return field(name);
    if (name.startsWith('Flash')) return flash(name, name === 'FlashCore');
    if (name === 'Hazard') return hazard(name);
    if (name === 'StudioFloor') return grid(name);
    if (d.set_plain[name]) return standard(name, d.set_plain[name]);
    if (d.special[name]) return standard(name, d.special[name]);
    if (mat.type === 'pbr') return pbr(name, mat, d.calm[name]);
    if (mat.type === 'plain') return plain(name, mat);
    return new THREE.MeshStandardMaterial({ name, color: 0x888888, roughness: 0.6 });
  }

  // replace every material in a loaded glTF scene (V2Assets.apply)
  apply(root, asset) {
    root.traverse((o) => {
      if (!o.isMesh) return;
      const swap = (m) => this.get(m.name, { mesh: meshKey(o), asset, hasUv: !!o.geometry.attributes.uv });
      o.material = Array.isArray(o.material) ? o.material.map(swap) : swap(o.material);
      if (o.material.transparent) o.renderOrder = 2;
    });
  }
}

// Godot's MeshInstance3D name for a glove: the node name (three.js names a multi-material mesh's
// primitives after the node; the node itself is the parent group in that case)
function meshKey(o) {
  if (o.name && !/_\d+$/.test(o.name)) return o.name;
  return o.parent && o.parent.name ? o.parent.name : o.name;
}

export const ASSETS_WITH_MASK = new Set(['spider', 'drone', 'turret', 'view_pistol', 'view_rifle']);
