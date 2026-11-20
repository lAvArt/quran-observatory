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
var CONCORDANCE_URL = SITE + "/data/concordance.json"
var CONCORDANCE_TEXT_URL = SITE + "/data/concordance-text.json"

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

// The first sense only ("to believe / trust" -> "to believe"), for labels
// with room for a word or two.
function shortMeaning(root) {
  if (!root) return ""
  if (root.gloss) return root.gloss.split(/\s*[\/;]\s*/)[0]
  return root.translit
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

// ---- Concordance ----------------------------------------------------------
//
// concordance.json maps every word of every āyah to its root (an index into
// its own root list, -1 for a word without one); concordance-text.json holds
// the words themselves, in the same shape. Together they answer what the
// root index alone cannot: which roots share āyahs with this one, every
// occurrence in context, and how it spreads across the sūrahs.

// K = Makkan, D = Madinan, sūrah 1 first. From the site's surahData.ts.
var REVELATION = "KDDDDKKDDKKKDKKKKKKKKDKDKKKKKKKKDKKKKKKKKKKKKKDDDKKKKKDKDDDDDDDDDDKKKKKKKKKDKKKKKKKKKKKKKKKKKKKKKDDKKKKKKKKKKDKKKK"

function isMakkan(surah) {
  return REVELATION.charAt(surah - 1) === "K"
}

var CONCORDANCE_LIMITS = { ayahs: 7000, ayahsPerSurah: 300, wordsPerAyah: 200 }

// { roots: [bare], lookup: {bare: index}, surahs: [[[rootIndex]]], words:
// [per-sūrah word count], totalWords, totalAyahs }, or null. Root indices
// stay aligned with the file even when an entry is rejected; words pointing
// at a rejected or out-of-range root count as rootless.
function sanitizeConcordance(raw) {
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.roots) || !Array.isArray(raw.surahs)) return null
  if (raw.surahs.length !== SURAH_COUNT || raw.roots.length > LIMITS.roots) return null

  var roots = []
  var lookup = Object.create(null)
  for (var r = 0; r < raw.roots.length; r++) {
    var entry = raw.roots[r]
    var bare = entry && typeof entry === "object" && typeof entry.bare === "string" && ROOT_KEY.test(entry.bare) ? entry.bare : ""
    roots.push(bare)
    if (bare && lookup[bare] === undefined) lookup[bare] = r
  }

  var surahs = []
  var words = []
  var totalWords = 0
  var totalAyahs = 0
  for (var s = 0; s < SURAH_COUNT; s++) {
    var rs = raw.surahs[s]
    if (!rs || typeof rs !== "object" || !Array.isArray(rs.ayahs) || !rs.ayahs.length || rs.ayahs.length > CONCORDANCE_LIMITS.ayahsPerSurah) return null
    var ayahs = []
    var count = 0
    for (var a = 0; a < rs.ayahs.length; a++) {
      var ra = rs.ayahs[a]
      if (!Array.isArray(ra) || ra.length > CONCORDANCE_LIMITS.wordsPerAyah) return null
      var ayah = []
      for (var w = 0; w < ra.length; w++) {
        var v = ra[w]
        ayah.push(typeof v === "number" && v >= 0 && v < roots.length && v === Math.floor(v) && roots[v] ? v : -1)
      }
      ayahs.push(ayah)
      count += ayah.length
    }
    totalAyahs += ayahs.length
    if (totalAyahs > CONCORDANCE_LIMITS.ayahs) return null
    surahs.push(ayahs)
    words.push(count)
    totalWords += count
  }
  return { roots: roots, lookup: lookup, surahs: surahs, words: words, totalWords: totalWords, totalAyahs: totalAyahs }
}

function parseConcordance(text) {
  if (typeof text !== "string" || !text.length || text.length > LIMITS.bytes) return null
  var raw
  try { raw = JSON.parse(text) } catch (e) { return null }
  return sanitizeConcordance(raw)
}

// The words of every āyah, or null unless they line up word for word with
// the concordance: a word's root is found by its position.
function sanitizeConcordanceText(raw, conc) {
  if (!conc || !raw || typeof raw !== "object" || !Array.isArray(raw.surahs) || raw.surahs.length !== SURAH_COUNT) return null
  var out = []
  for (var s = 0; s < SURAH_COUNT; s++) {
    var rs = raw.surahs[s]
    if (!Array.isArray(rs) || rs.length !== conc.surahs[s].length) return null
    var ayahs = []
    for (var a = 0; a < rs.length; a++) {
      var ra = rs[a]
      if (!Array.isArray(ra) || ra.length !== conc.surahs[s][a].length) return null
      var ayah = []
      for (var w = 0; w < ra.length; w++) ayah.push(cleanString(ra[w], LIMITS.word))
      ayahs.push(ayah)
    }
    out.push(ayahs)
  }
  return out
}

function parseConcordanceText(text, conc) {
  if (!conc || typeof text !== "string" || !text.length || text.length > LIMITS.bytes) return null
  var raw
  try { raw = JSON.parse(text) } catch (e) { return null }
  return sanitizeConcordanceText(raw, conc)
}

// Every āyah holding the root, in mushaf order, with the word positions
// (0-based) where it stands.
function rootOccurrences(conc, bare) {
  if (!conc || conc.lookup[bare] === undefined) return []
  var target = conc.lookup[bare]
  var out = []
  for (var s = 0; s < SURAH_COUNT; s++) {
    var ayahs = conc.surahs[s]
    for (var a = 0; a < ayahs.length; a++) {
      var positions = null
      for (var w = 0; w < ayahs[a].length; w++) {
        if (ayahs[a][w] === target) (positions || (positions = [])).push(w)
      }
      if (positions) out.push({ s: s + 1, a: a + 1, positions: positions })
    }
  }
  return out
}

// The roots that keep this one company: shared āyahs, ranked by local mutual
// information (shared × PMI). Plain counts would always crown the commonest
// roots (God, say, be); plain PMI, a root met three times. versesOf(bare)
// gives a root's āyah count; roots sharing fewer than minShared are left out.
function companions(conc, bare, versesOf, limit, minShared) {
  var occ = rootOccurrences(conc, bare)
  if (!occ.length) return []
  var target = conc.lookup[bare]
  var max = limit > 0 ? limit : 8
  var floor = minShared > 0 ? minShared : 3
  var shared = Object.create(null)
  for (var i = 0; i < occ.length; i++) {
    var ayah = conc.surahs[occ[i].s - 1][occ[i].a - 1]
    var seen = Object.create(null)
    for (var w = 0; w < ayah.length; w++) {
      var r = ayah[w]
      if (r < 0 || r === target || seen[r]) continue
      seen[r] = true
      shared[r] = (shared[r] || 0) + 1
    }
  }
  var n = conc.totalAyahs
  var fx = occ.length
  var out = []
  for (var key in shared) {
    var count = shared[key]
    if (count < floor) continue
    var other = conc.roots[key]
    var fy = versesOf(other)
    if (!(fy > 0)) continue
    var pmi = Math.log(count * n / (fx * fy)) / Math.LN2
    if (pmi <= 0) continue
    out.push({ bare: other, shared: count, pmi: pmi, score: count * pmi })
  }
  out.sort(function(x, y) { return y.score - x.score || y.shared - x.shared })
  return out.slice(0, max)
}

// Keyword-in-context: one line per occurrence, with up to `context` words
// either side. Lines run in mushaf order.
function concordanceLines(conc, text, bare, context, limit) {
  if (!text) return []
  var occ = rootOccurrences(conc, bare)
  var span = context > 0 ? context : 4
  var max = limit > 0 ? limit : 5000
  var out = []
  for (var i = 0; i < occ.length && out.length < max; i++) {
    var words = text[occ[i].s - 1][occ[i].a - 1]
    for (var p = 0; p < occ[i].positions.length && out.length < max; p++) {
      var at = occ[i].positions[p]
      out.push({
        s: occ[i].s,
        a: occ[i].a,
        before: words.slice(Math.max(0, at - span), at).join(" "),
        word: words[at],
        after: words.slice(at + 1, at + 1 + span).join(" "),
        clippedBefore: at - span > 0,
        clippedAfter: at + 1 + span < words.length
      })
    }
  }
  return out
}

// How the root spreads: occurrences per sūrah, the same per thousand words
// (so long sūrahs don't win by length), and the Makkan / Madinan split set
// against how much of the text each group holds.
function distribution(conc, bare) {
  var counts = []
  for (var i = 0; i < SURAH_COUNT; i++) counts.push(0)
  var occ = rootOccurrences(conc, bare)
  for (var o = 0; o < occ.length; o++) counts[occ[o].s - 1] += occ[o].positions.length
  var density = []
  var makkan = 0
  var madinan = 0
  var makkanWords = 0
  var total = 0
  for (var s = 0; s < SURAH_COUNT; s++) {
    var words = conc ? conc.words[s] : 0
    density.push(words > 0 ? counts[s] * 1000 / words : 0)
    total += counts[s]
    if (isMakkan(s + 1)) { makkan += counts[s]; makkanWords += words } else madinan += counts[s]
  }
  return {
    counts: counts,
    density: density,
    total: total,
    makkan: makkan,
    madinan: madinan,
    makkanShare: total > 0 ? makkan / total : 0,
    makkanWordShare: conc && conc.totalWords > 0 ? makkanWords / conc.totalWords : 0
  }
}

// ---- Graphs drawn the way quranobservatory.org draws them ------------------

// The site's "Where it occurs · by sūrah" strip (MinimalHome SurahStrip): a
// bar per sūrah, 3 + v * (H - 12) tall; bars at or under 26% of the busiest
// stay grey, the rest take the accent, solid above 60% and at 55% between.
function surahStrip(hist) {
  var max = Math.max(1, maxOf(hist))
  return hist.map(function(count) {
    var v = count / max
    var faint = v <= 0.26
    return { count: count, v: v, accent: count > 0 && !faint, opacity: v > 0.6 || faint ? 1 : 0.55 }
  })
}

// Deterministic randomness, so a root's graph looks the same every time.
function hashString(s) {
  var h = 2166136261
  for (var i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

function mulberry32(seed) {
  var a = seed >>> 0
  return function() {
    a = (a + 0x6D2B79F5) | 0
    var t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// The site's collocation burst (CollocationNetworkGraph), fitted to a panel:
// companions fan out around the root, stronger ties (higher PMI)
// nearer the centre and drawn larger, each trailing a few tendril dots - more
// for more shared āyahs. The site settles overlaps with a force simulation;
// here a few rounds of pairwise pushing do the same for a dozen-odd labels.
function collocationLayout(list, seed, width, height) {
  var out = { nodes: [], tendrils: [], stars: [] }
  var n = list.length
  var starRng = mulberry32(hashString("stars:" + seed))
  for (var s = 0; s < 46; s++)
    out.stars.push({ x: starRng() * width, y: starRng() * height, r: 0.3 + starRng() * 0.9 })
  if (!n || width <= 0 || height <= 0) return out

  var lo = Infinity, hi = -Infinity, maxShared = 1
  for (var i = 0; i < n; i++) {
    lo = Math.min(lo, list[i].pmi)
    hi = Math.max(hi, list[i].pmi)
    maxShared = Math.max(maxShared, list[i].shared)
  }
  if (lo === hi) { lo -= 1; hi += 1 }

  var marginX = 34, marginY = 20
  var cx = width / 2, cy = height / 2
  var rx = width / 2 - marginX, ry = height / 2 - marginY
  // The site deals companions into a few hashed sectors, which suits its
  // full-page canvas; in a panel that bunches them on one side, so here they
  // go evenly round the root (seeded start, a little jitter).
  var start = -Math.PI / 2 + (mulberry32(hashString("start:" + seed))() - 0.5) * 0.6
  for (var k = 0; k < n; k++) {
    var c = list[k]
    var rng = mulberry32(hashString(seed + ":" + c.bare + ":" + k))
    var t = Math.max(0, Math.min(1, (c.pmi - lo) / (hi - lo)))
    var angle = start + 2 * Math.PI * k / n + (rng() - 0.5) * 0.35
    var dist = 0.36 + (1 - t) * 0.5 + rng() * 0.12
    out.nodes.push({
      bare: c.bare, shared: c.shared, pmi: c.pmi, t: t,
      r: 4 + Math.sqrt(t) * 6,
      angle: angle,
      x: cx + Math.cos(angle) * rx * dist,
      y: cy + Math.sin(angle) * ry * dist,
      rng: rng
    })
  }

  // Keep label boxes (a dot with its label under it, about 46 x 40) apart, clear of the root
  // in the middle, and inside the frame.
  var nodes = out.nodes
  for (var round = 0; round < 80; round++) {
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b < n; b++) {
        var dx = nodes[b].x - nodes[a].x, dy = nodes[b].y - nodes[a].y
        var d = Math.sqrt((dx / 46) * (dx / 46) + (dy / 40) * (dy / 40))
        if (d >= 1) continue
        if (d < 1e-6) { dx = 1; dy = 0; d = 1e-6 }
        var push = (1 - d) / 2
        var ux = dx / (d * 46), uy = dy / (d * 40)
        nodes[a].x -= ux * push * 46; nodes[a].y -= uy * push * 40
        nodes[b].x += ux * push * 46; nodes[b].y += uy * push * 40
      }
      var ox = nodes[a].x - cx, oy = nodes[a].y - cy
      var od = Math.sqrt((ox / 52) * (ox / 52) + (oy / 34) * (oy / 34))
      if (od < 1) {
        var f = od < 1e-6 ? 1 : 1 / od
        nodes[a].x = cx + (od < 1e-6 ? 52 : ox * f)
        nodes[a].y = cy + oy * f
      }
      nodes[a].x = Math.max(marginX, Math.min(width - marginX, nodes[a].x))
      nodes[a].y = Math.max(marginY, Math.min(height - marginY - 12, nodes[a].y))
    }
  }

  for (var m = 0; m < n; m++) {
    var node = nodes[m]
    var tr = node.rng
    var count = Math.max(2, Math.min(7, Math.round(2 + 4 * node.shared / maxShared + node.t * 2)))
    var away = Math.atan2(node.y - cy, node.x - cx)
    for (var q = 0; q < count; q++) {
      var ta = away + (tr() - 0.5) * 1.1
      var td = 12 + tr() * 30
      out.tendrils.push({
        parent: m,
        x: Math.max(4, Math.min(width - 4, node.x + Math.cos(ta) * td)),
        y: Math.max(4, Math.min(height - 4, node.y + Math.sin(ta) * td * 0.8)),
        r: 1 + tr() * 1.3 + node.t * 0.6
      })
    }
    delete node.rng
  }
  return out
}

// The site's concordance rings (concordanceClient selectConcordance): every
// sūrah a ring, every āyah a tick at (i - ½) / N round it, lit where the
// chosen roots occur; a meeting is an āyah holding all of them. With "ayah"
// a sūrah qualifies when it has a meeting, with "surah" when each root is
// somewhere in it. One to three roots, given as bare forms.
function concordanceRings(conc, bares, meetIn) {
  if (!conc) return null
  var picked = []
  for (var p = 0; p < bares.length && picked.length < 3; p++) {
    var at = conc.lookup[bares[p]]
    if (at !== undefined && picked.indexOf(at) < 0) picked.push(at)
  }
  if (!picked.length) return null
  var all = (1 << picked.length) - 1
  var rings = []
  var totalMeetings = 0
  for (var s = 0; s < SURAH_COUNT; s++) {
    var ayahs = conc.surahs[s]
    var n = ayahs.length
    var words = []
    var hits = []
    var meetings = []
    var perRoot = picked.map(function() { return 0 })
    var maxWords = 1
    for (var i = 0; i < n; i++) {
      var ayah = ayahs[i]
      words.push(ayah.length)
      if (ayah.length > maxWords) maxWords = ayah.length
      var mask = 0
      for (var w = 0; w < ayah.length; w++) {
        var slot = ayah[w] < 0 ? -1 : picked.indexOf(ayah[w])
        if (slot >= 0) mask |= 1 << slot
      }
      if (!mask) continue
      var hit = { ayah: i + 1, mask: mask, words: ayah.length, pos: (i + 0.5) / n, meeting: mask === all }
      for (var b = 0; b < picked.length; b++) if (mask & (1 << b)) perRoot[b]++
      hits.push(hit)
      if (hit.meeting) meetings.push(hit)
    }
    var qualifies = meetIn === "surah" ? perRoot.every(function(c) { return c > 0 }) : meetings.length > 0
    totalMeetings += meetings.length
    rings.push({ n: s + 1, makkan: isMakkan(s + 1), ayahCount: n, words: words, maxWords: maxWords, hits: hits, meetings: meetings, perRoot: perRoot, qualifies: qualifies })
  }
  return {
    roots: picked.map(function(i) { return conc.roots[i] }),
    rings: rings,
    qualifying: rings.filter(function(r) { return r.qualifies }),
    totalMeetings: totalMeetings
  }
}

// Ring order, inside to out, as the site offers it: mushaf order (114 at the
// centre, 1 outermost), short to long, or by where the first meeting falls
// (rings without one go last) - the order that, aligned, turns the meetings'
// spiral into a column.
function ringOrder(rings, mode) {
  var out = rings.slice()
  if (mode === "length") {
    out.sort(function(a, b) { return a.ayahCount - b.ayahCount || b.n - a.n })
  } else if (mode === "first") {
    out.sort(function(a, b) {
      var fa = a.meetings.length ? a.meetings[0].pos : 2
      var fb = b.meetings.length ? b.meetings[0].pos : 2
      return fa - fb || b.n - a.n
    })
  } else {
    out.sort(function(a, b) { return b.n - a.n })
  }
  return out
}

// Ring angles run clockwise from 12 o'clock, with a gap there between 100
// and 0: position 0..1 to an angle.
function ringAngle(pos, gap) {
  return gap / 2 + pos * (2 * Math.PI - gap)
}

// The turn that brings a ring's first meeting under the marker at 12
// o'clock, the shortest way round (the site's calm variant). 0 without one.
function alignRotation(ring, gap) {
  if (!ring.meetings.length) return 0
  var turn = -ringAngle(ring.meetings[0].pos, gap)
  while (turn <= -Math.PI) turn += 2 * Math.PI
  while (turn > Math.PI) turn -= 2 * Math.PI
  return turn
}

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
}

// Where the meetings fall through their sūrahs, 0 to 100 in `bins` steps:
// the histogram round the outside of the rings.
function meetingHistogram(selection, bins) {
  var n = bins > 0 ? bins : 20
  var out = []
  for (var i = 0; i < n; i++) out.push(0)
  if (!selection) return out
  for (var r = 0; r < selection.qualifying.length; r++) {
    var ms = selection.qualifying[r].meetings
    for (var m = 0; m < ms.length; m++) out[Math.min(n - 1, Math.floor(ms[m].pos * n))]++
  }
  return out
}

// The site's Quran structure map in occurrence mode (lib/viz/structureMap):
// the 114 sūrahs round a clock face, each with an inward bar for its length
// (square-root scaled) and, outward, one dot per āyah holding the root.
function structureMap(conc, bare) {
  if (!conc) return null
  var dots = []
  for (var i = 0; i < SURAH_COUNT; i++) dots.push(0)
  var occ = rootOccurrences(conc, bare)
  for (var o = 0; o < occ.length; o++) dots[occ[o].s - 1]++
  var maxWords = maxOf(conc.words)
  var surahs = []
  for (var s = 0; s < SURAH_COUNT; s++) {
    surahs.push({
      n: s + 1,
      makkan: isMakkan(s + 1),
      words: conc.words[s],
      ayahs: conc.surahs[s].length,
      // The site's barLength, as a share of BAR_MAX: 16 + 104 * sqrt(words / max).
      bar: (16 + 104 * Math.sqrt(conc.words[s] / Math.max(1, maxWords))) / 120,
      dots: dots[s]
    })
  }
  return { surahs: surahs, ayahsWithRoot: occ.length, surahsWithRoot: dots.filter(function(d) { return d > 0 }).length }
}

// The site's occurrence stacks: dots 10 apart, tightened so a long stack
// never runs past 380 (in the map's 1000-unit world).
function occurrenceStep(count) {
  return count > 1 ? Math.min(10, 380 / (count - 1)) : 0
}

// The control point of the site's curved strands (buildCurvedPath): bowed
// off the straight line by a share of its length, to a side fixed per pair.
function curveControl(sx, sy, tx, ty, key, bendScale) {
  var dx = tx - sx, dy = ty - sy
  var dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1)
  var direction = hashString(key) % 2 === 0 ? 1 : -1
  var bend = Math.min(60, dist * bendScale) * direction
  return { x: (sx + tx) / 2 + (-dy / dist) * bend, y: (sy + ty) / 2 + (dx / dist) * bend }
}

function maxOf(values) {
  var m = 0
  for (var i = 0; i < values.length; i++) if (values[i] > m) m = values[i]
  return m
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
    CONCORDANCE_URL: CONCORDANCE_URL,
    CONCORDANCE_TEXT_URL: CONCORDANCE_TEXT_URL,
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
    shortMeaning: shortMeaning,
    barLabel: barLabel,
    todayText: todayText,
    histogramLevels: histogramLevels,
    posKey: posKey,
    siteLanguage: siteLanguage,
    rootUrl: rootUrl,
    searchUrl: searchUrl,
    REVELATION: REVELATION,
    isMakkan: isMakkan,
    sanitizeConcordance: sanitizeConcordance,
    parseConcordance: parseConcordance,
    sanitizeConcordanceText: sanitizeConcordanceText,
    parseConcordanceText: parseConcordanceText,
    rootOccurrences: rootOccurrences,
    companions: companions,
    concordanceLines: concordanceLines,
    distribution: distribution,
    maxOf: maxOf,
    surahStrip: surahStrip,
    hashString: hashString,
    collocationLayout: collocationLayout,
    curveControl: curveControl,
    concordanceRings: concordanceRings,
    meetingHistogram: meetingHistogram,
    ringOrder: ringOrder,
    ringAngle: ringAngle,
    alignRotation: alignRotation,
    easeInOutCubic: easeInOutCubic,
    structureMap: structureMap,
    occurrenceStep: occurrenceStep,
    needsDownload: needsDownload,
    moveSelection: moveSelection
  }
}
