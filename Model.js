// Pure data logic for the Quran Observatory widget: validating the root index
// downloaded from quranobservatory.org, picking today's root, and searching.
// Qt-free so it runs under node (test/model-test.js); the QML owns network,
// files and drawing.
//
// The search and the root of the day are ports of the site's own
// lib/corpus/rootStatsClient.ts and lib/search/arabicNormalize.ts, so the bar
// shows the same root as the homepage and a query lands on the same root.
// test/reference-test.mjs checks that against the site's TypeScript.

var SITE = "https://www.quranobservatory.org"
var DATA_URL = SITE + "/data/root-stats.json"
var FORMS_URL = SITE + "/data/form-index.json"

// Everything downloaded is bounded before it reaches the screen.
var LIMITS = {
  bytes: 8 * 1024 * 1024,
  roots: 5000,
  featured: 500,
  text: 64,
  gloss: 80,
  examples: 20,
  words: 200,
  word: 48,
  top: 10,
  pos: 12
}

var SURAH_COUNT = 114
var MAX_AYAH = 286

// [English, Arabic], index 0 = sūrah 1. From the site's lib/data/surahData.ts.
var SURAHS = [
  ["Al-Fatihah", "الفاتحة"], ["Al-Baqarah", "البقرة"], ["Aal-E-Imran", "آل عمران"],
  ["An-Nisa", "النساء"], ["Al-Ma'idah", "المائدة"], ["Al-An'am", "الأنعام"],
  ["Al-A'raf", "الأعراف"], ["Al-Anfal", "الأنفال"], ["At-Tawbah", "التوبة"],
  ["Yunus", "يونس"], ["Hud", "هود"], ["Yusuf", "يوسف"],
  ["Ar-Ra'd", "الرعد"], ["Ibrahim", "إبراهيم"], ["Al-Hijr", "الحجر"],
  ["An-Nahl", "النحل"], ["Al-Isra", "الإسراء"], ["Al-Kahf", "الكهف"],
  ["Maryam", "مريم"], ["Taha", "طه"], ["Al-Anbiya", "الأنبياء"],
  ["Al-Hajj", "الحج"], ["Al-Mu'minun", "المؤمنون"], ["An-Nur", "النور"],
  ["Al-Furqan", "الفرقان"], ["Ash-Shu'ara", "الشعراء"], ["An-Naml", "النمل"],
  ["Al-Qasas", "القصص"], ["Al-Ankabut", "العنكبوت"], ["Ar-Rum", "الروم"],
  ["Luqman", "لقمان"], ["As-Sajdah", "السجدة"], ["Al-Ahzab", "الأحزاب"],
  ["Saba", "سبأ"], ["Fatir", "فاطر"], ["Ya-Sin", "يس"],
  ["As-Saffat", "الصافات"], ["Sad", "ص"], ["Az-Zumar", "الزمر"],
  ["Ghafir", "غافر"], ["Fussilat", "فصلت"], ["Ash-Shura", "الشورى"],
  ["Az-Zukhruf", "الزخرف"], ["Ad-Dukhan", "الدخان"], ["Al-Jathiyah", "الجاثية"],
  ["Al-Ahqaf", "الأحقاف"], ["Muhammad", "محمد"], ["Al-Fath", "الفتح"],
  ["Al-Hujurat", "الحجرات"], ["Qaf", "ق"], ["Adh-Dhariyat", "الذاريات"],
  ["At-Tur", "الطور"], ["An-Najm", "النجم"], ["Al-Qamar", "القمر"],
  ["Ar-Rahman", "الرحمن"], ["Al-Waqi'ah", "الواقعة"], ["Al-Hadid", "الحديد"],
  ["Al-Mujadila", "المجادلة"], ["Al-Hashr", "الحشر"], ["Al-Mumtahanah", "الممتحنة"],
  ["As-Saff", "الصف"], ["Al-Jumu'ah", "الجمعة"], ["Al-Munafiqun", "المنافقون"],
  ["At-Taghabun", "التغابن"], ["At-Talaq", "الطلاق"], ["At-Tahrim", "التحريم"],
  ["Al-Mulk", "الملك"], ["Al-Qalam", "القلم"], ["Al-Haqqah", "الحاقة"],
  ["Al-Ma'arij", "المعارج"], ["Nuh", "نوح"], ["Al-Jinn", "الجن"],
  ["Al-Muzzammil", "المزمل"], ["Al-Muddaththir", "المدثر"], ["Al-Qiyamah", "القيامة"],
  ["Al-Insan", "الإنسان"], ["Al-Mursalat", "المرسلات"], ["An-Naba", "النبأ"],
  ["An-Nazi'at", "النازعات"], ["Abasa", "عبس"], ["At-Takwir", "التكوير"],
  ["Al-Infitar", "الإنفطار"], ["Al-Mutaffifin", "المطففين"], ["Al-Inshiqaq", "الإنشقاق"],
  ["Al-Buruj", "البروج"], ["At-Tariq", "الطارق"], ["Al-A'la", "الأعلى"],
  ["Al-Ghashiyah", "الغاشية"], ["Al-Fajr", "الفجر"], ["Al-Balad", "البلد"],
  ["Ash-Shams", "الشمس"], ["Al-Layl", "الليل"], ["Ad-Duhaa", "الضحى"],
  ["Ash-Sharh", "الشرح"], ["At-Tin", "التين"], ["Al-Alaq", "العلق"],
  ["Al-Qadr", "القدر"], ["Al-Bayyinah", "البينة"], ["Az-Zalzalah", "الزلزلة"],
  ["Al-Adiyat", "العاديات"], ["Al-Qari'ah", "القارعة"], ["At-Takathur", "التكاثر"],
  ["Al-Asr", "العصر"], ["Al-Humazah", "الهمزة"], ["Al-Fil", "الفيل"],
  ["Quraysh", "قريش"], ["Al-Ma'un", "الماعون"], ["Al-Kawthar", "الكوثر"],
  ["Al-Kafirun", "الكافرون"], ["An-Nasr", "النصر"], ["Al-Masad", "المسد"],
  ["Al-Ikhlas", "الإخلاص"], ["Al-Falaq", "الفلق"], ["An-Nas", "الناس"]
]

function surahName(number, arabic) {
  var entry = SURAHS[number - 1]
  if (!entry) return ""
  return arabic ? entry[1] : entry[0]
}

// ---- Validation -----------------------------------------------------------

// Control characters and bidi overrides would reorder or hide what the panel
// draws; nothing in the corpus needs them.
var UNSAFE_CHARS = /[\u0000-\u001F\u007F-\u009F‎‏‪-‮⁦-⁩]/g
// Arabic letters (hamza through yeh, alif wasla and the extended block); a root
// key is never anything else.
var ROOT_KEY = /^[ء-غف-يٱ-ۓ]{1,8}$/

function cleanString(value, max) {
  if (typeof value !== "string") return ""
  var s = value.replace(UNSAFE_CHARS, "")
  return s.length > max ? s.slice(0, max) : s
}

function cleanInt(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  n = Math.round(n)
  return n < min ? min : (n > max ? max : n)
}

function cleanSurah(value) {
  var n = Number(value)
  return isFinite(n) && n >= 1 && n <= SURAH_COUNT ? Math.round(n) : 0
}

function cleanExample(raw) {
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.words)) return null
  var s = cleanSurah(raw.s)
  var a = cleanInt(raw.a, 0, MAX_AYAH)
  if (!s || !a) return null
  var words = []
  for (var i = 0; i < raw.words.length && words.length < LIMITS.words; i++) {
    var w = raw.words[i]
    if (!w || typeof w !== "object") continue
    var t = cleanString(w.t, LIMITS.word)
    if (!t) continue
    words.push({ t: t, root: cleanString(w.root, 12), pos: cleanString(w.pos, 12) })
  }
  if (!words.length) return null
  return { s: s, a: a, w: cleanInt(raw.w, 0, LIMITS.words), words: words }
}

function cleanRoot(raw, key) {
  if (!raw || typeof raw !== "object" || !ROOT_KEY.test(key)) return null
  if (cleanString(raw.bare, 12) !== key) return null

  var hist = []
  var rawHist = Array.isArray(raw.hist) ? raw.hist : []
  for (var h = 0; h < SURAH_COUNT; h++) hist.push(cleanInt(rawHist[h], 0, 100000))

  var top = []
  var rawTop = Array.isArray(raw.top) ? raw.top : []
  for (var t = 0; t < rawTop.length && top.length < LIMITS.top; t++) {
    var row = rawTop[t]
    if (!Array.isArray(row)) continue
    var sura = cleanSurah(row[0])
    if (sura) top.push([sura, cleanInt(row[1], 0, 100000), cleanInt(row[2], 0, MAX_AYAH)])
  }

  var pos = []
  var rawPos = Array.isArray(raw.pos) ? raw.pos : []
  for (var p = 0; p < rawPos.length && pos.length < LIMITS.pos; p++) {
    var pr = rawPos[p]
    if (Array.isArray(pr) && cleanString(pr[0], 12)) pos.push([cleanString(pr[0], 12), cleanInt(pr[1], 0, 100000)])
  }

  var examples = []
  var rawEx = Array.isArray(raw.examples) ? raw.examples : []
  for (var e = 0; e < rawEx.length && examples.length < LIMITS.examples; e++) {
    var ex = cleanExample(rawEx[e])
    if (ex) examples.push(ex)
  }

  var first = null
  if (raw.first && typeof raw.first === "object" && cleanSurah(raw.first.sura))
    first = { sura: cleanSurah(raw.first.sura), ayah: cleanInt(raw.first.ayah, 1, MAX_AYAH) }

  return {
    root: cleanString(raw.root, LIMITS.text) || key,
    bare: key,
    bw: cleanString(raw.bw, LIMITS.text),
    translit: cleanString(raw.translit, LIMITS.text),
    gloss: cleanString(raw.gloss, LIMITS.gloss),
    count: cleanInt(raw.count, 0, 100000),
    surahs: cleanInt(raw.surahs, 0, SURAH_COUNT),
    verses: cleanInt(raw.verses, 0, 10000),
    forms: cleanInt(raw.forms, 0, 10000),
    first: first,
    top: top,
    hist: hist,
    pos: pos,
    examples: examples
  }
}

// The validated index, with the search tables built once, or null when the
// data is not a root index at all.
function sanitize(raw) {
  if (!raw || typeof raw !== "object" || !raw.roots || typeof raw.roots !== "object" || Array.isArray(raw.roots)) return null

  var roots = {}
  var count = 0
  for (var key in raw.roots) {
    if (!Object.prototype.hasOwnProperty.call(raw.roots, key)) continue
    if (count >= LIMITS.roots) break
    var r = cleanRoot(raw.roots[key], key)
    if (r) { roots[key] = r; count++ }
  }
  if (!count) return null

  var featured = []
  var rawFeatured = Array.isArray(raw.featured) ? raw.featured : []
  for (var i = 0; i < rawFeatured.length && featured.length < LIMITS.featured; i++) {
    var bare = rawFeatured[i]
    if (typeof bare === "string" && Object.prototype.hasOwnProperty.call(roots, bare)) featured.push(bare)
  }

  var index = { version: cleanInt(raw.version, 0, 1000), rootCount: count, featured: featured, roots: roots }
  buildSearchTables(index)
  return index
}

function parseIndex(text) {
  if (typeof text !== "string" || !text.length || text.length > LIMITS.bytes) return null
  var raw
  try { raw = JSON.parse(text) } catch (e) { return null }
  return sanitize(raw)
}

// ---- Root of the day ------------------------------------------------------

// Whole days since the epoch on the local calendar. The site computes exactly
// this in the browser, so both roll over at local midnight.
function epochDay(date) {
  return Math.floor((date.getTime() - date.getTimezoneOffset() * 60000) / 86400000)
}

function rootOfTheDay(index, day) {
  if (!index || !index.featured.length) return null
  var n = index.featured.length
  var bare = index.featured[((day % n) + n) % n]
  return index.roots[bare] || null
}

// ---- Normalisation (ported from the site) ---------------------------------

// rootStatsClient.ts normalizeArabic: harakat, dagger alif, tatweel,
// separators; hamza-bearing alifs fold to a bare alif.
function normalizeArabic(s) {
  return String(s)
    .replace(/[ً-ْٰـ]/g, "")
    .replace(/[\s\-·.]/g, "")
    .replace(/[آأإٱ]/g, "ا")
    .trim()
}

// rootStatsClient.ts normalizeLatin: lowercase, accents and ʿ ʾ dropped.
function normalizeLatin(s) {
  return String(s)
    .normalize("NFD")
    .replace(/[̀-ͯʿʾˀ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "")
}

// arabicNormalize.ts normalizeArabicForSearch.
function normalizeArabicForSearch(value) {
  return String(value)
    .trim()
    .normalize("NFKD")
    .replace(/[ً-ٰٟۖ-ۭ]/g, "")
    .replace(/ـ/g, "")
    .replace(/[ٱأإآ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/ؤ/g, "و")
    .replace(/ئ/g, "ي")
    .replace(/ة/g, "ه")
    .replace(/\s+/g, " ")
}

// Inside a root every alif or hamza carrier is the hamza consonant.
function normRootKey(s) {
  return s.replace(/[اأإآٱئؤ]/g, "ء")
}

var ARABIC_CHAR = /[؀-ۿ]/
var AR_PREFIXES = ["ال", "و", "ف", "ب", "ل", "لل", "وال", "بال"]
var AR_SUFFIXES = ["ات", "ون", "ين", "ان", "كم", "هم", "هن", "نا", "ها", "ة", "ه", "ي", "ا", "ن", "ت"]

function buildSearchTables(index) {
  var byCount = []
  for (var k in index.roots) byCount.push(index.roots[k])
  byCount.sort(function(a, b) { return b.count - a.count })

  // Term -> bare root, highest count first, in insertion order (Maps keep it),
  // so prefix scans land on the most frequent root.
  var terms = new Map()
  var add = function(term, bare) { if (term && !terms.has(term)) terms.set(term, bare) }
  var normMap = new Map()
  for (var i = 0; i < byCount.length; i++) {
    var r = byCount[i]
    add(normalizeLatin(r.bw), r.bare)
    add(normalizeLatin(r.translit), r.bare)
    if (r.gloss) {
      var words = r.gloss.split(/[^a-zA-Z]+/)
      for (var w = 0; w < words.length; w++) {
        var lw = normalizeLatin(words[w])
        if (lw.length >= 2) add(lw, r.bare)
      }
    }
    var n = normRootKey(r.bare)
    if (!normMap.has(n)) normMap.set(n, r.bare)
    r.searchKey = normalizeArabicForSearch(r.bare)
  }
  index.byCount = byCount
  index.terms = terms
  index.normMap = normMap
}

function matchRoot(index, s) {
  if (Object.prototype.hasOwnProperty.call(index.roots, s)) return index.roots[s]
  var viaNorm = index.normMap.get(normRootKey(s))
  return viaNorm ? index.roots[viaNorm] || null : null
}

// One Arabic word to a root: exact, de-affixed, geminate, then prefix.
function lookupArabicWord(index, word) {
  var ar = normalizeArabic(word)
  if (!ar) return null

  var direct = matchRoot(index, ar)
  if (direct) return direct

  var seen = new Set([ar])
  var frontier = [ar]
  for (var depth = 0; depth < 3 && frontier.length; depth++) {
    var next = []
    for (var f = 0; f < frontier.length; f++) {
      var cur = frontier[f]
      for (var p = 0; p < AR_PREFIXES.length; p++) {
        var pre = AR_PREFIXES[p]
        if (cur.startsWith(pre) && cur.length - pre.length >= 2) {
          var c1 = cur.slice(pre.length)
          if (!seen.has(c1)) { seen.add(c1); next.push(c1) }
        }
      }
      for (var s = 0; s < AR_SUFFIXES.length; s++) {
        var suf = AR_SUFFIXES[s]
        if (cur.endsWith(suf) && cur.length - suf.length >= 2) {
          var c2 = cur.slice(0, cur.length - suf.length)
          if (!seen.has(c2)) { seen.add(c2); next.push(c2) }
        }
      }
    }
    frontier = next
  }
  // Stable sort, longest first, as the site's spread-then-sort does.
  var candidates = Array.from(seen).sort(function(a, b) { return b.length - a.length })
  for (var i = 0; i < candidates.length; i++) {
    var hit = matchRoot(index, candidates[i])
    if (hit) return hit
  }
  // Two-letter stems are often geminate roots: أم -> امم.
  for (var j = 0; j < candidates.length; j++) {
    if (candidates[j].length === 2) {
      var gem = matchRoot(index, candidates[j] + candidates[j][1])
      if (gem) return gem
    }
  }
  if (ar.length >= 2) {
    var nq = normRootKey(ar)
    for (var r = 0; r < index.byCount.length; r++) {
      var b = index.byCount[r].bare
      if (b.startsWith(ar) || normRootKey(b).startsWith(nq)) return index.roots[b]
    }
  }
  return null
}

function lookupLatin(index, s) {
  var lat = normalizeLatin(s)
  if (!lat) return null
  var bare = index.terms.get(lat)
  if (bare) return index.roots[bare] || null
  if (lat.length >= 3) {
    var it = index.terms.entries()
    for (var e = it.next(); !e.done; e = it.next())
      if (e.value[0].startsWith(lat)) return index.roots[e.value[1]] || null
  }
  return null
}

// The site's lookupRoot: free text to the one root it means, or null.
function lookupRoot(index, query) {
  var q = String(query || "").trim()
  if (!index || !q) return null

  if (ARABIC_CHAR.test(q)) {
    var whole = lookupArabicWord(index, q)
    if (whole) return whole
    var words = q.split(/\s+/).filter(function(w) { return ARABIC_CHAR.test(w) })
    if (words.length > 1) {
      for (var i = 0; i < words.length; i++) {
        var hit = lookupArabicWord(index, words[i])
        if (hit) return hit
      }
    }
    return null
  }

  var latin = lookupLatin(index, q)
  if (latin) return latin
  var parts = q.split(/[^a-zA-Z]+/).filter(function(w) { return w.length >= 3 })
  if (parts.length > 1) {
    for (var j = 0; j < parts.length; j++) {
      var h = lookupLatin(index, parts[j])
      if (h) return h
    }
  }
  return null
}

// ---- Inflected words (formIndexClient.ts) ---------------------------------
//
// form-index.json maps the corpus's surface words to their roots, so يكتبون
// finds كتب and آمنوا finds امن. Optional: search works without it, just less
// forgivingly.

var FORM_LIMIT = 100000
var FORM_KEY = /^[ء-يٱ-ۓ]{1,24}$/
var PROCLITIC = /^(وال|فال|بال|كال|لل|ال|و|ف|ب|ك|ل)/

// Surface form -> bare root, or null when the data is not a form index.
function sanitizeForms(raw) {
  if (!raw || typeof raw !== "object" || !raw.forms || typeof raw.forms !== "object" || Array.isArray(raw.forms)) return null
  var forms = Object.create(null)
  var count = 0
  for (var key in raw.forms) {
    if (!Object.prototype.hasOwnProperty.call(raw.forms, key)) continue
    if (count >= FORM_LIMIT) break
    var value = raw.forms[key]
    if (FORM_KEY.test(key) && typeof value === "string" && ROOT_KEY.test(value)) { forms[key] = value; count++ }
  }
  return count ? forms : null
}

function parseForms(text) {
  if (typeof text !== "string" || !text.length || text.length > LIMITS.bytes) return null
  var raw
  try { raw = JSON.parse(text) } catch (e) { return null }
  return sanitizeForms(raw)
}

// آ (composed, and alif + madda) is written ءا in much of the corpus.
function foldMaddaToHamzaAlef(value) {
  return String(value).replace(/آ/g, "ءا").replace(/آ/g, "ءا")
}

function foldHamza(value) {
  return value.replace(/ء/g, "")
}

// Drop the medial long alif the Uthmani rasm usually omits: صالح -> صلح.
function foldRasmAlef(normalized) {
  if (normalized.length <= 2) return normalized
  return normalized[0] + normalized.slice(1, -1).replace(/ا/g, "") + normalized[normalized.length - 1]
}

function searchKeyVariants(query) {
  var out = []
  var add = function(k) { if (k && k.length >= 2 && out.indexOf(k) < 0) out.push(k) }
  var keys = [normalizeArabicForSearch(query), normalizeArabicForSearch(foldMaddaToHamzaAlef(query))]
  for (var i = 0; i < keys.length; i++) { add(keys[i]); add(foldHamza(keys[i])) }
  return out
}

function lookupFormRoot(forms, query) {
  if (!forms) return null
  var variants = searchKeyVariants(query)
  var resolve = function(k) {
    if (forms[k]) return forms[k]
    var stripped = k.replace(PROCLITIC, "")
    return stripped.length >= 2 && forms[stripped] ? forms[stripped] : null
  }
  // Direct spellings first, the rasm fold only after: a bridged hit beats an
  // over-fold that lands on the wrong root (قران -> قرن).
  for (var i = 0; i < variants.length; i++) {
    var hit = resolve(variants[i])
    if (hit) return hit
  }
  for (var j = 0; j < variants.length; j++) {
    var folded = foldRasmAlef(variants[j])
    if (folded !== variants[j]) {
      var h = resolve(folded)
      if (h) return h
    }
  }
  return null
}

// The result list, in the homepage's order: the root lookup, then the root
// of the inflected word, then the roots the query could be the start of,
// most frequent first.
function search(index, query, limit, forms) {
  var q = String(query || "").trim()
  if (!index || !q) return []
  var max = limit > 0 ? limit : 8
  var out = []
  var seen = {}
  var push = function(r) {
    if (r && !seen[r.bare] && out.length < max) { seen[r.bare] = true; out.push(r) }
  }

  push(lookupRoot(index, q))
  if (forms && ARABIC_CHAR.test(q)) {
    var formRoot = lookupFormRoot(forms, q)
    if (formRoot && Object.prototype.hasOwnProperty.call(index.roots, formRoot)) push(index.roots[formRoot])
  }

  if (ARABIC_CHAR.test(q)) {
    var qn = normalizeArabicForSearch(q)
    if (qn) for (var i = 0; i < index.byCount.length && out.length < max; i++)
      if (index.byCount[i].searchKey.startsWith(qn)) push(index.byCount[i])
  } else {
    var lat = normalizeLatin(q)
    if (lat.length >= 2) {
      var it = index.terms.entries()
      for (var e = it.next(); !e.done && out.length < max; e = it.next())
        if (e.value[0].startsWith(lat)) push(index.roots[e.value[1]])
    }
  }
  return out
}

// ---- Presentation helpers -------------------------------------------------

// The verse as words, with the root's own words marked.
function verseWords(example, bare) {
  if (!example) return []
  return example.words.map(function(w) { return { t: w.t, hit: w.root === bare } })
}

function compactTranslit(translit) {
  return String(translit || "").replace(/\s*·\s*/g, "·")
}

// Gloss when the site has one, otherwise the romanised skeleton.
function meaning(root) {
  if (!root) return ""
  return root.gloss || root.translit
}

var LABEL_STYLES = ["Root and meaning", "Root", "Transliteration and meaning", "Icon only"]

// The bar label without its direction mark; the QML adds one for the
// interface direction so Arabic and English sit in a predictable order.
// countText is the formatted occurrence count ("196×"), or "" to leave it off.
function barLabel(root, style, countText) {
  if (!root || style === "Icon only") return ""
  var label
  if (style === "Root") label = root.root
  else if (style === "Transliteration and meaning")
    label = compactTranslit(root.translit) + (root.gloss ? " · " + root.gloss : "")
  else
    label = root.root + (root.gloss ? " · " + root.gloss : (root.translit ? " · " + compactTranslit(root.translit) : ""))
  return countText ? label + " · " + countText : label
}

// One line for scripts: `qs ipc call … today`.
function todayText(root) {
  if (!root) return ""
  var parts = [root.root]
  if (root.translit) parts.push("(" + root.translit + ")")
  var s = parts.join(" ")
  if (root.gloss) s += " - " + root.gloss
  return s + " - " + root.count + " occurrences"
}

// Bar heights 0..1 per sūrah.
function histogramLevels(hist) {
  var max = 0
  for (var i = 0; i < hist.length; i++) if (hist[i] > max) max = hist[i]
  return hist.map(function(v) { return max > 0 ? v / max : 0 })
}

var POS_KEYS = { N: "noun", V: "verb", ADJ: "adjective", PN: "properNoun", P: "particle", PRON: "pronoun", ADV: "adverb", IMPN: "imperativeNoun" }

function posKey(code) {
  return POS_KEYS[code] || ""
}

function siteLanguage(omarchyLanguage) {
  return String(omarchyLanguage || "").split("-")[0] === "ar" ? "ar" : "en"
}

function rootUrl(bare, lang) {
  return SITE + "/" + (lang === "ar" ? "ar" : "en") + "?q=" + encodeURIComponent(String(bare || ""))
}

function searchUrl(query, lang) {
  return SITE + "/" + (lang === "ar" ? "ar" : "en") + "/search?q=" + encodeURIComponent(String(query || ""))
}

// ---- Updates --------------------------------------------------------------

var UPDATE_INTERVALS = { "Daily": 86400, "Weekly": 7 * 86400, "Off": 0 }
// After a failed download, wait this long before trying again on our own.
var RETRY_SECONDS = 3600

// mtimeSeconds is the cached file's age stamp, 0 when there is no file.
function needsDownload(mtimeSeconds, nowMs, interval, lastAttemptMs) {
  var every = UPDATE_INTERVALS[interval]
  if (every === undefined) every = UPDATE_INTERVALS.Weekly
  if (!every) return false
  if (lastAttemptMs > 0 && nowMs - lastAttemptMs < RETRY_SECONDS * 1000) return false
  if (!(mtimeSeconds > 0)) return true
  return nowMs / 1000 - mtimeSeconds >= every
}

function moveSelection(index, delta, count) {
  if (count <= 0) return 0
  return ((index + delta) % count + count) % count
}

if (typeof module !== "undefined") {
  module.exports = {
    SITE: SITE,
    DATA_URL: DATA_URL,
    FORMS_URL: FORMS_URL,
    LIMITS: LIMITS,
    SURAHS: SURAHS,
    LABEL_STYLES: LABEL_STYLES,
    surahName: surahName,
    cleanString: cleanString,
    sanitize: sanitize,
    parseIndex: parseIndex,
    epochDay: epochDay,
    rootOfTheDay: rootOfTheDay,
    normalizeArabic: normalizeArabic,
    normalizeLatin: normalizeLatin,
    normalizeArabicForSearch: normalizeArabicForSearch,
    lookupRoot: lookupRoot,
    sanitizeForms: sanitizeForms,
    parseForms: parseForms,
    lookupFormRoot: lookupFormRoot,
    search: search,
    verseWords: verseWords,
    compactTranslit: compactTranslit,
    meaning: meaning,
    barLabel: barLabel,
    todayText: todayText,
    histogramLevels: histogramLevels,
    posKey: posKey,
    siteLanguage: siteLanguage,
    rootUrl: rootUrl,
    searchUrl: searchUrl,
    needsDownload: needsDownload,
    moveSelection: moveSelection
  }
}
