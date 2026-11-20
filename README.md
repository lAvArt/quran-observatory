# Quran Observatory for Omarchy

Today's Quranic root in your [Omarchy](https://omarchy.org) bar, from
[quranobservatory.org](https://www.quranobservatory.org).

```
خ-ي-ر · good / better · 196×
```

It sits in a faint, softly rounded frame so it doesn't blend into the
clock and indicators beside it (or set *Bar style* to *Plain*). Click it for
the root in full: its Arabic form, transliteration and meaning; occurrences,
verses, sūrahs and word forms; the parts of speech it takes. Under those,
one diagram at a time:

- **Verses**: example verses with the root's words highlighted
- **Companions**: the eight roots it shares the most verses with, drawn as a
  network around it; heavier spokes mean more verses in common. Ranked by
  local mutual information (shared verses × PMI), so the commonest roots
  don't crowd out the telling ones: ر-ح-م's companions are غ-ف-ر (forgive),
  ت-و-ب (repent), ف-ض-ل (bounty). Click a companion to move to it.
- **Concordance**: every occurrence in context, with the word centred
  between what comes before and after it, and its verse reference
- **Distribution**: occurrences in each of the 114 sūrahs; a grid of the
  sūrahs shaded by occurrences per 1,000 words, so long sūrahs don't win
  by length; and the Makkan / Madinan split, marked against where an even
  spread would fall

Search by Arabic root or word (`رحمة`, `يكتبون`, `أم القرى`), English meaning
(`mercy`), Buckwalter (`rHm`) or transliteration (`r h m`).

Today's root is the same one the site's homepage shows. The plugin picks it
with the site's own formula, so the two change together at local midnight.

## Privacy and network use

The widget downloads four public files from quranobservatory.org (the
root index, the word-form index, and the concordance with its text, about
3.5 MB together) and keeps them in
`~/.cache/io.github.lavart.quran-observatory/`. Today's root, the search and
every diagram run on that copy, so **what you type and the roots you look at
are never sent anywhere**.

- **Update schedule:** downloads are weekly by default. The *Download root
  data* setting switches them to daily, or *Off* to make no network
  requests at all.
- **Safe downloads:** a download replaces the cache only after it parses
  and validates, so a dropped connection never costs you the copy that
  works. Every field is length- and range-checked, and all text is drawn as
  plain text.
- **Site links:** only the *Open on the site* and *Search the corpus*
  buttons open quranobservatory.org, and they open it in your browser.

## Install

```
omarchy plugin add https://github.com/lAvArt/quran-observatory --enable
```

Or copy the plugin files into
`~/.config/omarchy/plugins/io.github.lavart.quran-observatory/`, then
run `omarchy-shell shell rescanPlugins` and
`omarchy bar put io.github.lavart.quran-observatory --section centerEnd`.

## Use

| | |
|---|---|
| Left click | open the panel |
| Right click | open today's root on quranobservatory.org |
| Type | search |
| Up / Down, Enter | choose a result |
| Escape | clear the search, go back to today's root, then close |
| Up / Down (search empty) | switch the diagram |
| Left / Right (search empty) | step through the example verses |
| Page Up / Page Down | scroll the concordance |
| Enter (search empty) | open the root on the site |
| Ctrl+Enter | search the whole corpus on the site |
| Tab | next panel |

## Settings

| Setting | Options |
|---|---|
| Bar label | Root and meaning · Root · Transliteration and meaning · Icon only |
| Bar style | Chip · Plain |
| Show occurrences | On · Off (the `196×` after the root) |
| Download root data | Weekly · Daily · Off |
| Arabic font | any installed font; default Noto Naskh Arabic |

The interface is in English and Arabic and follows Omarchy's language
setting. In Arabic, the site links open the Arabic version of the site.

## Scripting

```
qs ipc call io.github.lavart.quran-observatory today       # خ-ي-ر (kh · y · r) - good / better - 196 occurrences
qs ipc call io.github.lavart.quran-observatory search رحمة  # open the panel on a search
qs ipc call io.github.lavart.quran-observatory toggle
qs ipc call io.github.lavart.quran-observatory view companions   # or verses, concordance, distribution
qs ipc call io.github.lavart.quran-observatory refresh     # download the data now
```

To bind a key, for example in `~/.config/hypr/bindings.lua`:
`qs ipc call io.github.lavart.quran-observatory toggle`.

## Development

```
node test/model-test.js
node test/reference-test.mjs <site-repo> root-stats.json form-index.json concordance.json concordance-text.json
```

`model-test.js` needs nothing but node. `reference-test.mjs` runs the site's
own TypeScript next to the plugin's port and checks that they agree: today's
root over 1,000 days, the root lookup over 55 queries, the word-form lookup
over a sample of the corpus's surface forms, and, for every root, its
per-sūrah verse counts and the revelation places against the site's
concordance code. The data files are at
`https://www.quranobservatory.org/data/`.

After editing an installed copy, run `omarchy restart shell`. The running
shell doesn't always reload a plugin it has already loaded.

## Data

The root data is built by quranobservatory.org from the
[Quranic Arabic Corpus](https://corpus.quran.com) (University of Leeds).
Nothing from the corpus is bundled here; it's downloaded at run time.

## License

MIT, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
