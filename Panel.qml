import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The root panel: a search line on top, then either the matching roots or one
// root in full - its meaning, how often and where it occurs across the 114
// sūrahs, and example verses with the root's words picked out.
//
// Under the numbers, one diagram at a time: example verses, the roots it
// keeps company with, every occurrence in context, and its spread across the
// sūrahs.
//
// Keyboard: type to search, Up/Down and Enter pick a result, Escape steps
// back (clears the search, returns to today's root, then closes). With the
// search empty, Up/Down switch the diagram, Left/Right step through the
// verses, Page Up/Down scroll the concordance, and Enter opens the root on
// quranobservatory.org; Ctrl+Enter always searches the corpus there.
Panel {
  id: root
  moduleName: "io.github.lavart.quran-observatory"
  ipcTarget: "io.github.lavart.quran-observatory"
  manageIpc: false

  property var anchorItem: null
  // The bar tracks the widget in its slot (BarWidget.qml), not this nested
  // panel, so everything that identifies the popout has to be that widget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var index: hostWidget ? hostWidget.index : null
  readonly property var forms: hostWidget ? hostWidget.forms : null
  readonly property var todayRoot: hostWidget ? hostWidget.today : null
  readonly property string dataStatus: hostWidget ? hostWidget.dataStatus : "loading"
  readonly property string arabicFont: hostWidget ? hostWidget.arabicFont : "Noto Naskh Arabic"
  readonly property string siteLang: Model.siteLanguage(Commons.I18n.language)
  readonly property bool rtl: Commons.I18n.rightToLeft

  // A root picked from the results; empty shows today's.
  property string pickedBare: ""
  readonly property var shown: pickedBare !== "" && index && index.roots[pickedBare] ? index.roots[pickedBare] : todayRoot
  readonly property bool showingToday: !!shown && !!todayRoot && shown.bare === todayRoot.bare

  readonly property string query: searchField.text
  readonly property bool searching: query.trim() !== ""
  readonly property var results: searching ? Model.search(index, query, 8, forms) : []
  property int selectedIndex: 0

  property int exampleIndex: 0
  readonly property var examples: shown ? shown.examples : []
  readonly property var example: examples.length ? examples[Math.min(exampleIndex, examples.length - 1)] : null
  readonly property var words: Model.verseWords(example, shown ? shown.bare : "")
  readonly property var stripBars: shown ? Model.surahStrip(shown.hist) : []
  // The sūrah of the verse on show, spotlighted in the strip.
  readonly property int activeSura: view === "verses" && example ? example.s : 0
  readonly property int maxTop: {
    var m = 0
    if (shown) for (var i = 0; i < shown.top.length; i++) m = Math.max(m, shown.top[i][1])
    return m
  }
  property int hoveredSurah: 0

  // The diagram under the root's numbers. Only the open one is computed.
  readonly property var views: ["verses", "companions", "rings", "concordance", "structure"]
  property string view: "verses"
  readonly property var conc: hostWidget ? hostWidget.concordance : null

  function versesOf(bare) {
    return index && index.roots[bare] ? index.roots[bare].verses : 0
  }

  readonly property var companionList: view === "companions" && shown && conc
    ? Model.companions(conc, shown.bare, versesOf, 16, 3) : []

  readonly property var kwic: {
    if (view !== "concordance" || !shown || !conc || !hostWidget) return []
    var revision = hostWidget.textRevision
    return Model.concordanceLines(conc, hostWidget.concordanceText(), shown.bare, 4)
  }

  readonly property var dist: view === "structure" && shown && conc ? Model.distribution(conc, shown.bare) : null
  readonly property var structureData: view === "structure" && shown && conc ? Model.structureMap(conc, shown.bare) : null

  // Rings: up to three roots, each chosen by the reader as on the site. Until
  // they choose (ringRootsChoice null), the root on show and its strongest
  // companion.
  property var ringRootsChoice: null
  readonly property var ringPartners: view === "rings" && shown && conc ? Model.companions(conc, shown.bare, versesOf, 6, 3) : []
  readonly property var ringRoots: ringRootsChoice
    ? ringRootsChoice
    : (shown ? (ringPartners.length ? [shown.bare, ringPartners[0].bare] : [shown.bare]) : [])
  readonly property var ringsSel: view === "rings" && conc && ringRoots.length ? Model.concordanceRings(conc, ringRoots, "ayah") : null

  // The slot being edited (-1 none; ringRoots.length adds a root) and its query.
  property int editingSlot: -1
  property string slotQuery: ""
  readonly property var slotSuggestions: {
    if (editingSlot < 0 || !index) return []
    var taken = ringRoots
    var pool = slotQuery.trim() !== ""
      ? Model.search(index, slotQuery, 10, forms)
      : ringPartners.map(function(c) { return index.roots[c.bare] }).filter(function(r) { return !!r })
    return pool.filter(function(r, i) { return taken.indexOf(r.bare) < 0 || taken.indexOf(r.bare) === editingSlot }).slice(0, 6)
  }

  function ringColour(slot) {
    return slot === 0 ? accent : (slot === 1 ? accent2 : contentForeground)
  }

  function editSlot(slot) {
    editingSlot = slot
    slotQuery = ""
    Qt.callLater(function() { if (slotField) { slotField.text = ""; slotField.forceActiveFocus() } })
  }

  function stopEditingSlot() {
    editingSlot = -1
    slotQuery = ""
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function setSlot(slot, bare) {
    var roots = ringRoots.slice()
    var already = roots.indexOf(bare)
    if (already >= 0 && already !== slot) roots.splice(already, 1)
    if (slot >= roots.length) roots.push(bare)
    else roots[slot] = bare
    ringRootsChoice = roots.slice(0, 3)
    stopEditingSlot()
  }

  function removeSlot(slot) {
    if (ringRoots.length <= 1) return
    var roots = ringRoots.slice()
    roots.splice(slot, 1)
    ringRootsChoice = roots
    if (editingSlot >= 0) stopEditingSlot()
  }

  // By script: bare roots, space separated (e.g. "غفر رحم"), known ones only.
  function setRingRoots(text) {
    var roots = []
    var parts = String(text || "").split(/\s+/)
    for (var i = 0; i < parts.length && roots.length < 3; i++)
      if (index && index.roots[parts[i]] && roots.indexOf(parts[i]) < 0) roots.push(parts[i])
    if (roots.length) ringRootsChoice = roots
  }
  readonly property var ringsHist: Model.meetingHistogram(ringsSel, 20)

  // The site's palette from the theme: the first root in the accent, the
  // second a cool counterpart 144° round (orange -> the site's teal; cool
  // Makki against warm Madani too), meetings
  // in cream. A colourless accent leaves the complement a quiet foreground.
  readonly property color accent2: accent.hslSaturation > 0.12
    ? Qt.hsla((accent.hslHue + 0.4) % 1, Math.max(0.3, accent.hslSaturation * 0.6), Math.min(0.6, Math.max(0.45, accent.hslLightness)), 1)
    : Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.55)
  readonly property color cream: Qt.tint(contentForeground, Qt.rgba(1, 0.93, 0.8, 0.35))

  function stepView(delta) {
    view = views[Model.moveSelection(Math.max(0, views.indexOf(view)), delta, views.length)]
  }

  onShownChanged: { exampleIndex = 0; hoveredSurah = 0; ringRootsChoice = null; editingSlot = -1 }
  onQueryChanged: selectedIndex = 0

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(contentForeground, 1.45)
  readonly property color faint: Qt.darker(contentForeground, 2.2)
  readonly property color accent: Color.accent
  readonly property string uiFont: bar ? bar.fontFamily : Style.font.family

  // ---- Opening and closing ------------------------------------------------

  function open() {
    pickedBare = ""
    searchField.text = ""
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
      searchField.forceActiveFocus()
    })
  }

  function openView(name) {
    if (views.indexOf(name) >= 0) view = name
    if (!root.opened) open()
  }

  // By script: open on the root a query finds, the panel's own search's first answer.
  function showRoot(query) {
    if (!root.opened) open()
    var hit = Model.search(index, String(query || ""), 1, forms)[0]
    if (hit) Qt.callLater(function() { root.pick(hit) })
  }

  // Rings by script: an order (mushaf | length | first) and alignment.
  function setRings(order, align) {
    openView("rings")
    Qt.callLater(function() {
      if (["mushaf", "length", "first"].indexOf(order) >= 0) ringsBox.ringOrder = order
      ringsBox.aligned = !!align
    })
  }

  function openWithQuery(text) {
    if (!root.opened) open()
    Qt.callLater(function() { searchField.text = text; searchField.forceActiveFocus() })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Actions ------------------------------------------------------------

  function pick(result) {
    if (!result) return
    pickedBare = todayRoot && result.bare === todayRoot.bare ? "" : result.bare
    searchField.text = ""
  }

  function backToToday() {
    pickedBare = ""
    searchField.text = ""
  }

  function stepExample(delta) {
    if (examples.length > 1) exampleIndex = Model.moveSelection(exampleIndex, delta, examples.length)
  }

  function openRootOnSite() {
    if (shown) Qt.openUrlExternally(Model.rootUrl(shown.bare, siteLang))
  }

  function openSearchOnSite() {
    var q = query.trim() || (shown ? shown.bare : "")
    if (q) Qt.openUrlExternally(Model.searchUrl(q, siteLang))
  }

  function handleKey(event) {
    var k = event.key
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (k === Qt.Key_Escape) {
      if (searching) searchField.text = ""
      else if (!showingToday && todayRoot) backToToday()
      else close()
    } else if ((k === Qt.Key_Down || k === Qt.Key_Up) && searching) {
      selectedIndex = Model.moveSelection(selectedIndex, k === Qt.Key_Down ? 1 : -1, results.length)
    } else if ((k === Qt.Key_Down || k === Qt.Key_Up) && shown) {
      stepView(k === Qt.Key_Down ? 1 : -1)
    } else if ((k === Qt.Key_PageDown || k === Qt.Key_PageUp) && view === "concordance") {
      kwicList.contentY = Math.max(0, Math.min(kwicList.contentHeight - kwicList.height,
        kwicList.contentY + (k === Qt.Key_PageDown ? 1 : -1) * kwicList.height * 0.9))
    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (ctrl) openSearchOnSite()
      else if (searching && results.length) pick(results[Math.min(selectedIndex, results.length - 1)])
      else if (searching) openSearchOnSite()
      else openRootOnSite()
    } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      switchPanel(k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
    } else if (!searching && (k === Qt.Key_Left || k === Qt.Key_Right)) {
      var forward = k === Qt.Key_Right
      stepExample(forward !== rtl ? 1 : -1)
    } else {
      return
    }
    event.accepted = true
  }

  // ---- Text ---------------------------------------------------------------

  readonly property string dateLabel: {
    var d = hostWidget ? hostWidget.day : 0
    return Qt.locale(Commons.I18n.formatLocale).toString(new Date(), "dddd d MMMM")
  }

  function surahLabel(n) {
    return Model.surahName(n, siteLang === "ar")
  }

  function n(value) {
    return Commons.I18n.formatNumber(value)
  }

  readonly property string posLine: {
    if (!shown) return ""
    var parts = []
    for (var i = 0; i < shown.pos.length && parts.length < 3; i++) {
      var key = Model.posKey(shown.pos[i][0])
      if (key) parts.push(strings.tn("pos." + key, shown.pos[i][1]).arg(n(shown.pos[i][1])))
    }
    return parts.join("  ·  ")
  }

  readonly property string statusText: {
    switch (dataStatus) {
    case "downloading": return strings.t("status.downloading")
    case "offline": return strings.t("status.offline")
    case "invalid": return strings.t("status.invalid")
    case "disabled": return strings.t("status.disabled")
    default: return strings.t("status.loading")
    }
  }

  // ---- Layout -------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Flickable {
      id: scroller
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: column
        width: scroller.width
        spacing: Style.space(12)

        TextField {
          id: searchField
          width: parent.width
          placeholderText: strings.t("search.placeholder")
          foreground: root.contentForeground
          font.family: root.uiFont
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.handleKey(event) }
        }

        // ---- Results ----
        Column {
          width: parent.width
          spacing: Style.space(2)
          visible: root.searching

          Repeater {
            model: root.results

            Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool selected: index === root.selectedIndex
              width: parent.width
              height: Math.max(rowArabic.implicitHeight, Style.space(34))
              radius: Style.cornerRadius
              color: selected ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.09) : "transparent"

              PlainText {
                id: rowArabic
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(78)
                horizontalAlignment: Text.AlignHCenter
                text: row.modelData.root
                font.family: root.arabicFont
                font.pixelSize: Math.round(Style.font.title * 1.35)
                color: root.contentForeground
              }

              Column {
                anchors.left: rowArabic.right
                anchors.leftMargin: Style.space(10)
                anchors.right: rowCount.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter

                PlainText {
                  width: parent.width
                  elide: Text.ElideRight
                  text: row.modelData.gloss || row.modelData.translit
                  font.family: root.uiFont
                  font.pixelSize: Style.font.body
                  color: root.contentForeground
                }

                PlainText {
                  width: parent.width
                  elide: Text.ElideRight
                  visible: row.modelData.gloss !== ""
                  text: row.modelData.translit
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }

              PlainText {
                id: rowCount
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("result.count").arg(root.n(row.modelData.count))
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                color: root.dim
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = row.index
                onClicked: root.pick(row.modelData)
              }
            }
          }

          PlainText {
            visible: root.results.length === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: strings.t("search.none").arg(root.query.trim())
            font.family: root.uiFont
            font.pixelSize: Style.font.body
            color: root.contentForeground
          }

          PlainText {
            width: parent.width
            topPadding: Style.space(6)
            wrapMode: Text.Wrap
            text: strings.t("search.hint")
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            color: root.faint
          }
        }

        // ---- No data yet ----
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: !root.searching && !root.shown

          PlainText {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.statusText
            font.family: root.uiFont
            font.pixelSize: Style.font.body
            color: root.contentForeground
          }

          Button {
            visible: root.dataStatus === "offline" || root.dataStatus === "invalid" || root.dataStatus === "disabled"
            enabled: !(root.hostWidget && root.hostWidget.dataBusy)
            text: root.dataStatus === "disabled" ? strings.t("action.downloadOnce") : strings.t("action.retry")
            foreground: root.contentForeground
            fontFamily: root.uiFont
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.refreshData()
          }
        }

        // ---- One root ----
        Column {
          id: detail
          width: parent.width
          spacing: Style.space(12)
          visible: !root.searching && !!root.shown

          Item {
            width: parent.width
            height: Math.max(heading.implicitHeight, todayButton.visible ? todayButton.implicitHeight : 0)

            PanelSectionHeader {
              id: heading
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: (root.showingToday ? strings.t("heading.today").arg(root.dateLabel) : strings.t("heading.root")).toUpperCase()
              foreground: root.contentForeground
              fontFamily: root.uiFont
            }

            Button {
              id: todayButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.showingToday && !!root.todayRoot
              text: strings.t("action.today")
              fontSize: Style.font.caption
              foreground: root.contentForeground
              fontFamily: root.uiFont
              onClicked: root.backToToday()
            }
          }

          PlainText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.shown ? root.shown.root : ""
            font.family: root.arabicFont
            font.pixelSize: Math.round(Style.font.display * 1.75)
            color: root.contentForeground
          }

          PlainText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.shown ? (root.shown.translit + (root.shown.gloss ? "   —   " + root.shown.gloss : "")) : ""
            font.family: root.uiFont
            font.pixelSize: Style.font.subtitle
            color: root.dim
          }

          Row {
            id: stats
            width: parent.width
            readonly property var cells: root.shown ? [
              [root.shown.count, "stat.occurrencesLabel"],
              [root.shown.verses, "stat.versesLabel"],
              [root.shown.surahs, "stat.surahsLabel"],
              [root.shown.forms, "stat.formsLabel"]
            ] : []

            Repeater {
              model: stats.cells

              Column {
                required property var modelData
                width: stats.width / 4

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.n(modelData[0])
                  font.family: root.uiFont
                  font.pixelSize: Style.font.title
                  font.weight: Font.DemiBold
                  color: root.contentForeground
                }

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: strings.tn(modelData[1], modelData[0]).toUpperCase()
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }
            }
          }

          PlainText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: text !== ""
            text: root.posLine
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            color: root.dim
          }

          // ---- Where it occurs · by sūrah ----
          // The site's strip, drawn by its rules (Model.surahStrip): a bar per
          // sūrah, the busier ones in the accent, the sūrah of the verse on
          // show spotlighted with a dot while the rest fade.
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: whereLabel.implicitHeight

              PanelSectionHeader {
                id: whereLabel
                anchors.left: parent.left
                text: strings.t("where.label").toUpperCase()
                foreground: root.contentForeground
                fontFamily: root.uiFont
              }

              PlainText {
                anchors.right: parent.right
                anchors.verticalCenter: whereLabel.verticalCenter
                text: root.shown ? strings.t("where.of").arg(root.n(root.shown.surahs)).arg(root.n(114)) : ""
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                color: root.dim
              }
            }

            Item {
              id: strip
              width: parent.width
              height: Style.space(74)
              // Sūrah 1 on the left whatever the language, as on the site.
              LayoutMirroring.enabled: false

              Canvas {
                anchors.fill: parent
                readonly property var deps: [root.stripBars, root.activeSura, root.hoveredSurah, root.contentForeground, root.accent, width, height]
                onDepsChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var bars = root.stripBars
                  var fg = root.contentForeground
                  var ac = root.accent
                  var W = width, H = height, gap = W / 114
                  ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.12)
                  ctx.fillRect(0, H - 1, W, 1)
                  for (var i = 0; i < bars.length; i++) {
                    var b = bars[i]
                    if (!b.count) continue
                    var bh = 3 + b.v * (H - 12)
                    var active = i + 1 === root.activeSura
                    var hover = i + 1 === root.hoveredSurah
                    var wide = Math.max(1.4, gap * (active ? 0.72 : 0.6))
                    var alpha = active || hover ? 1 : b.opacity
                    if (root.activeSura > 0 && !active && !hover) alpha = Math.min(alpha, 0.32)
                    ctx.globalAlpha = alpha
                    ctx.fillStyle = active || hover || b.accent ? ac : Qt.rgba(fg.r, fg.g, fg.b, 0.18)
                    ctx.fillRect(i * gap + (gap - wide) / 2, H - bh, wide, bh)
                  }
                  ctx.globalAlpha = 1
                  var s = root.activeSura
                  if (s > 0 && bars[s - 1] && bars[s - 1].count) {
                    var top = H - (3 + bars[s - 1].v * (H - 12)) - 6
                    ctx.beginPath()
                    ctx.arc((s - 0.5) * gap, top, 3, 0, 2 * Math.PI)
                    ctx.fillStyle = ac
                    ctx.fill()
                    ctx.lineWidth = 1
                    ctx.strokeStyle = Color.popups.background
                    ctx.stroke()
                  }
                }
              }

              // Full-height targets, so thin bars are easy to catch.
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) {
                  var s = Math.floor(mouse.x / (width / 114)) + 1
                  root.hoveredSurah = s >= 1 && s <= 114 && root.shown && root.shown.hist[s - 1] > 0 ? s : 0
                }
                onExited: root.hoveredSurah = 0
              }
            }

            // Ticks, 1 to 114 left to right in every language; the hover
            // read-out takes their place while a bar is pointed at.
            Item {
              width: parent.width
              height: Math.round(Style.font.caption * 1.5)
              LayoutMirroring.enabled: false
              LayoutMirroring.childrenInherit: true

              Repeater {
                model: root.hoveredSurah > 0 ? [] : [1, 30, 60, 90, 114]

                PlainText {
                  required property int modelData
                  x: Math.max(0, Math.min(parent.width - implicitWidth, (modelData - 0.5) / 114 * parent.width - implicitWidth / 2))
                  text: root.n(modelData)
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.faint
                }
              }

              PlainText {
                width: parent.width
                visible: root.hoveredSurah > 0
                horizontalAlignment: Text.AlignHCenter
                text: root.hoveredSurah > 0 && root.shown
                  ? strings.t("hist.hover").arg(root.surahLabel(root.hoveredSurah)).arg(root.n(root.hoveredSurah)).arg(root.n(root.shown.hist[root.hoveredSurah - 1]))
                  : ""
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                color: root.contentForeground
              }
            }

            // The sūrahs it occurs in most, as on the site: name, a bar
            // against the top one, and the count - or the verse, when once.
            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.shown ? root.shown.top : []

                Rectangle {
                  id: chip
                  required property var modelData
                  readonly property bool once: modelData[1] === 1 && modelData[2] > 0
                  readonly property bool lit: modelData[0] === root.activeSura || modelData[0] === root.hoveredSurah
                  width: chipRow.implicitWidth + 2 * Style.space(8)
                  height: Math.round(chipRow.implicitHeight + Style.space(8))
                  radius: Style.space(4)
                  color: "transparent"
                  border.width: 1
                  border.color: lit ? root.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

                  Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    PlainText {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.surahLabel(chip.modelData[0])
                      font.family: root.uiFont
                      font.pixelSize: Style.font.bodySmall
                      color: root.contentForeground
                    }

                    Rectangle {
                      visible: !chip.once
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(26)
                      height: 3
                      radius: 1.5
                      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                      Rectangle {
                        width: root.maxTop > 0 ? parent.width * chip.modelData[1] / root.maxTop : 0
                        height: parent.height
                        radius: parent.radius
                        color: root.accent
                      }
                    }

                    PlainText {
                      anchors.verticalCenter: parent.verticalCenter
                      text: chip.once ? root.n(chip.modelData[0]) + ":" + root.n(chip.modelData[2]) : strings.t("result.count").arg(root.n(chip.modelData[1]))
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      color: chip.once ? root.dim : root.accent
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.hoveredSurah = chip.modelData[0]
                    onExited: if (root.hoveredSurah === chip.modelData[0]) root.hoveredSurah = 0
                  }
                }
              }
            }
          }

          // ---- Views: one diagram at a time under the root's numbers ----
          ButtonGroup {
            anchors.horizontalCenter: parent.horizontalCenter
            focusable: false
            options: [
              { value: "verses", label: strings.t("view.verses") },
              { value: "companions", label: strings.t("view.companions") },
              { value: "rings", label: strings.t("view.rings") },
              { value: "concordance", label: strings.t("view.concordance") },
              { value: "structure", label: strings.t("view.structure") }
            ]
            value: root.view
            foreground: root.contentForeground
            fontFamily: root.uiFont
            fontSize: Style.font.bodySmall
            onChanged: function(v) { root.view = v }
          }

          PlainText {
            width: parent.width
            visible: root.view !== "verses" && !root.conc
            wrapMode: Text.Wrap
            text: strings.t("view.unavailable")
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            color: root.dim
          }

          // ---- Verses ----
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.view === "verses"

            Item {
              width: parent.width
              height: Math.max(versesHeading.implicitHeight, prevButton.size)

              PanelSectionHeader {
                id: versesHeading
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: strings.t("verses.heading").toUpperCase()
                foreground: root.contentForeground
                fontFamily: root.uiFont
              }

              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                visible: root.examples.length > 1

                PanelActionButton {
                  id: prevButton
                  iconText: root.rtl ? "" : ""
                  tooltipText: strings.t("verses.previous")
                  foreground: root.contentForeground
                  fontSize: Style.font.caption
                  onClicked: root.stepExample(-1)
                }

                PlainText {
                  anchors.verticalCenter: parent.verticalCenter
                  text: strings.t("verses.position").arg(root.n(root.exampleIndex + 1)).arg(root.n(root.examples.length))
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }

                PanelActionButton {
                  iconText: root.rtl ? "" : ""
                  tooltipText: strings.t("verses.next")
                  foreground: root.contentForeground
                  fontSize: Style.font.caption
                  onClicked: root.stepExample(1)
                }
              }
            }

            // Each word its own plain Text, so the root's words can be marked
            // without ever handing the verse to the rich-text parser.
            Flow {
              width: parent.width
              visible: root.words.length > 0
              // Arabic runs right to left whatever the interface language, so
              // a mirrored (RTL) panel must not flip it back.
              LayoutMirroring.enabled: false
              layoutDirection: Qt.RightToLeft
              spacing: Style.space(7)

              Repeater {
                model: root.words

                PlainText {
                  required property var modelData
                  text: modelData.t
                  font.family: root.arabicFont
                  font.pixelSize: Math.round(Style.font.title * 1.4)
                  font.weight: modelData.hit ? Font.Bold : Font.Normal
                  color: modelData.hit ? root.accent : root.contentForeground
                }
              }
            }

            PlainText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              visible: !!root.example
              text: root.example ? strings.t("verses.reference").arg(root.surahLabel(root.example.s)).arg(root.n(root.example.s)).arg(root.n(root.example.a)) : ""
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              color: root.dim
            }

            PlainText {
              width: parent.width
              visible: root.examples.length === 0
              wrapMode: Text.Wrap
              text: root.shown && root.shown.first
                ? strings.t("verses.noneFirst").arg(root.surahLabel(root.shown.first.sura)).arg(root.n(root.shown.first.sura)).arg(root.n(root.shown.first.ayah))
                : strings.t("verses.none")
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              color: root.dim
            }
          }

          // ---- Companions: the roots it shares āyahs with ----
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.view === "companions" && !!root.conc

            // The site's collocation burst: the root glowing in the middle,
            // curved strands out to its companions - nearer, larger and in the
            // accent for a stronger tie (higher PMI) - each trailing tendril
            // dots, over a faint field of stars. Click a companion to go to it.
            Item {
              id: burst
              width: parent.width
              height: Style.space(300)
              visible: root.companionList.length > 0
              LayoutMirroring.enabled: false

              property int hovered: -1
              readonly property var layout: Model.collocationLayout(root.companionList, root.shown ? root.shown.bare : "", width, height)
              readonly property real cx: width / 2
              readonly property real cy: height / 2

              onHoveredChanged: burstCanvas.requestPaint()

              Connections {
                target: root
                function onCompanionListChanged() { burst.hovered = -1 }
              }

              Canvas {
                id: burstCanvas
                anchors.fill: parent
                readonly property var deps: [burst.layout, root.contentForeground, root.accent]
                onDepsChanged: requestPaint()

                // Stronger ties take the accent, weaker the foreground; both
                // brighten with strength, as the site's palette does.
                function tone(node, alpha) {
                  var c = node.t >= 0.5 ? root.accent : root.contentForeground
                  return Qt.rgba(c.r, c.g, c.b, Math.min(1, alpha * (0.6 + 0.4 * node.t)))
                }

                function strand(ctx, sx, sy, tx, ty, key, bend) {
                  var c = Model.curveControl(sx, sy, tx, ty, key, bend)
                  ctx.beginPath()
                  ctx.moveTo(sx, sy)
                  ctx.quadraticCurveTo(c.x, c.y, tx, ty)
                  ctx.stroke()
                }

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var L = burst.layout
                  var fg = root.contentForeground
                  var ac = root.accent
                  var cx = burst.cx, cy = burst.cy
                  var key = root.shown ? root.shown.bare : ""
                  var i, nd, td, hot

                  ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.2)
                  for (i = 0; i < L.stars.length; i++) {
                    ctx.beginPath()
                    ctx.arc(L.stars[i].x, L.stars[i].y, L.stars[i].r, 0, 2 * Math.PI)
                    ctx.fill()
                  }

                  var glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, 80)
                  glow.addColorStop(0, Qt.rgba(ac.r, ac.g, ac.b, 0.18))
                  glow.addColorStop(1, Qt.rgba(ac.r, ac.g, ac.b, 0))
                  ctx.fillStyle = glow
                  ctx.fillRect(cx - 80, cy - 80, 160, 160)

                  // Branch strands to the tendrils.
                  ctx.lineWidth = 0.7
                  for (i = 0; i < L.tendrils.length; i++) {
                    td = L.tendrils[i]
                    nd = L.nodes[td.parent]
                    ctx.strokeStyle = tone(nd, td.parent === burst.hovered ? 0.7 : 0.26)
                    strand(ctx, nd.x, nd.y, td.x, td.y, nd.bare + ":" + i, 0.35)
                  }

                  // Trunks: a soft outer stroke and a finer core, like the site.
                  for (i = 0; i < L.nodes.length; i++) {
                    nd = L.nodes[i]
                    hot = i === burst.hovered
                    ctx.strokeStyle = tone(nd, hot ? 0.4 : 0.06 + nd.t * 0.14)
                    ctx.lineWidth = Math.min(4, 1.6 + nd.shared * 0.06)
                    strand(ctx, cx, cy, nd.x, nd.y, key + ":" + nd.bare, 0.22)
                    ctx.strokeStyle = tone(nd, hot ? 1 : 0.24 + nd.t * 0.3)
                    ctx.lineWidth = hot ? 1.6 : Math.min(1.8, 0.6 + nd.shared * 0.03)
                    strand(ctx, cx, cy, nd.x, nd.y, key + ":" + nd.bare, 0.22)
                  }

                  for (i = 0; i < L.tendrils.length; i++) {
                    td = L.tendrils[i]
                    ctx.fillStyle = tone(L.nodes[td.parent], 0.8)
                    ctx.beginPath()
                    ctx.arc(td.x, td.y, td.r, 0, 2 * Math.PI)
                    ctx.fill()
                  }

                  for (i = 0; i < L.nodes.length; i++) {
                    nd = L.nodes[i]
                    hot = i === burst.hovered
                    ctx.fillStyle = tone(nd, hot ? 0.34 : 0.14)
                    ctx.beginPath()
                    ctx.arc(nd.x, nd.y, nd.r + (hot ? 5 : 3), 0, 2 * Math.PI)
                    ctx.fill()
                    ctx.fillStyle = tone(nd, 1)
                    ctx.beginPath()
                    ctx.arc(nd.x, nd.y, nd.r, 0, 2 * Math.PI)
                    ctx.fill()
                  }

                  // The root: a light core in an accent ring, with a halo.
                  ctx.fillStyle = Qt.rgba(ac.r, ac.g, ac.b, 0.22)
                  ctx.beginPath()
                  ctx.arc(cx, cy, 15, 0, 2 * Math.PI)
                  ctx.fill()
                  ctx.fillStyle = fg
                  ctx.beginPath()
                  ctx.arc(cx, cy, 8, 0, 2 * Math.PI)
                  ctx.fill()
                  ctx.strokeStyle = ac
                  ctx.lineWidth = 2
                  ctx.beginPath()
                  ctx.arc(cx, cy, 9.5, 0, 2 * Math.PI)
                  ctx.stroke()
                }
              }

              PlainText {
                x: burst.cx - implicitWidth / 2
                y: burst.cy + 15
                text: root.shown ? root.shown.bare : ""
                font.family: root.arabicFont
                font.pixelSize: Math.round(Style.font.title * 1.35)
                font.weight: Font.DemiBold
                color: root.contentForeground
                style: Text.Outline
                styleColor: Color.popups.background
              }

              Repeater {
                model: burst.layout.nodes

                PlainText {
                  required property var modelData
                  required property int index
                  x: modelData.x - implicitWidth / 2
                  y: modelData.y + modelData.r + 1
                  text: modelData.bare
                  font.family: root.arabicFont
                  font.pixelSize: Math.round(Style.font.title * 1.05)
                  color: index === burst.hovered ? root.accent : root.contentForeground
                  style: Text.Outline
                  styleColor: Color.popups.background
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: burst.hovered >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPositionChanged: function(mouse) {
                  var nodes = burst.layout.nodes
                  var best = -1, bestDistance = 1e9
                  for (var i = 0; i < nodes.length; i++) {
                    // The dot and the label under it both count.
                    var d = Math.sqrt(Math.pow(mouse.x - nodes[i].x, 2) + Math.pow(mouse.y - nodes[i].y - 8, 2))
                    if (d < Math.max(18, nodes[i].r + 12) && d < bestDistance) { best = i; bestDistance = d }
                  }
                  burst.hovered = best
                }
                onExited: burst.hovered = -1
                onClicked: if (burst.hovered >= 0) root.pick({ bare: burst.layout.nodes[burst.hovered].bare })
              }
            }

            // The site's legend: higher and lower PMI.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(14)
              visible: root.companionList.length > 0

              Repeater {
                model: [
                  { tone: root.accent, label: strings.t("companions.legendHigh") },
                  { tone: root.contentForeground, label: strings.t("companions.legendLow") }
                ]

                Row {
                  required property var modelData
                  spacing: Style.space(5)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(7)
                    height: width
                    radius: width / 2
                    color: modelData.tone
                  }

                  PlainText {
                    text: modelData.label
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    color: root.dim
                  }
                }
              }
            }

            PlainText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              readonly property var hoveredCompanion: burst.hovered >= 0 ? root.companionList[burst.hovered] : null
              text: {
                if (root.companionList.length === 0) return strings.t("companions.none")
                var c = hoveredCompanion
                if (!c || !root.shown) return strings.t("companions.caption")
                var other = root.index && root.index.roots[c.bare] ? root.index.roots[c.bare].root : c.bare
                return strings.tn("companions.hover", c.shared).arg(root.shown.root).arg(other).arg(root.n(c.shared))
              }
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              color: hoveredCompanion ? root.contentForeground : root.dim
            }
          }

          // ---- Concordance rings (the site's): every sūrah a ring, every
          // āyah a tick, lit where the roots occur, cream where they meet ----
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.view === "rings" && !!root.conc

            // The roots, as on the site: up to three, each in its ring
            // colour. Click one to change it, × to drop it, + to add one.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(5)

              PlainText {
                height: Style.space(22)
                verticalAlignment: Text.AlignVCenter
                text: strings.t("rings.roots").toUpperCase()
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                color: root.dim
              }

              Repeater {
                model: root.ringRoots

                Rectangle {
                  id: slotChip
                  required property string modelData
                  required property int index
                  readonly property bool editing: root.editingSlot === index
                  readonly property color tone: root.ringColour(index)
                  width: slotRow.implicitWidth + 2 * Style.space(7)
                  height: Style.space(22)
                  radius: Style.space(4)
                  color: editing ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12) : "transparent"
                  border.width: 1
                  border.color: Qt.rgba(tone.r, tone.g, tone.b, editing ? 0.9 : 0.55)

                  Row {
                    id: slotRow
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    PlainText {
                      anchors.verticalCenter: parent.verticalCenter
                      text: slotChip.modelData
                      font.family: root.arabicFont
                      font.pixelSize: Style.font.title
                      color: slotChip.tone

                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: slotChip.editing ? root.stopEditingSlot() : root.editSlot(slotChip.index)
                      }
                    }

                    PlainText {
                      visible: root.ringRoots.length > 1
                      anchors.verticalCenter: parent.verticalCenter
                      text: "×"
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      color: root.dim

                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeSlot(slotChip.index)
                      }
                    }
                  }
                }
              }

              Rectangle {
                visible: root.ringRoots.length < 3
                width: Style.space(22)
                height: Style.space(22)
                radius: Style.space(4)
                color: root.editingSlot === root.ringRoots.length ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12) : "transparent"
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

                PlainText {
                  anchors.centerIn: parent
                  text: "+"
                  font.family: root.uiFont
                  font.pixelSize: Style.font.body
                  color: root.dim
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.editingSlot === root.ringRoots.length ? root.stopEditingSlot() : root.editSlot(root.ringRoots.length)
                }
              }
            }

            // Picking a root for a slot: type to search every root; empty,
            // the root on show's strongest companions.
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.editingSlot >= 0

              TextField {
                id: slotField
                width: parent.width
                verticalPadding: Style.space(3)
                placeholderText: strings.t("rings.pick")
                foreground: root.contentForeground
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                onTextChanged: root.slotQuery = text
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.stopEditingSlot()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.slotSuggestions.length) root.setSlot(root.editingSlot, root.slotSuggestions[0].bare)
                    event.accepted = true
                  }
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(5)

                Repeater {
                  model: root.slotSuggestions

                  Rectangle {
                    id: suggestion
                    required property var modelData
                    width: suggestionRow.implicitWidth + 2 * Style.space(7)
                    height: Style.space(24)
                    radius: Style.space(4)
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)

                    Row {
                      id: suggestionRow
                      anchors.centerIn: parent
                      spacing: Style.space(6)

                      PlainText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: suggestion.modelData.root
                        font.family: root.arabicFont
                        font.pixelSize: Style.font.title
                        color: root.contentForeground
                      }

                      PlainText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Model.shortMeaning(suggestion.modelData)
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                        color: root.dim
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setSlot(root.editingSlot, suggestion.modelData.bare)
                    }
                  }
                }
              }
            }

            // The site's motions, as one line of small chips: travel (the
            // three orders) and turn (align every first meeting at 12 o'clock).
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(5)

              Repeater {
                model: [
                  { value: "mushaf", label: strings.t("rings.orderMushaf") },
                  { value: "length", label: strings.t("rings.orderLength") },
                  { value: "first", label: strings.t("rings.orderFirst") },
                  { value: "align", label: ringsBox.aligned ? strings.t("rings.reset") : strings.t("rings.align") }
                ]

                Rectangle {
                  id: motionChip
                  required property var modelData
                  required property int index
                  readonly property bool chosen: modelData.value === "align" ? ringsBox.aligned : modelData.value === ringsBox.ringOrder
                  width: motionLabel.implicitWidth + 2 * Style.space(7)
                  height: Style.space(22)
                  radius: Style.space(4)
                  color: chosen ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12) : "transparent"
                  border.width: 1
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, chosen ? 0.3 : 0.14)

                  PlainText {
                    id: motionLabel
                    anchors.centerIn: parent
                    text: motionChip.modelData.label
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    color: motionChip.chosen ? root.contentForeground : root.dim
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (motionChip.modelData.value === "align") ringsBox.aligned = !ringsBox.aligned
                      else ringsBox.ringOrder = motionChip.modelData.value
                    }
                  }
                }
              }
            }

            Item {
              id: ringsBox
              width: parent.width
              height: width
              LayoutMirroring.enabled: false

              readonly property var sel: root.ringsSel
              // "mushaf" (114 inside to 1 outside, the site's default),
              // "length" or "first"; and whether first meetings are aligned.
              property string ringOrder: "mushaf"
              property bool aligned: false
              // The rings inside to out, as they will stand once at rest.
              property var order: []
              // Per sūrah: where each ring moves from and to (radial slot,
              // turn), with its delay and duration on the shared clock.
              property var motion: ({})
              property real clock: 0
              property real total: 0
              readonly property bool moving: motionClock.running

              NumberAnimation {
                id: motionClock
                target: ringsBox
                property: "clock"
                from: 0
                to: ringsBox.total
                duration: ringsBox.total
                easing.type: Easing.Linear
              }

              // A ring's slot and turn right now.
              function now(n) {
                var m = motion[n]
                if (!m) return { slot: 0, turn: 0, travelling: false, settled: true }
                var t = m.dur > 0 ? Math.max(0, Math.min(1, (clock - m.delay) / m.dur)) : 1
                var e = Model.easeInOutCubic(t)
                return { slot: m.i0 + (m.i1 - m.i0) * e, turn: m.r0 + (m.r1 - m.r0) * e, travelling: t < 1 && m.i0 !== m.i1, settled: t >= 1 }
              }

              // Set where every ring is headed. Animated: each starts from
              // where it is now, so a new request mid-motion never snaps.
              function retarget(animate) {
                if (!sel) { order = []; motion = ({}); total = 0; motionClock.stop(); return }
                var target = Model.ringOrder(sel.qualifying, ringOrder)
                var next = {}
                var longest = 0
                var calm = Style.duration(600)
                for (var k = 0; k < target.length; k++) {
                  var ring = target[k]
                  var turnTo = aligned ? Model.alignRotation(ring, gap) : 0
                  var cur = animate && motion[ring.n] ? now(ring.n) : { slot: k, turn: turnTo }
                  var travel = Math.abs(k - cur.slot), turn = Math.abs(turnTo - cur.turn)
                  var delay = 0, dur = 0
                  if (animate && calm > 0 && (travel > 1e-3 || turn > 1e-3)) {
                    // Turning: 8 ms a ring, innermost first; travelling:
                    // staggered by how far a ring goes.
                    delay = (turn > 1e-3 ? k * 8 : 0) + (travel > 1e-3 ? Math.min(240, travel * 10) : 0)
                    dur = Style.duration(travel > 1e-3 ? 700 : 600)
                  }
                  next[ring.n] = { i0: cur.slot, i1: k, r0: cur.turn, r1: turnTo, delay: delay, dur: dur }
                  longest = Math.max(longest, delay + dur)
                }
                hoverRing = -1
                hoverAyah = -1
                order = target
                motion = next
                motionClock.stop()
                clock = 0
                total = longest
                if (longest > 0) motionClock.restart()
                else ringsCanvas.requestPaint()
              }

              onSelChanged: retarget(false)
              onRingOrderChanged: retarget(true)
              onAlignedChanged: retarget(true)
              Component.onCompleted: retarget(false)
              readonly property real cx: width / 2
              readonly property real cy: height / 2
              readonly property real outerR: Math.min(width, height) / 2 - Style.space(34)
              // The hole is sized to the words in it: wide enough for the
              // longest of the three centre lines (they sit up to ~26 px off
              // centre), never less than the site's proportion, and capped
              // so the rings keep most of the radius.
              readonly property string glossLine: sel ? sel.roots.map(function(b) { return root.index && root.index.roots[b] ? Model.shortMeaning(root.index.roots[b]) : b }).join(" \u00b7 ") : ""
              readonly property string summaryLine: sel ? strings.t("rings.summary").arg(root.n(sel.qualifying.length)).arg(root.n(sel.totalMeetings)) : ""
              readonly property string rootsLine: sel ? sel.roots.join(" \u00b7 ") : ""
              TextMetrics { id: glossMetrics; font.family: root.uiFont; font.pixelSize: Style.font.caption; text: ringsBox.glossLine }
              TextMetrics { id: summaryMetrics; font.family: root.uiFont; font.pixelSize: Style.font.caption; text: ringsBox.summaryLine }
              TextMetrics { id: rootsMetrics; font.family: root.arabicFont; font.pixelSize: Math.round(Style.font.title * 1.25); font.weight: Font.DemiBold; text: ringsBox.rootsLine }
              readonly property real centreHalf: Math.max(glossMetrics.advanceWidth, summaryMetrics.advanceWidth, rootsMetrics.advanceWidth) / 2
              readonly property real innerR: Math.min(outerR * 0.5, Math.max(outerR * 0.27, Math.sqrt(centreHalf * centreHalf + 26 * 26) + Style.space(8)))
              readonly property real thick: order.length ? (outerR - innerR) / order.length : 0
              // The gap at 12 o'clock, between 100 and 0.
              readonly property real gap: 0.38
              property int hoverRing: -1
              property int hoverAyah: -1

              function angleAt(pos) { return gap / 2 + pos * (2 * Math.PI - gap) }
              // Canvas arcs start at 3 o'clock; ours at 12.
              function arcAngle(a) { return a - Math.PI / 2 }

              Canvas {
                id: ringsCanvas
                anchors.fill: parent
                readonly property var deps: [ringsBox.motion, ringsBox.clock, ringsBox.width, root.contentForeground, root.accent, root.accent2, root.cream]
                onDepsChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var B = ringsBox, order = B.order
                  var fg = root.contentForeground
                  var colours = [root.accent, root.accent2, root.contentForeground]
                  var usable = 2 * Math.PI - B.gap
                  var k, ring, i, r0, band, a, half, h

                  // Scale: 0 to 100 round the outside, ticks every 10.
                  ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.14)
                  ctx.lineWidth = 1
                  ctx.beginPath()
                  ctx.arc(B.cx, B.cy, B.outerR + 16, B.arcAngle(B.gap / 2), B.arcAngle(2 * Math.PI - B.gap / 2))
                  ctx.stroke()
                  for (i = 0; i <= 10; i++) {
                    a = B.angleAt(i / 10)
                    ctx.beginPath()
                    ctx.moveTo(B.cx + (B.outerR + 16) * Math.sin(a), B.cy - (B.outerR + 16) * Math.cos(a))
                    ctx.lineTo(B.cx + (B.outerR + 20) * Math.sin(a), B.cy - (B.outerR + 20) * Math.cos(a))
                    ctx.stroke()
                  }
                  // The marker at 12 o'clock.
                  ctx.fillStyle = B.aligned ? root.cream : Qt.rgba(fg.r, fg.g, fg.b, 0.5)
                  ctx.beginPath()
                  ctx.moveTo(B.cx - 4, B.cy - B.outerR - 26)
                  ctx.lineTo(B.cx + 4, B.cy - B.outerR - 26)
                  ctx.lineTo(B.cx, B.cy - B.outerR - 20)
                  ctx.closePath()
                  ctx.fill()

                  // Histogram of where the meetings fall, between rings and scale.
                  // Hidden while rings move; dimmed once aligned, since its
                  // positions describe the unturned rings.
                  var hist = B.moving ? [] : root.ringsHist
                  var hmax = Model.maxOf(hist)
                  var histAlpha = B.aligned ? 0.12 : 0.32
                  for (i = 0; i < hist.length; i++) {
                    if (!hist[i]) continue
                    a = B.angleAt((i + 0.5) / hist.length)
                    half = usable / hist.length * 0.3
                    h = 2 + 9 * hist[i] / Math.max(1, hmax)
                    ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, histAlpha)
                    ctx.lineWidth = h
                    ctx.beginPath()
                    ctx.arc(B.cx, B.cy, B.outerR + 4 + h / 2, B.arcAngle(a - half), B.arcAngle(a + half))
                    ctx.stroke()
                  }

                  for (k = 0; k < order.length; k++) {
                    ring = order[k]
                    var state = B.now(ring.n)
                    var spin = state.turn
                    r0 = B.innerR + state.slot * B.thick
                    band = Math.max(0.6, B.thick * 0.82)
                    // A travelling ring draws lighter, so crossings stay legible.
                    ctx.globalAlpha = state.travelling ? 0.6 : 1
                    // The track, cool for Makki and warm for Madani.
                    var tint = ring.makkan ? root.accent2 : root.accent
                    ctx.strokeStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.07)
                    ctx.lineWidth = band
                    ctx.beginPath()
                    ctx.arc(B.cx, B.cy, r0 + band / 2, B.arcAngle(B.gap / 2 + spin), B.arcAngle(2 * Math.PI - B.gap / 2 + spin))
                    ctx.stroke()
                    // Every āyah, taller for more words.
                    half = usable / ring.ayahCount * 0.36
                    ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.1)
                    for (i = 0; i < ring.ayahCount; i++) {
                      h = band * (0.3 + 0.7 * ring.words[i] / ring.maxWords)
                      a = B.angleAt((i + 0.5) / ring.ayahCount) + spin
                      ctx.lineWidth = h
                      ctx.beginPath()
                      ctx.arc(B.cx, B.cy, r0 + h / 2, B.arcAngle(a - half), B.arcAngle(a + half))
                      ctx.stroke()
                    }
                    // Where the roots stand; cream where they all meet. Each
                    // root has its own radial slot when the ring is thick enough.
                    var slots = B.sel.roots.length
                    for (i = 0; i < ring.hits.length; i++) {
                      var hit = ring.hits[i]
                      h = band * (0.3 + 0.7 * hit.words / ring.maxWords)
                      a = B.angleAt(hit.pos) + spin
                      if (hit.meeting) {
                        ctx.strokeStyle = root.cream
                        ctx.lineWidth = h
                        ctx.beginPath()
                        ctx.arc(B.cx, B.cy, r0 + h / 2, B.arcAngle(a - half * 1.15), B.arcAngle(a + half * 1.15))
                        ctx.stroke()
                        continue
                      }
                      if (slots > 1 && band >= 4) {
                        for (var b = 0; b < slots; b++) {
                          if (!(hit.mask & (1 << b))) continue
                          ctx.strokeStyle = colours[b]
                          ctx.lineWidth = h / slots
                          ctx.beginPath()
                          ctx.arc(B.cx, B.cy, r0 + h / slots * (b + 0.5), B.arcAngle(a - half), B.arcAngle(a + half))
                          ctx.stroke()
                        }
                      } else {
                        var first = 0
                        while (!(hit.mask & (1 << first))) first++
                        ctx.strokeStyle = colours[first]
                        ctx.lineWidth = h
                        ctx.beginPath()
                        ctx.arc(B.cx, B.cy, r0 + h / 2, B.arcAngle(a - half), B.arcAngle(a + half))
                        ctx.stroke()
                      }
                    }
                  }

                  ctx.globalAlpha = 1

                  // Threads: each meeting to the nearest meeting on the next
                  // ring out. They depend on neighbours, so they wait for rest.
                  ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.13)
                  ctx.lineWidth = 0.6
                  for (k = 0; !B.moving && k + 1 < order.length; k++) {
                    var here = order[k].meetings, next = order[k + 1].meetings
                    if (!here.length || !next.length) continue
                    var ra = B.innerR + (k + 0.5) * B.thick, rb = B.innerR + (k + 1.5) * B.thick
                    for (i = 0; i < here.length; i++) {
                      var best = next[0]
                      for (var j = 1; j < next.length; j++)
                        if (Math.abs(next[j].pos - here[i].pos) < Math.abs(best.pos - here[i].pos)) best = next[j]
                      var a1 = B.angleAt(here[i].pos) + B.now(order[k].n).turn, a2 = B.angleAt(best.pos) + B.now(order[k + 1].n).turn
                      ctx.beginPath()
                      ctx.moveTo(B.cx + ra * Math.sin(a1), B.cy - ra * Math.cos(a1))
                      ctx.lineTo(B.cx + rb * Math.sin(a2), B.cy - rb * Math.cos(a2))
                      ctx.stroke()
                    }
                  }
                }
              }

              // Hover: outline the āyah under the pointer, on its own layer so
              // the rings never repaint.
              Canvas {
                id: ringsHover
                anchors.fill: parent
                readonly property var deps: [ringsBox.hoverRing, ringsBox.hoverAyah]
                onDepsChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var B = ringsBox
                  if (B.hoverRing < 0 || B.hoverAyah < 0) return
                  var ring = B.order[B.hoverRing]
                  if (!ring) return
                  var spin = B.now(ring.n).turn
                  var r0 = B.innerR + B.hoverRing * B.thick
                  var band = Math.max(0.6, B.thick * 0.82)
                  var half = (2 * Math.PI - B.gap) / ring.ayahCount * 0.5
                  var a = B.angleAt((B.hoverAyah + 0.5) / ring.ayahCount) + spin
                  var fg = root.contentForeground
                  ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.18)
                  ctx.lineWidth = Math.max(1, B.thick)
                  ctx.beginPath()
                  ctx.arc(B.cx, B.cy, r0 + band / 2, B.arcAngle(B.gap / 2 + spin), B.arcAngle(2 * Math.PI - B.gap / 2 + spin))
                  ctx.stroke()
                  ctx.strokeStyle = fg
                  ctx.lineWidth = Math.max(2, band + 2)
                  ctx.beginPath()
                  ctx.arc(B.cx, B.cy, r0 + band / 2, B.arcAngle(a - Math.max(half, 0.012)), B.arcAngle(a + Math.max(half, 0.012)))
                  ctx.stroke()
                }
              }

              // Scale labels: 0 at the gap's right edge, 100 at its left.
              Repeater {
                model: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

                PlainText {
                  required property int modelData
                  readonly property real angle: ringsBox.angleAt(modelData / 100)
                  x: ringsBox.cx + (ringsBox.outerR + 28) * Math.sin(angle) - implicitWidth / 2
                  y: ringsBox.cy - (ringsBox.outerR + 28) * Math.cos(angle) - implicitHeight / 2
                  text: root.n(modelData)
                  font.family: root.uiFont
                  font.pixelSize: Math.round(Style.font.caption * 0.9)
                  color: root.faint
                }
              }

              Column {
                anchors.centerIn: parent
                width: ringsBox.centreHalf * 2 + Style.space(4)
                spacing: Style.space(2)

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(5)
                  // The first root on the right, as Arabic reads.
                  layoutDirection: Qt.RightToLeft

                  Repeater {
                    model: ringsBox.sel ? ringsBox.sel.roots : []

                    PlainText {
                      required property string modelData
                      required property int index
                      text: (index > 0 ? "· " : "") + modelData
                      font.family: root.arabicFont
                      font.pixelSize: Math.round(Style.font.title * 1.25)
                      font.weight: Font.DemiBold
                      color: index === 0 ? root.accent : (index === 1 ? root.accent2 : root.contentForeground)
                    }
                  }
                }

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: ringsBox.glossLine
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: ringsBox.summaryLine
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.contentForeground
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) {
                  var B = ringsBox
                  if (B.moving) { B.hoverRing = -1; B.hoverAyah = -1; return }
                  var dx = mouse.x - B.cx, dy = mouse.y - B.cy
                  var r = Math.sqrt(dx * dx + dy * dy)
                  var k = Math.floor((r - B.innerR) / Math.max(0.001, B.thick))
                  if (k < 0 || k >= B.order.length) { B.hoverRing = -1; B.hoverAyah = -1; return }
                  var ring = B.order[k]
                  // Undo the ring's turn to find the position on it.
                  var a = Math.atan2(dx, -dy) - B.now(ring.n).turn
                  a = ((a % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI)
                  if (a < B.gap / 2 || a > 2 * Math.PI - B.gap / 2) { B.hoverRing = -1; B.hoverAyah = -1; return }
                  B.hoverRing = k
                  B.hoverAyah = Math.min(ring.ayahCount - 1, Math.floor((a - B.gap / 2) / (2 * Math.PI - B.gap) * ring.ayahCount))
                }
                onExited: { ringsBox.hoverRing = -1; ringsBox.hoverAyah = -1 }
              }
            }

            // What's under the pointer: the reference, and the āyah's words
            // around the chosen roots.
            PlainText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: {
                var B = ringsBox
                var ring = B.hoverRing >= 0 ? B.order[B.hoverRing] : null
                if (!ring || B.hoverAyah < 0) return strings.t("rings.caption")
                var s = strings.t("rings.hover").arg(root.surahLabel(ring.n)).arg(root.n(ring.n)).arg(root.n(B.hoverAyah + 1))
                for (var i = 0; i < ring.hits.length; i++)
                  if (ring.hits[i].ayah === B.hoverAyah + 1 && ring.hits[i].meeting && B.sel.roots.length > 1) return s + "  ·  " + strings.t("rings.meeting")
                return s
              }
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              color: ringsBox.hoverRing >= 0 ? root.contentForeground : root.dim
            }

            PlainText {
              width: parent.width
              visible: text !== ""
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideMiddle
              text: {
                var B = ringsBox
                if (B.hoverRing < 0 || B.hoverAyah < 0 || !root.hostWidget) return ""
                var revision = root.hostWidget.textRevision
                var words = root.hostWidget.concordanceText()
                var ring = B.order[B.hoverRing]
                if (!words || !ring || !words[ring.n - 1] || !words[ring.n - 1][B.hoverAyah]) return ""
                return words[ring.n - 1][B.hoverAyah].join(" ")
              }
              font.family: root.arabicFont
              font.pixelSize: Math.round(Style.font.title * 1.1)
              color: root.contentForeground
            }
          }

          // ---- Concordance: every occurrence in its context ----
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.view === "concordance" && !!root.conc

            PlainText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.shown ? strings.tn("concordance.caption", root.kwic.length).arg(root.n(root.kwic.length)).arg(root.n(root.shown.verses)) : ""
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              color: root.dim
            }

            ListView {
              id: kwicList
              width: parent.width
              height: Math.min(contentHeight, Style.space(300))
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              model: root.kwic
              reuseItems: true

              Connections {
                target: root
                function onKwicChanged() { kwicList.positionViewAtBeginning() }
              }

              delegate: Item {
                id: line
                required property var modelData
                required property int index
                width: kwicList.width
                height: Style.space(30)
                // Arabic order whatever the interface direction: what comes
                // before the word sits to its right, what follows to its left.
                LayoutMirroring.enabled: false
                LayoutMirroring.childrenInherit: true

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: line.index % 2 ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.035) : "transparent"
                }

                PlainText {
                  id: lineRef
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(48)
                  text: root.n(line.modelData.s) + ":" + root.n(line.modelData.a)
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }

                Item {
                  anchors.left: lineRef.right
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  height: parent.height

                  PlainText {
                    id: keyword
                    anchors.centerIn: parent
                    text: line.modelData.word
                    font.family: root.arabicFont
                    font.pixelSize: Math.round(Style.font.title * 1.2)
                    font.weight: Font.DemiBold
                    color: root.accent
                  }

                  // Following words: run leftwards from the keyword, cut at the far end.
                  Item {
                    anchors.left: parent.left
                    anchors.right: keyword.left
                    anchors.rightMargin: Style.space(8)
                    height: parent.height
                    clip: true

                    PlainText {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: line.modelData.after + (line.modelData.clippedAfter ? " …" : "")
                      font.family: root.arabicFont
                      font.pixelSize: Math.round(Style.font.title * 1.05)
                      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.75)
                    }
                  }

                  // Preceding words: run rightwards from the keyword.
                  Item {
                    anchors.left: keyword.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: parent.right
                    height: parent.height
                    clip: true

                    PlainText {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: (line.modelData.clippedBefore ? "… " : "") + line.modelData.before
                      font.family: root.arabicFont
                      font.pixelSize: Math.round(Style.font.title * 1.05)
                      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.75)
                    }
                  }
                }
              }
            }
          }

          // ---- Quran structure map (the site's, occurrence mode): the 114
          // sūrahs round a clock face, length inward, the root's āyahs outward ----
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.view === "structure" && !!root.conc

            Item {
              id: mapBox
              width: parent.width
              height: width
              LayoutMirroring.enabled: false

              readonly property var map: root.structureData
              readonly property real cx: width / 2
              readonly property real cy: height / 2
              // The site's world: arcs at 460-470, dots from 500 outward (up to
              // 880). Scaled to the longest stack this root actually draws, so
              // the map fills its square.
              readonly property real extent: {
                var longest = 0
                if (map) for (var i = 0; i < map.surahs.length; i++) {
                  var d = map.surahs[i].dots
                  if (d > 1) longest = Math.max(longest, (d - 1) * Model.occurrenceStep(d))
                }
                return Math.max(640, 500 + longest + 14)
              }
              readonly property real unit: (Math.min(width, height) / 2 - 4) / extent
              readonly property real slot: 2 * Math.PI / 114
              property int hovered: 0

              function px(angle, r) { return { x: cx + r * unit * Math.sin(angle), y: cy - r * unit * Math.cos(angle) } }

              Canvas {
                anchors.fill: parent
                readonly property var deps: [mapBox.map, mapBox.hovered, mapBox.width, root.contentForeground, root.accent, root.accent2, root.cream]
                onDepsChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var M = mapBox, map = M.map
                  if (!map) return
                  var fg = root.contentForeground
                  for (var i = 0; i < map.surahs.length; i++) {
                    var s = map.surahs[i]
                    var mid = (s.n - 0.5) * M.slot
                    var half = M.slot / 2 * 0.84
                    var hot = M.hovered === s.n
                    var tone = s.makkan ? root.accent2 : root.accent
                    var a0 = mid - half - Math.PI / 2, a1 = mid + half - Math.PI / 2
                    // The arc: the sūrah itself, Makki or Madani.
                    ctx.strokeStyle = Qt.rgba(tone.r, tone.g, tone.b, hot ? 1 : (s.dots ? 0.85 : 0.45))
                    ctx.lineWidth = 10 * M.unit
                    ctx.beginPath()
                    ctx.arc(M.cx, M.cy, 465 * M.unit, a0, a1)
                    ctx.stroke()
                    // Inward: its length in words.
                    var len = s.bar * 120
                    ctx.strokeStyle = Qt.rgba(tone.r, tone.g, tone.b, hot ? 0.6 : 0.22)
                    ctx.lineWidth = len * M.unit
                    ctx.beginPath()
                    ctx.arc(M.cx, M.cy, (460 - 7 - len / 2) * M.unit, mid - half * 0.8 - Math.PI / 2, mid + half * 0.8 - Math.PI / 2)
                    ctx.stroke()
                    // Outward: a dot per āyah holding the root.
                    if (s.dots) {
                      var step = Model.occurrenceStep(s.dots)
                      ctx.fillStyle = hot ? fg : root.cream
                      for (var d = 0; d < s.dots; d++) {
                        var p = M.px(mid, 500 + d * step)
                        ctx.beginPath()
                        ctx.arc(p.x, p.y, Math.max(1, 3.4 * M.unit), 0, 2 * Math.PI)
                        ctx.fill()
                      }
                    }
                  }
                  // The current verse's sūrah, as in the strip: a tick inside.
                  if (root.activeSura > 0) {
                    var am = (root.activeSura - 0.5) * M.slot
                    var q0 = M.px(am, 336), q1 = M.px(am, 452)
                    ctx.strokeStyle = root.accent
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.moveTo(q0.x, q0.y)
                    ctx.lineTo(q1.x, q1.y)
                    ctx.stroke()
                  }
                }
              }

              // A few sūrah numbers round the face, like a clock's hours.
              Repeater {
                model: [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

                PlainText {
                  required property int modelData
                  // Inside the length bars, which reach in to 333.
                  readonly property var at: mapBox.px((modelData - 0.5) * mapBox.slot, 300)
                  x: at.x - implicitWidth / 2
                  y: at.y - implicitHeight / 2
                  text: root.n(modelData)
                  font.family: root.uiFont
                  font.pixelSize: Math.round(Style.font.caption * 0.9)
                  color: root.faint
                }
              }

              Column {
                anchors.centerIn: parent
                width: 600 * mapBox.unit
                spacing: Style.space(3)

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  visible: mapBox.hovered > 0
                  text: strings.t("structure.surah").arg(root.n(mapBox.hovered)).toUpperCase()
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: mapBox.hovered > 0 ? Model.surahName(mapBox.hovered, false) : (root.shown ? root.shown.root : "")
                  font.family: mapBox.hovered > 0 ? root.uiFont : root.arabicFont
                  font.pixelSize: mapBox.hovered > 0 ? Style.font.title : Math.round(Style.font.title * 1.6)
                  font.weight: Font.DemiBold
                  color: root.contentForeground
                }

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  visible: mapBox.hovered > 0
                  text: mapBox.hovered > 0 ? Model.surahName(mapBox.hovered, true) : ""
                  font.family: root.arabicFont
                  font.pixelSize: Math.round(Style.font.title * 1.3)
                  color: root.contentForeground
                }

                PlainText {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.Wrap
                  text: {
                    var map = mapBox.map
                    if (!map) return ""
                    if (mapBox.hovered > 0) {
                      var s = map.surahs[mapBox.hovered - 1]
                      return strings.t("structure.hover").arg(root.n(s.ayahs)).arg(root.n(s.dots))
                    }
                    return strings.t("structure.summary").arg(root.n(map.surahsWithRoot)).arg(root.n(map.ayahsWithRoot))
                  }
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) {
                  var dx = mouse.x - mapBox.cx, dy = mouse.y - mapBox.cy
                  var r = Math.sqrt(dx * dx + dy * dy) / mapBox.unit
                  if (r < 330 || r > mapBox.extent) { mapBox.hovered = 0; return }
                  var a = Math.atan2(dx, -dy)
                  if (a < 0) a += 2 * Math.PI
                  mapBox.hovered = Math.min(114, Math.floor(a / mapBox.slot) + 1)
                }
                onExited: mapBox.hovered = 0
              }
            }

            // Legend: Makki and Madani, as the arcs are tinted.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(14)

              Repeater {
                model: [
                  { tone: root.accent2, label: strings.t("structure.makki") },
                  { tone: root.accent, label: strings.t("structure.madani") },
                  { tone: root.cream, label: strings.t("structure.dot") }
                ]

                Row {
                  required property var modelData
                  spacing: Style.space(5)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: Style.space(2)
                    color: modelData.tone
                  }

                  PlainText {
                    text: modelData.label
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    color: root.dim
                  }
                }
              }
            }
            // Makkan / Madinan, against how much of the text each holds.
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: !!root.dist && root.dist.total > 0

              PanelSectionHeader {
                text: strings.t("dist.split").toUpperCase()
                foreground: root.contentForeground
                fontFamily: root.uiFont
              }

              Item {
                width: parent.width
                height: Style.space(16)

                Rectangle {
                  id: splitTrack
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width
                  height: Style.space(10)
                  radius: Style.space(3)
                  clip: true
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.16)

                  Rectangle {
                    width: root.dist ? Math.round(parent.width * root.dist.makkanShare) : 0
                    height: parent.height
                    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.6)
                  }
                }

                // Where the bar would split if the root were spread evenly.
                Rectangle {
                  x: root.dist ? Math.round(parent.width * root.dist.makkanWordShare) - 1 : 0
                  width: 2
                  height: parent.height
                  radius: 1
                  color: root.contentForeground
                }
              }

              Item {
                width: parent.width
                height: makkanLabel.implicitHeight

                PlainText {
                  id: makkanLabel
                  anchors.left: parent.left
                  text: root.dist ? strings.t("dist.makkan").arg(root.n(Math.round(root.dist.makkanShare * 100))).arg(root.n(root.dist.makkan)) : ""
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.contentForeground
                }

                PlainText {
                  anchors.right: parent.right
                  text: root.dist ? strings.t("dist.madinan").arg(root.n(100 - Math.round(root.dist.makkanShare * 100))).arg(root.n(root.dist.madinan)) : ""
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }

              PlainText {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.dist ? strings.t("dist.wordShare").arg(root.n(Math.round(root.dist.makkanWordShare * 100))) : ""
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                color: root.faint
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.contentForeground }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: strings.t("action.openRoot")
              iconText: ""
              foreground: root.contentForeground
              fontFamily: root.uiFont
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.openRootOnSite()
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: strings.t("action.searchCorpus")
              iconText: ""
              foreground: root.contentForeground
              fontFamily: root.uiFont
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.openSearchOnSite()
            }
          }

          PlainText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: strings.t("footer.source")
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            color: root.faint
          }
        }
      }
    }
  }
}
