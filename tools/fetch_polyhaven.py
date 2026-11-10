#!/usr/bin/env python3
"""Fetch Poly Haven CC0 models (1K glTF) into assets_src/models/polyhaven/<id>/ and log them.

    python3 -I tools/fetch_polyhaven.py medical_box ammo_box

Checks the asset page states CC0 before downloading. The raw files are git-ignored;
blender/scripts/normalize_pickups.py turns them into assets/models/*.glb.
"""
import csv, datetime, json, pathlib, sys, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets_src" / "models" / "polyhaven"
LICENSES = ROOT / "licenses.csv"
UA = {"User-Agent": "project-firewall-asset-fetch"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def fetch(asset):
    page = get(f"https://polyhaven.com/a/{asset}").decode("utf-8", "replace")
    if "CC0 1.0" not in page:
        raise SystemExit(f"{asset}: page does not state CC0; refusing")
    info = json.loads(get(f"https://api.polyhaven.com/info/{asset}"))
    files = json.loads(get(f"https://api.polyhaven.com/files/{asset}"))
    g = files["gltf"]["1k"]["gltf"]
    d = OUT / asset
    d.mkdir(parents=True, exist_ok=True)
    (d / pathlib.Path(g["url"]).name).write_bytes(get(g["url"]))
    for rel, inc in g.get("include", {}).items():
        p = d / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(get(inc["url"]))
    print(f"{asset}: {info.get('name')} -> {d.relative_to(ROOT)} ({len(g.get('include', {}))} files)")
    log(f"{info.get('name', asset)} model, 1K textures ({asset})", "Poly Haven", f"https://polyhaven.com/a/{asset}", "CC0 1.0")


def log(name, source, url, lic):
    rows = list(csv.DictReader(LICENSES.open(newline=""))) if LICENSES.exists() else []
    if not any(r["url"] == url for r in rows):
        rows.append({"name": name, "source": source, "url": url, "license": lic, "date": datetime.date.today().isoformat()})
    with LICENSES.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["name", "source", "url", "license", "date"])
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    for a in sys.argv[1:]:
        fetch(a)
