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
  property int hoveredCell: 0

  // The diagram under the root's numbers. Only the open one is computed.
  readonly property var views: ["verses", "companions", "concordance", "distribution"]
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

  readonly property var dist: view === "distribution" && shown && conc ? Model.distribution(conc, shown.bare) : null
  readonly property real densityMax: dist ? Model.maxOf(dist.density) : 0

  function stepView(delta) {
    view = views[Model.moveSelection(Math.max(0, views.indexOf(view)), delta, views.length)]
  }

  onShownChanged: { exampleIndex = 0; hoveredSurah = 0; hoveredCell = 0 }
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
              { value: "concordance", label: strings.t("view.concordance") },
              { value: "distribution", label: strings.t("view.distribution") }
            ]
            value: root.view
            foreground: root.contentForeground
            fontFamily: root.uiFont
            fontSize: Style.font.bodySmall
            onChanged: function(v) { root.view = v }
          }

          PlainText {
            width: parent.width
            visible: root.view !== "verses" && root.view !== "distribution" && !root.conc
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

          // ---- Distribution: across the sūrahs ----
          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.view === "distribution"

            // Per thousand words: the 114 sūrahs as a grid, darker where the
            // root is used more for the sūrah's length.
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: !!root.dist

              PanelSectionHeader {
                text: strings.t("dist.density").toUpperCase()
                foreground: root.contentForeground
                fontFamily: root.uiFont
              }

              Item {
                width: parent.width
                height: densityGrid.height

                Grid {
                  id: densityGrid
                  anchors.horizontalCenter: parent.horizontalCenter
                  columns: 19
                  spacing: 2
                  readonly property real cell: Math.floor((parent.width - 18 * spacing) / 19)

                  Repeater {
                    model: root.dist ? root.dist.density : []

                    Rectangle {
                      required property real modelData
                      required property int index
                      readonly property int surah: index + 1
                      readonly property real level: root.densityMax > 0 ? modelData / root.densityMax : 0
                      width: densityGrid.cell
                      height: Math.round(densityGrid.cell * 0.72)
                      radius: Style.space(2)
                      color: root.hoveredCell === surah ? root.accent
                        : (modelData > 0 ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12 + 0.75 * Math.sqrt(level))
                          : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04))
                    }
                  }
                }

                MouseArea {
                  anchors.fill: densityGrid
                  hoverEnabled: true
                  onPositionChanged: function(mouse) {
                    var cell = densityGrid.childAt(mouse.x, mouse.y)
                    root.hoveredCell = cell && cell.surah ? cell.surah : 0
                  }
                  onExited: root.hoveredCell = 0
                }
              }

              PlainText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.hoveredCell > 0 && root.dist
                  ? strings.t("dist.densityHover").arg(root.surahLabel(root.hoveredCell)).arg(root.n(root.hoveredCell))
                      .arg(Commons.I18n.formatNumber(root.dist.density[root.hoveredCell - 1], 1))
                  : strings.t("dist.densityCaption")
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                color: root.hoveredCell > 0 ? root.contentForeground : root.dim
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
