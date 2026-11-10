#!/usr/bin/env python3
"""Fetch ambientCG CC0 texture sets and pack them for Godot.

    python3 -I tools/fetch_textures.py            # everything in SETS
    python3 -I tools/fetch_textures.py Metal029   # one set

For each set:
  - checks the asset page states the CC0 licence (refuses otherwise)
  - downloads <id>_<res>-JPG.zip into assets_src/textures/<id>/ (git-ignored)
  - writes assets/textures/<id>/albedo.jpg, normal.jpg (OpenGL / NormalGL) and
    orm.jpg (R = AO, G = roughness, B = metalness, half resolution for 2K sets), the
    layout ORMMaterial3D expects
  - adds or updates its row in licenses.csv
"""
import csv, datetime, io, json, pathlib, sys, urllib.request, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets_src" / "textures"
OUT = ROOT / "assets" / "textures"
LICENSES = ROOT / "licenses.csv"

# id -> resolution. 2K for walls/floors/large surfaces, 1K for small props (CLAUDE.md).
SETS = {
    "Metal046A": "2K",         # wall panels (dark clean metal)
    "Metal028": "2K",          # frames, trims, pillars (black powder coat)
    "Metal038": "2K",          # door panel (scratched steel)
    "DiamondPlate008A": "2K",  # floor
    "MetalPlates015B": "2K",   # ceiling (vent grid)
    "Metal029": "1K",          # small props
}

API = "https://ambientcg.com/api/v2/full_json?id={id}&include=downloadData"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "project-firewall-asset-fetch"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def fetch(asset_id, res):
    from PIL import Image

    meta = json.loads(get(API.format(id=asset_id)))["foundAssets"][0]
    # The API carries no licence field; each asset page states the site-wide CC0 licence.
    page = get(f"https://ambientcg.com/view?id={asset_id}").decode("utf-8", "replace")
    if "Creative Commons CC0" not in page:
        raise SystemExit(f"{asset_id}: asset page does not state CC0; refusing")
    want = f"{res}-JPG"
    link = None
    for cat in meta["downloadFolders"]["default"]["downloadFiletypeCategories"].values():
        for d in cat["downloads"]:
            if d["attribute"] == want:
                link = d["downloadLink"]
    if not link:
        raise SystemExit(f"{asset_id}: no {want} download")

    src = SRC / asset_id
    src.mkdir(parents=True, exist_ok=True)
    zpath = src / f"{asset_id}_{want}.zip"
    if not zpath.exists():
        print(f"downloading {asset_id} {want} ...")
        zpath.write_bytes(get(link))
    z = zipfile.ZipFile(zpath)

    def member(suffix):
        for n in z.namelist():
            if n.endswith(f"_{suffix}.jpg"):
                return Image.open(io.BytesIO(z.read(n)))
        return None

    color = member("Color")
    normal = member("NormalGL")
    if color is None or normal is None:
        raise SystemExit(f"{asset_id}: missing Color or NormalGL map")
    size = color.size
    gray = lambda im, default: (im.convert("L").resize(size) if im is not None else Image.new("L", size, default))
    ao = gray(member("AmbientOcclusion"), 255)
    rough = gray(member("Roughness"), 160)
    metal = gray(member("Metalness"), 0)

    out = OUT / asset_id
    out.mkdir(parents=True, exist_ok=True)
    color.convert("RGB").save(out / "albedo.jpg", quality=92)
    normal.convert("RGB").save(out / "normal.jpg", quality=95)
    orm = Image.merge("RGB", (ao, rough, metal))
    # ORM carries soft detail: half resolution for 2K sets keeps the web download down
    # (albedo and normal stay at full 2K).
    if size[0] > 1024:
        orm = orm.resize((size[0] // 2, size[1] // 2), Image.LANCZOS)
    orm.save(out / "orm.jpg", quality=92)
    print(f"{asset_id}: {size[0]}x{size[1]} -> {out.relative_to(ROOT)} (metal map: {'yes' if member('Metalness') else 'no'})")
    log_license(f"{asset_id} ({res} PBR texture)", "ambientCG",
                f"https://ambientcg.com/view?id={asset_id}", "CC0 1.0")


def log_license(name, source, url, lic):
    rows = []
    if LICENSES.exists():
        with LICENSES.open(newline="") as f:
            rows = list(csv.DictReader(f))
    today = datetime.date.today().isoformat()
    for r in rows:
        if r["url"] == url:
            r.update(name=name, source=source, license=lic)
            break
    else:
        rows.append({"name": name, "source": source, "url": url, "license": lic, "date": today})
    with LICENSES.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["name", "source", "url", "license", "date"])
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    ids = sys.argv[1:] or list(SETS)
    for i in ids:
        fetch(i, SETS.get(i, "2K"))
