# Style

The template's `css/docs.css` and `css/gallery.css` implement all of this; change tokens there, not per page.

## Colour tokens (`:root` in docs.css)

| Token | Value | Use |
|---|---|---|
| `--bg` | `#141414` | page, model list |
| `--side` | `#1B1B1B` | left menu |
| `--line` | `#2A2A2A` | dividers, borders |
| `--ink` / `--ink-2` | `#E8E8E8` / `#A3A3A3` | text / secondary |
| `--accent` | `#3FD0E8` | links, kickers, viewer's active clip |
| `--accent-bg` | `#2B2B2B` | selected menu row, selected model, step number circle |
| `--hover` | `#232323` | hover rows |
| `--code` | `#1E1E1E` | reply panels |

The 3D stage keeps a light studio grey (radial `#b9bec0` -> `#7f8689`) so models read; its toolbars are light
pills (`#F5F6F6` at 92 %) and a dark glass bottom bar (`rgba(14,18,21,.78)`).

## Menu (from the user's reference: a dark docs sidebar)

220 px wide, padding 16 x 10; items: flex, 12 px gap, padding 7 x 10, radius 8, Geist 400 15 px, `#E8E8E8`,
icon `#CFCFCF`; hover `#232323`; current `#2B2B2B`, white text and icon. No search. On phones (< 760 px) it becomes
a sticky horizontal bar. Icons are inline Lucide SVGs (ISC licence; add a `licenses.csv` row):
Overview `book-open-text`, Play `gamepad-2`, GDD `file-text`, Assets `box`, Trajectory `route`.

## Typography (the user's rules)

- **Funnel Display**, weight 500, tracking -0.02em: headlines and titles. Homepage H1 72 px, page H1 64 px,
  large H2 48 px (centred), H2 40 px (left), H3 26.5 px, card titles 20 px.
- **Geist**: body text, buttons and links. Lead 18 px / 1.65, body 16 px / 1.6, card body 15 px / 1.6,
  buttons 16.5 px weight 500, links 15 px.
- **JetBrains Mono**, uppercase, tracking 0.14em: the "code" voice. Hero prompt 13 px, kickers 12 px in cyan,
  labels 11 px. (Viewer buttons and trajectory numbers/dates are labels.)
- Headlines in sentence case. Sizes step down at 991, 767 and 479 px (CSS variables `--h1-home`, `--h1`, `--h2`...).
- Self-host: fetch the latin woff2 from Google Fonts' CSS (send a desktop browser User-Agent to get woff2), put
  them in `site/fonts/` with each family's `OFL.txt` (github.com/google/fonts/tree/main/ofl/<family>).

## Layout rules

- Content column 820 px max, padding 40 x 48 (24 x 16 on phones).
- Overview step: number circle left (32 px, JetBrains Mono), `h2`, `.shots` grid (first image full width, two
  below), then Goal / Steps / Learnings / Tools as cyan kickers.
- Video: `.video iframe { width: 100%; aspect-ratio: <recording>; border-radius: 6px }`.
- Play page: the iframe is centred on `#04070A`, `width: min(100%, (100vh - 48px) * 16/9)`.
