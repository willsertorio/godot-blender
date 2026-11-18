#!/usr/bin/env bash
# Publish build/site to the gh-pages branch (GitHub Pages: Settings -> Pages -> Deploy from a branch -> gh-pages, / (root)).
# Prebuilt files on their own branch: nothing merges into main and no CI has to build Godot.
# Run from the repository root, after scripts/build_site.sh. Ask the user before the first push to gh-pages.
#   scripts/publish_gh_pages.sh "message"
set -euo pipefail
SRC=build/site
WORK="${GH_PAGES_WORKDIR:-$(mktemp -d)}"
URL=$(git remote get-url origin)
HEAD=$(git rev-parse --short HEAD)
MSG="${1:-Site build}"

if git ls-remote --exit-code origin gh-pages >/dev/null 2>&1; then
  git clone -q --depth 1 --branch gh-pages "$URL" "$WORK/site"
else
  mkdir -p "$WORK/site" && git -C "$WORK/site" init -q -b gh-pages && git -C "$WORK/site" remote add origin "$URL"
fi
find "$WORK/site" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$SRC"/. "$WORK/site"/
cd "$WORK/site"
git add -A
if git diff --cached --quiet; then echo "gh-pages: nothing changed"; exit 0; fi
git -c user.name="$(git -C "$OLDPWD" log -1 --format=%an)" -c user.email="$(git -C "$OLDPWD" log -1 --format=%ae)" \
  commit -q -m "$MSG (from $HEAD)"
for i in 1 2 3 4; do git push -q origin gh-pages && break; sleep $((2 ** i)); done
git log --oneline -1
