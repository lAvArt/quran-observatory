import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The root data, kept in ~/.cache and refreshed from quranobservatory.org on
// the schedule the user picked. Downloads go to .part files and only replace
// the cache once they parse and validate, so a cut connection or a bad
// response never costs the copy that works.
Item {
  id: root

  // "Weekly", "Daily" or "Off" (no network at all).
  property string updateInterval: "Weekly"

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/io.github.lavart.quran-observatory"
  readonly property string statsFile: cacheDir + "/root-stats.json"
  readonly property string formsFile: cacheDir + "/form-index.json"

  property var index: null
  property var forms: null
  // ready | loading | downloading | offline | invalid | disabled
  property string status: "loading"
  readonly property bool busy: fetcher.running || installer.running

  property real lastAttempt: 0
  property bool cacheChecked: false

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
    fetcher.command = [
      "curl", "-fsSL", "--proto", "=https", "--max-time", "90",
      "--max-filesize", String(Model.LIMITS.bytes), "--create-dirs",
      "-o", statsFile + ".part", Model.DATA_URL,
      "-o", formsFile + ".part", Model.FORMS_URL
    ]
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

  // The cached copy. Read once at start and again whenever an install
  // replaces it.
  FileView {
    id: statsView
    path: root.statsFile
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
    path: root.formsFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseForms(text())
      if (parsed) root.forms = parsed
    }
  }

  // Downloads, read back before they are trusted.
  FileView {
    id: statsPart
    path: root.statsFile + ".part"
    printErrors: false
    blockLoading: true
  }

  FileView {
    id: formsPart
    path: root.formsFile + ".part"
    printErrors: false
    blockLoading: true
  }

  Process {
    id: ageProbe
    command: ["stat", "-c", "%Y", root.statsFile]
    stdout: StdioCollector {
      id: ageOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var mtime = exitCode === 0 ? Number(String(ageOut.text).trim()) : 0
      // A cache that is there but unreadable counts as missing.
      if (!root.index) mtime = 0
      if (Model.needsDownload(mtime, Date.now(), root.updateInterval, root.lastAttempt))
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
      statsPart.reload()
      formsPart.reload()
      var statsOk = Model.parseIndex(statsPart.text()) !== null
      var formsOk = Model.parseForms(formsPart.text()) !== null
      if (!statsOk) {
        console.warn("[quran-observatory] downloaded root index did not validate; keeping the cached copy")
        root.failed("invalid")
        cleaner.running = true
        return
      }
      // Paths go in as arguments, never into the script text.
      installer.command = formsOk
        ? ["sh", "-c", "mv -f \"$1\" \"$2\" && mv -f \"$3\" \"$4\"", "sh", root.statsFile + ".part", root.statsFile, root.formsFile + ".part", root.formsFile]
        : ["sh", "-c", "mv -f \"$1\" \"$2\"; rm -f \"$3\"", "sh", root.statsFile + ".part", root.statsFile, root.formsFile + ".part"]
      installer.running = true
    }
  }

  Process {
    id: installer
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("[quran-observatory] could not install the downloaded data, exit " + exitCode)
        root.failed("invalid")
        return
      }
      // The watchers pick the new files up; reload in case the watch was
      // lost when the file was replaced.
      statsView.reload()
      formsView.reload()
    }
  }

  Process {
    id: cleaner
    command: ["rm", "-f", root.statsFile + ".part", root.formsFile + ".part"]
  }
}
