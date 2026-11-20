# Changelog

## 1.2.0 (2026-11-20)

- A small graph in the bar after the label: the root's spread across the
  sūrahs (19 groups of six, square-root scaled) or its Makkan / Madinan
  split against an even spread. *Bar graph* setting; the tooltip spells it
  out.
- The Arabic root in the bar is centred on its own ink and sized to clear
  the frame, instead of sinking to the Latin baseline.

## 1.1.0 (2026-11-20)

- Diagrams under the root, one at a time: Verses, Companions (a network of
  the roots it shares the most verses with, ranked by local mutual
  information; click one to move to it), Concordance (every occurrence in
  context) and Distribution (per-sūrah counts, a per-1,000-words grid, and
  the Makkan / Madinan split against an even spread).
- The bar label sits in a faint, softly rounded frame (Bar style: Chip),
  with the occurrence count in a small badge; Plain keeps the old look.
- Downloads the site's concordance files too (about 3.5 MB in all); the
  diagrams are computed offline from them.
- `qs ipc call … view <name>` opens the panel on a diagram.

## 1.0.0 (2026-11-20)

- Today's root in the bar, the same one the site's homepage shows, with its
  meaning and how often it occurs (`خ-ي-ر · good / better · 196×`).
- Panel: the root's statistics, parts of speech, a per-sūrah histogram, and
  example verses with the root's words highlighted.
- Search by Arabic root or inflected word, English meaning, Buckwalter or
  transliteration; works offline from the cached data.
- Weekly, daily or no downloads; downloads are validated before they
  replace the cache.
- English and Arabic interface.
