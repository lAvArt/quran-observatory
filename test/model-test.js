// Run with: node test/model-test.js
// No network: fixtures only. test/reference-test.mjs checks the same code
// against the site's own TypeScript and real data.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const M = require("../Model.js")

const dir = path.join(__dirname, "..")
let passed = 0
function test(name, fn) {
  try { fn(); passed++ } catch (e) { console.error("FAIL " + name + "\n  " + e.message); process.exitCode = 1 }
}

function root(bare, extra) {
  return Object.assign({
    root: bare.split("").join("-"), bare: bare, bw: "", translit: "", gloss: null,
    count: 1, surahs: 1, verses: 1, forms: 1, first: { sura: 1, ayah: 1 },
    top: [[1, 1, 1]], hist: new Array(114).fill(0), pos: [["N", 1]]
  }, extra || {})
}

const fixture = {
  version: 1,
  rootCount: 4,
  featured: ["رحم", "كتب", "missing"],
  roots: {
    "رحم": root("رحم", { bw: "rHm", translit: "r · ḥ · m", gloss: "mercy / compassion", count: 339,
      examples: [{ s: 1, a: 1, w: 3, words: [{ t: "بِسْمِ", root: "سمو", pos: "N" }, { t: "ٱلرَّحْمَٰنِ", root: "رحم", pos: "ADJ" }] }] }),
    "كتب": root("كتب", { bw: "ktb", translit: "k · t · b", gloss: "write / book", count: 319 }),
    "امم": root("امم", { bw: "Amm", translit: "ʾ · m · m", gloss: "mother / nation", count: 119 }),
    "رحب": root("رحب", { bw: "rHb", translit: "r · ḥ · b", count: 4 })
  }
}
const index = M.sanitize(JSON.parse(JSON.stringify(fixture)))

// ---- Validation ----

test("sanitize keeps valid roots and drops unknown featured entries", () => {
  assert.strictEqual(index.rootCount, 4)
  assert.deepStrictEqual(index.featured, ["رحم", "كتب"])
})

test("sanitize rejects things that are not a root index", () => {
  for (const bad of [null, 42, "x", [], {}, { roots: [] }, { roots: { "x": {} } }]) assert.strictEqual(M.sanitize(bad), null)
  assert.strictEqual(M.parseIndex("{not json"), null)
  assert.strictEqual(M.parseIndex(""), null)
  assert.strictEqual(M.parseIndex("x".repeat(M.LIMITS.bytes + 1)), null)
})

test("root keys must be Arabic letters and match their bare form", () => {
  const raw = { featured: [], roots: { "<b>": root("<b>"), "abc": root("abc"), "كتب": root("رحم"), "علم": root("علم") } }
  assert.deepStrictEqual(Object.keys(M.sanitize(raw).roots), ["علم"])
})

test("markup-shaped text stays literal and is length-bounded", () => {
  const evil = '<img src="https://example.invalid/t">'
  const raw = { featured: ["علم"], roots: { "علم": root("علم", { gloss: evil + "x".repeat(200), translit: evil }) } }
  const r = M.sanitize(raw).roots["علم"]
  assert.ok(r.gloss.startsWith(evil), "kept as text, not interpreted")
  assert.strictEqual(r.gloss.length, M.LIMITS.gloss)
  assert.strictEqual(r.translit, evil)
})

test("control characters and bidi overrides are stripped", () => {
  const raw = { featured: [], roots: { "علم": root("علم", { gloss: "kno‮wl\u0000edge⁦" }) } }
  assert.strictEqual(M.sanitize(raw).roots["علم"].gloss, "knowledge")
})

test("numbers are clamped and arrays bounded", () => {
  const raw = { featured: [], roots: { "علم": root("علم", {
    count: -5, surahs: 9999, verses: "12", forms: NaN,
    hist: [1, 2, "x"], top: [[0, 1, 1], [2, 3, 4], "bad", [115, 1, 1]],
    examples: new Array(50).fill({ s: 2, a: 1, w: 0, words: [{ t: "قَالَ", root: "قول" }] }).concat([{ s: 0, a: 1, words: [] }])
  }) } }
  const r = M.sanitize(raw).roots["علم"]
  assert.strictEqual(r.count, 0)
  assert.strictEqual(r.surahs, 114)
  assert.strictEqual(r.verses, 12)
  assert.strictEqual(r.forms, 0)
  assert.strictEqual(r.hist.length, 114)
  assert.deepStrictEqual(r.hist.slice(0, 4), [1, 2, 0, 0])
  assert.deepStrictEqual(r.top, [[2, 3, 4]])
  assert.strictEqual(r.examples.length, M.LIMITS.examples)
})

test("form index validation drops malformed keys and values", () => {
  const forms = M.sanitizeForms({ forms: { "يكتبون": "كتب", "ص:طه": "بسط", "رحمة": "<b>", "": "علم", "امهات": "امم" } })
  assert.deepStrictEqual(Object.keys(forms).sort(), ["امهات", "يكتبون"])
  assert.strictEqual(M.sanitizeForms({ forms: [] }), null)
  assert.strictEqual(M.parseForms("nope"), null)
})

// ---- Root of the day ----

test("epochDay counts local days like the site", () => {
  const d = new Date(2026, 10, 20, 0, 30)
  const expected = Math.floor((d.getTime() - d.getTimezoneOffset() * 60000) / 86400000)
  assert.strictEqual(M.epochDay(d), expected)
  assert.strictEqual(M.epochDay(new Date(2026, 10, 20, 23, 59)), expected)
  assert.strictEqual(M.epochDay(new Date(2026, 10, 21, 0, 0)), expected + 1)
})

test("rootOfTheDay walks the featured list", () => {
  assert.strictEqual(M.rootOfTheDay(index, 0).bare, "رحم")
  assert.strictEqual(M.rootOfTheDay(index, 1).bare, "كتب")
  assert.strictEqual(M.rootOfTheDay(index, 2).bare, "رحم")
  assert.strictEqual(M.rootOfTheDay(null, 2), null)
  assert.strictEqual(M.rootOfTheDay(M.sanitize({ featured: [], roots: fixture.roots }), 3), null)
})

// ---- Search ----

test("search finds roots by Arabic word, gloss, Buckwalter and transliteration", () => {
  assert.strictEqual(M.search(index, "الرحمة")[0].bare, "رحم")
  assert.strictEqual(M.search(index, "mercy")[0].bare, "رحم")
  assert.strictEqual(M.search(index, "ktb")[0].bare, "كتب")
  assert.strictEqual(M.search(index, "k t b")[0].bare, "كتب")
  assert.strictEqual(M.search(index, "أم")[0].bare, "امم")
  assert.deepStrictEqual(M.search(index, "   "), [])
  assert.deepStrictEqual(M.search(index, "zzzz"), [])
})

test("search lists prefix matches after the best match, most frequent first", () => {
  assert.deepStrictEqual(M.search(index, "رح").map((r) => r.bare), ["رحم", "رحب"])
})

test("search uses the form index for inflected words", () => {
  const forms = M.sanitizeForms({ forms: { "يكتبون": "كتب" } })
  assert.deepStrictEqual(M.search(index, "يكتبون"), [])
  assert.strictEqual(M.search(index, "يكتبون", 8, forms)[0].bare, "كتب")
  assert.strictEqual(M.search(index, "ويكتبون", 8, forms)[0].bare, "كتب", "proclitic stripped")
})

test("search ignores a form that points at a root the index lacks", () => {
  const forms = M.sanitizeForms({ forms: { "علماء": "علم" } })
  assert.deepStrictEqual(M.search(index, "علماء", 8, forms), [])
})

test("search respects the limit", () => {
  assert.strictEqual(M.search(index, "ر", 1).length, 1)
})

// ---- Presentation ----

test("verseWords marks the root's own words", () => {
  const words = M.verseWords(index.roots["رحم"].examples[0], "رحم")
  assert.deepStrictEqual(words.map((w) => w.hit), [false, true])
  assert.deepStrictEqual(M.verseWords(null, "رحم"), [])
})

test("barLabel styles", () => {
  const r = index.roots["رحم"]
  assert.strictEqual(M.barLabel(r, "Root and meaning"), "ر-ح-م · mercy / compassion")
  assert.strictEqual(M.barLabel(r, "Root"), "ر-ح-م")
  assert.strictEqual(M.barLabel(r, "Transliteration and meaning"), "r·ḥ·m · mercy / compassion")
  assert.strictEqual(M.barLabel(r, "Icon only"), "")
  assert.strictEqual(M.barLabel(index.roots["رحب"], "Root and meaning"), "ر-ح-ب · r·ḥ·b", "no gloss falls back to transliteration")
  assert.strictEqual(M.barLabel(null, "Root"), "")
})

test("barLabel appends the occurrence count when given one", () => {
  const r = index.roots["رحم"]
  assert.strictEqual(M.barLabel(r, "Root and meaning", "339×"), "ر-ح-م · mercy / compassion · 339×")
  assert.strictEqual(M.barLabel(r, "Root", "339×"), "ر-ح-م · 339×")
  assert.strictEqual(M.barLabel(r, "Transliteration and meaning", "339×"), "r·ḥ·m · mercy / compassion · 339×")
  assert.strictEqual(M.barLabel(r, "Icon only", "339×"), "", "the icon stays alone")
})

test("todayText is one plain line", () => {
  assert.strictEqual(M.todayText(index.roots["رحم"]), "ر-ح-م (r · ḥ · m) - mercy / compassion - 339 occurrences")
  assert.strictEqual(M.todayText(null), "")
})

test("histogramLevels scales to the busiest surah", () => {
  assert.deepStrictEqual(M.histogramLevels([0, 2, 4]), [0, 0.5, 1])
  assert.deepStrictEqual(M.histogramLevels([0, 0]), [0, 0])
})

test("surah names", () => {
  assert.strictEqual(M.SURAHS.length, 114)
  assert.strictEqual(M.surahName(1), "Al-Fatihah")
  assert.strictEqual(M.surahName(2, true), "البقرة")
  assert.strictEqual(M.surahName(0), "")
  assert.strictEqual(M.surahName(115), "")
})

test("site URLs encode the query and pick a language", () => {
  assert.strictEqual(M.rootUrl("رحم", "en"), "https://www.quranobservatory.org/en?q=%D8%B1%D8%AD%D9%85")
  assert.strictEqual(M.searchUrl("a&b=c #d", "ar"), "https://www.quranobservatory.org/ar/search?q=a%26b%3Dc%20%23d")
  assert.strictEqual(M.rootUrl("x", "fr"), "https://www.quranobservatory.org/en?q=x")
  assert.strictEqual(M.siteLanguage("ar"), "ar")
  assert.strictEqual(M.siteLanguage("pt-BR"), "en")
})

// ---- Updates ----

test("needsDownload follows the schedule and backs off after a failure", () => {
  const now = Date.UTC(2026, 10, 20)
  const day = 86400
  assert.strictEqual(M.needsDownload(0, now, "Weekly", 0), true, "no cache")
  assert.strictEqual(M.needsDownload(now / 1000 - 2 * day, now, "Weekly", 0), false)
  assert.strictEqual(M.needsDownload(now / 1000 - 8 * day, now, "Weekly", 0), true)
  assert.strictEqual(M.needsDownload(now / 1000 - 2 * day, now, "Daily", 0), true)
  assert.strictEqual(M.needsDownload(0, now, "Off", 0), false, "off never downloads")
  assert.strictEqual(M.needsDownload(0, now, "Weekly", now - 60000), false, "recent failure")
  assert.strictEqual(M.needsDownload(0, now, "Weekly", now - 2 * 3600 * 1000), true)
  assert.strictEqual(M.needsDownload(0, now, "bogus", 0), true, "unknown interval acts as weekly")
})

test("moveSelection wraps", () => {
  assert.strictEqual(M.moveSelection(0, -1, 3), 2)
  assert.strictEqual(M.moveSelection(2, 1, 3), 0)
  assert.strictEqual(M.moveSelection(0, 1, 0), 0)
})

// ---- Static checks on the QML and catalogs ----

const qmlFiles = fs.readdirSync(dir).filter((f) => f.endsWith(".qml"))
const qml = Object.fromEntries(qmlFiles.map((f) => [f, fs.readFileSync(path.join(dir, f), "utf8")]))

test("only PlainText draws text; nothing opts into rich text", () => {
  for (const [file, src] of Object.entries(qml)) {
    if (file === "PlainText.qml") continue
    assert.ok(!/(^|\s)Text\s*\{/.test(src), file + " uses a bare Text")
    assert.ok(!/TextEdit\s*\{/.test(src), file + " uses TextEdit")
    assert.ok(!/(RichText|StyledText|AutoText|MarkdownText)/.test(src), file + " enables rich text")
  }
  assert.ok(/textFormat:\s*Text\.PlainText/.test(qml["PlainText.qml"]))
})

test("no shell command is built from data", () => {
  for (const [file, src] of Object.entries(qml)) {
    for (const m of src.matchAll(/"sh",\s*"-c",\s*("(?:[^"\\]|\\.)*")/g)) {
      const script = JSON.parse(m[1])
      assert.ok(/^[^+]*$/.test(m[0]), file + ": script is concatenated")
      assert.ok(!/\$\{|\+/.test(script), file + ": script interpolates")
    }
  }
})

const en = JSON.parse(fs.readFileSync(path.join(dir, "i18n/en.json"), "utf8"))
const ar = JSON.parse(fs.readFileSync(path.join(dir, "i18n/ar.json"), "utf8"))

test("every string key the QML uses is in both catalogs", () => {
  const used = new Set()
  for (const src of Object.values(qml)) for (const m of src.matchAll(/strings\.tn?\("([^"]+)"/g)) used.add(m[1])
  // Keys built at runtime: stat labels listed in Panel.qml, and "pos." + posKey.
  for (const m of qml["Panel.qml"].matchAll(/"(stat\.[A-Za-z]+)"/g)) used.add(m[1])
  for (const code of ["N", "V", "ADJ", "PN", "P", "PRON", "ADV", "IMPN"]) used.add("pos." + M.posKey(code))
  used.delete("pos.")
  for (const key of used) {
    assert.ok(key in en, "en.json lacks " + key)
    assert.ok(key in ar, "ar.json lacks " + key)
  }
})

test("catalogs agree on keys, plurals and placeholders", () => {
  assert.deepStrictEqual(Object.keys(ar).sort(), Object.keys(en).sort())
  for (const key of Object.keys(en)) {
    const e = en[key], a = ar[key]
    if (typeof e === "object") {
      assert.deepStrictEqual(Object.keys(e).sort(), ["one", "other"], key)
      assert.deepStrictEqual(Object.keys(a).sort(), ["few", "many", "one", "other", "two", "zero"], key)
    } else {
      const holes = (s) => (s.match(/%\d/g) || []).sort().join()
      assert.strictEqual(holes(a), holes(e), key + " placeholders")
    }
  }
})

test("every POS code Model knows has a catalog entry", () => {
  for (const code of ["N", "V", "ADJ", "PN", "P", "PRON", "ADV", "IMPN"]) assert.ok(("pos." + M.posKey(code)) in en, code)
  assert.strictEqual(M.posKey("ZZZ"), "")
})

test("manifest defaults match the schema and Model", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"))
  const w = manifest.barWidget
  for (const field of w.schema) assert.deepStrictEqual(w.defaults[field.key], field.defaultValue, field.key)
  assert.deepStrictEqual(w.schema.find((f) => f.key === "label").options, M.LABEL_STYLES)
  assert.deepStrictEqual(w.schema.find((f) => f.key === "updates").options.slice().sort(), ["Daily", "Off", "Weekly"])
})

console.log(process.exitCode ? "model tests failed" : passed + " model tests passed")
