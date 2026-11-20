import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The root data, kept in ~/.cache and refreshed from quranobservatory.org on
// the schedule the user picked. Downloads go to .part files and only replace
// the cache once they parse and validate, so a cut connection or a bad
// response never costs the copy that works.
//
// Four files: the root index (required) and three that only add to it - the
// word forms (search), the concordance (companions, distribution) and the
// concordance text (keyword-in-context lines, parsed only when first asked).
Item {
  id: root

  // "Weekly", "Daily" or "Off" (no network at all).
  property string updateInterval: "Weekly"

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/io.github.lavart.quran-observatory"
  readonly property var files: [
    { key: "stats", url: Model.DATA_URL, path: cacheDir + "/root-stats.json" },
    { key: "forms", url: Model.FORMS_URL, path: cacheDir + "/form-index.json" },
    { key: "concordance", url: Model.CONCORDANCE_URL, path: cacheDir + "/concordance.json" },
    { key: "text", url: Model.CONCORDANCE_TEXT_URL, path: cacheDir + "/concordance-text.json" }
  ]

  property var index: null
  property var forms: null
  property var concordance: null
  // ready | loading | downloading | offline | invalid | disabled
  property string status: "loading"
  readonly property bool busy: fetcher.running || installer.running

  property real lastAttempt: 0
  property bool cacheChecked: false

  // The concordance text is 1.4 MB of words; it is parsed the first time the
  // panel asks for it and dropped whenever its file or the concordance changes.
  // Kept in a plain object, not properties: filling it from inside a binding
  // must not notify that binding (it would loop). textRevision is the signal.
  property var textStore: ({ tried: false, data: null })
  property int textRevision: 0

  function concordanceText() {
    var store = textStore
    if (!store.tried && concordance) {
      store.tried = true
      store.data = Model.parseConcordanceText(textView.text(), concordance)
    }
    return store.data
  }

  function resetText() {
    textStore = { tried: false, data: null }
    textRevision++
  }

  onConcordanceChanged: resetText()
  onUpdateIntervalChanged: check()

  // Re-reads the clock against the cache now and then, so a shell that stays
  // up for weeks still refreshes on schedule.
  Timer {
    interval: 3 * 3600 * 1000
    running: true
    repeat: true
    onTriggered: root.check()
  }

  // Asked for by hand (the panel's retry, IPC): skips the schedule and the
  // retry back-off, but never turns updates on behind the user's back.
  function refresh(force) {
    if (busy) return
    if (updateInterval === "Off" && !force) return
    download()
  }

  function check() {
    if (!cacheChecked || busy) return
    if (updateInterval === "Off") {
      if (!index) status = "disabled"
      return
    }
    ageProbe.running = true
  }

  function download() {
    lastAttempt = Date.now()
    if (!index) status = "downloading"
    var cmd = ["curl", "-fsSL", "--proto", "=https", "--max-time", "120",
      "--max-filesize", String(Model.LIMITS.bytes), "--create-dirs"]
    for (var i = 0; i < files.length; i++) cmd.push("-o", files[i].path + ".part", files[i].url)
    fetcher.command = cmd
    fetcher.running = true
  }

  function failed(kind) {
    if (!index) status = kind
  }

  function adoptStats(text) {
    var parsed = Model.parseIndex(text)
    if (parsed) {
      index = parsed
      status = "ready"
    } else if (!index) {
      status = "invalid"
    }
  }

  // Reads back what curl wrote and installs every file that validates. The
  // root index must; the others are kept only when they are sound.
  function install() {
    statsPart.reload()
    if (!Model.parseIndex(statsPart.text())) {
      console.warn("[quran-observatory] downloaded root index did not validate; keeping the cached copy")
      failed("invalid")
      cleaner.running = true
      return
    }
    formsPart.reload()
    concordancePart.reload()
    textPart.reload()
    var conc = Model.parseConcordance(concordancePart.text())
    var ok = {
      stats: true,
      forms: Model.parseForms(formsPart.text()) !== null,
      concordance: conc !== null,
      text: conc !== null && Model.parseConcordanceText(textPart.text(), conc) !== null
    }
    // Pairs of paths go in as arguments, never into the script text.
    var cmd = ["sh", "-c", "while [ $# -ge 2 ]; do mv -f \"$1\" \"$2\" || exit 1; shift 2; done", "sh"]
    for (var i = 0; i < files.length; i++) {
      if (ok[files[i].key]) cmd.push(files[i].path + ".part", files[i].path)
      else console.warn("[quran-observatory] downloaded " + files[i].key + " did not validate; keeping the cached copy")
    }
    installer.command = cmd
    installer.running = true
  }

  // The cached copies. Read once at start and again whenever an install
  // replaces them.
  FileView {
    id: statsView
    path: root.files[0].path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.adoptStats(text())
      if (!root.cacheChecked) { root.cacheChecked = true; root.check() }
    }
    onLoadFailed: {
      if (!root.cacheChecked) { root.cacheChecked = true; root.check() }
    }
  }

  FileView {
    id: formsView
    path: root.files[1].path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseForms(text())
      if (parsed) root.forms = parsed
    }
  }

  FileView {
    id: concordanceView
    path: root.files[2].path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseConcordance(text())
      if (parsed) root.concordance = parsed
    }
  }

  FileView {
    id: textView
    path: root.files[3].path
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: { reload(); root.resetText() }
  }

  // Downloads, read back before they are trusted.
  FileView { id: statsPart; path: root.files[0].path + ".part"; printErrors: false; blockLoading: true }
  FileView { id: formsPart; path: root.files[1].path + ".part"; printErrors: false; blockLoading: true }
  FileView { id: concordancePart; path: root.files[2].path + ".part"; printErrors: false; blockLoading: true }
  FileView { id: textPart; path: root.files[3].path + ".part"; printErrors: false; blockLoading: true }

  Process {
    id: ageProbe
    // Missing extras count as stale, so an update adds the newer files.
    command: ["stat", "-c", "%Y"].concat(root.files.map(function(f) { return f.path }))
    stdout: StdioCollector {
      id: ageOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var stamps = String(ageOut.text).trim().split(/\s+/).map(Number)
      var oldest = exitCode === 0 && stamps.length === root.files.length ? Math.min.apply(null, stamps) : 0
      if (!root.index) oldest = 0
      if (Model.needsDownload(oldest, Date.now(), root.updateInterval, root.lastAttempt))
        root.download()
      else if (!root.index && root.lastAttempt > 0)
        root.failed("offline")
    }
  }

  Process {
    id: fetcher
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("[quran-observatory] download failed, curl exit " + exitCode)
        root.failed("offline")
        cleaner.running = true
        return
      }
      root.install()
    }
  }

  Process {
    id: installer
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("[quran-observatory] could not install the downloaded data, exit " + exitCode)
        root.failed("invalid")
      }
      cleaner.running = true
      // The watchers pick the new files up; reload in case a watch was lost
      // when its file was replaced.
      statsView.reload()
      formsView.reload()
      concordanceView.reload()
      textView.reload()
      root.resetText()
    }
  }

  Process {
    id: cleaner
    command: ["rm", "-f"].concat(root.files.map(function(f) { return f.path + ".part" }))
  }
}
