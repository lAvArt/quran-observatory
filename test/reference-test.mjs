// Checks the plugin's search and root of the day against the site's own code.
//
//   node test/reference-test.mjs <site-repo> <root-stats.json> [form-index.json] [concordance.json concordance-text.json]
//
// <site-repo> is a checkout of github.com/lAvArt/Quranic-Linguistics-Observatory;
// the JSON files are the site's public data (curl them from
// https://www.quranobservatory.org/data/). Node 22.6+ runs the TypeScript.
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { createRequire } from "node:module"

const [siteRepo, statsPath, formsPath, concPath, textPath] = process.argv.slice(2)
if (!siteRepo || !statsPath) {
  console.error("usage: node test/reference-test.mjs <site-repo> <root-stats.json> [form-index.json]")
  process.exit(2)
}

// The site's modules import through its "@/" alias; copy them somewhere the
// imports can be made relative.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "qo-ref-"))
const copy = (from, to, rewrite) => {
  let src = fs.readFileSync(path.join(siteRepo, from), "utf8")
  if (rewrite) src = src.replace(/"@\/lib\/search\/arabicNormalize"/g, '"./arabicNormalize.ts"')
  fs.writeFileSync(path.join(tmp, to), src)
}
copy("lib/search/arabicNormalize.ts", "arabicNormalize.ts")
copy("lib/corpus/rootStatsClient.ts", "rootStatsClient.ts", true)
copy("lib/corpus/formIndexClient.ts", "formIndexClient.ts", true)
copy("lib/data/surahData.ts", "surahData.ts")
{
  const p = path.join(tmp, "concordanceClient.ts")
  copy("lib/corpus/concordanceClient.ts", "concordanceClient.ts", true)
  fs.writeFileSync(p, fs.readFileSync(p, "utf8").replace(/"@\/lib\/data\/surahData"/g, '"./surahData.ts"'))
}

const site = await import(path.join(tmp, "rootStatsClient.ts"))
const siteForms = await import(path.join(tmp, "formIndexClient.ts"))
const M = createRequire(import.meta.url)("../Model.js")

const raw = JSON.parse(fs.readFileSync(statsPath, "utf8"))
const index = M.parseIndex(fs.readFileSync(statsPath, "utf8"))
const rawForms = formsPath ? JSON.parse(fs.readFileSync(formsPath, "utf8")) : null
const forms = formsPath ? M.parseForms(fs.readFileSync(formsPath, "utf8")) : null

let failures = 0
const check = (ok, message) => { if (!ok) { failures++; console.error("FAIL " + message) } }

check(index && index.rootCount === Object.keys(raw.roots).length, `validation kept ${index && index.rootCount} of ${Object.keys(raw.roots).length} roots`)
check(index && index.featured.length === raw.featured.length, "validation kept every featured root")
// Keys carrying leftover Buckwalter marks (ص:طه, الرسولا") are dropped on
// purpose: no typed query reaches them.
const plainKeys = rawForms ? Object.keys(rawForms.forms).filter((k) => /^[ء-يٱ-ۓ]+$/.test(k)) : []
if (forms) {
  check(Object.keys(forms).length === plainKeys.length, "validation kept every plain-Arabic surface form")
  const skipped = Object.keys(rawForms.forms).length - plainKeys.length
  if (skipped) console.log(`note: ${skipped} form keys in the site data carry non-Arabic marks and are skipped`)
}

for (let day = 20000; day < 21000; day++) {
  const a = site.rootOfTheDay(raw, day)?.bare ?? null
  const b = M.rootOfTheDay(index, day)?.bare ?? null
  check(a === b, `root of day ${day}: site ${a}, plugin ${b}`)
}

const queries = [
  "رحمة", "الرحمن", "أمهاتكم", "أم القرى", "قرآن", "القرآن", "قران", "كتب", "يكتبون", "علم", "العلماء",
  "ربكم", "رب", "بالحق", "فاتقوا", "آمنوا", "سماء", "السموات", "الصالحين", "صالح", "رحمان", "اسم", "اسماء",
  "ال", "ي", "ع", "مسلمين", "والذين", "بسم", "الحمد", "يوم", "الدين", "نعبد", "نستعين",
  "mercy", "merc", "knowledge", "knowl", "good", "rHm", "ktb", "kh y r", "god", "book", "patience",
  "sabr", "s b r", "xyz", "light", "Light of the heavens", "day", "ḥ", "r · ḥ · m", "earth", "heaven"
]
for (const q of queries) {
  const a = site.lookupRoot(raw, q)?.bare ?? null
  const b = M.lookupRoot(index, q)?.bare ?? null
  check(a === b, `lookupRoot ${JSON.stringify(q)}: site ${a}, plugin ${b}`)
  if (forms && /[؀-ۿ]/.test(q)) {
    const fa = siteForms.lookupFormRoot(rawForms, q)
    const fb = M.lookupFormRoot(forms, q)
    check(fa === fb, `lookupFormRoot ${JSON.stringify(q)}: site ${fa}, plugin ${fb}`)
  }
}

// Every surface form the corpus has must resolve the same way on both sides.
if (forms) {
  let n = 0
  for (const word of plainKeys) {
    if (++n % 7) continue
    check(siteForms.lookupFormRoot(rawForms, word) === M.lookupFormRoot(forms, word), `form ${word}`)
  }
}

// The concordance: every root's totals must match the root index, and its
// per-sūrah āyah counts and revelation places must match the site's own
// selectConcordance.
let concChecked = false
if (concPath) {
  const siteConc = await import(path.join(tmp, "concordanceClient.ts"))
  const rawConc = JSON.parse(fs.readFileSync(concPath, "utf8"))
  const conc = M.parseConcordance(fs.readFileSync(concPath, "utf8"))
  check(conc !== null, "concordance validates")
  if (textPath) check(M.parseConcordanceText(fs.readFileSync(textPath, "utf8"), conc) !== null, "concordance text lines up with the concordance")
  for (let i = 0; conc && i < rawConc.roots.length; i++) {
    const bare = rawConc.roots[i].bare
    const stat = index.roots[bare]
    const occ = M.rootOccurrences(conc, bare)
    const count = occ.reduce((n, o) => n + o.positions.length, 0)
    check(stat && count === stat.count && occ.length === stat.verses, `concordance totals for ${bare}`)
    check(stat && JSON.stringify(M.distribution(conc, bare).counts) === JSON.stringify(stat.hist), `distribution for ${bare}`)
    const sel = siteConc.selectConcordance(rawConc, [i], "ayah")
    const perSurah = new Array(114).fill(0)
    for (const o of occ) perSurah[o.s - 1]++
    for (const s of sel.surahs) {
      check(s.perRoot[0] === perSurah[s.n - 1], `āyahs of ${bare} in sūrah ${s.n}`)
      check((s.revelationPlace === "makkah") === M.isMakkan(s.n), `revelation place of sūrah ${s.n}`)
    }
  }
  concChecked = true
}

fs.rmSync(tmp, { recursive: true, force: true })
console.log(failures ? `${failures} mismatches` : `reference: plugin matches the site (${queries.length} queries, 1000 days${forms ? ", forms" : ""}${concChecked ? ", concordance" : ""})`)
process.exitCode = failures ? 1 : 0
