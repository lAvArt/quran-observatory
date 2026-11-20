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
  readonly property var levels: shown ? Model.histogramLevels(shown.hist) : []
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
    ? Model.companions(conc, shown.bare, versesOf, 8, 3) : []

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

  readonly property string histogramCaption: {
    if (!shown) return ""
    if (hoveredSurah > 0)
      return strings.t("hist.hover").arg(surahLabel(hoveredSurah)).arg(n(hoveredSurah)).arg(n(shown.hist[hoveredSurah - 1]))
    var tops = []
    for (var i = 0; i < shown.top.length && i < 3; i++)
      tops.push(strings.t("hist.topEntry").arg(surahLabel(shown.top[i][0])).arg(n(shown.top[i][1])))
    return tops.length ? strings.t("hist.mostIn").arg(tops.join(", ")) : ""
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

            Item {
              id: network
              width: parent.width
              height: Style.space(250)
              visible: root.companionList.length > 0

              property int hovered: -1
              readonly property real cx: width / 2
              readonly property real cy: height / 2
              // Node centres keep clear of the edges by half a node.
              readonly property real rx: Math.max(0, width / 2 - Style.space(64))
              readonly property real ry: Math.max(0, height / 2 - Style.space(26))
              readonly property int maxShared: {
                var m = 0
                for (var i = 0; i < root.companionList.length; i++) m = Math.max(m, root.companionList[i].shared)
                return m
              }
              function angle(i) { return -Math.PI / 2 + 2 * Math.PI * i / Math.max(1, root.companionList.length) }
              function px(i) { return cx + rx * Math.cos(angle(i)) }
              function py(i) { return cy + ry * Math.sin(angle(i)) }

              onHoveredChanged: edges.requestPaint()

              Connections {
                target: root
                function onCompanionListChanged() { network.hovered = -1 }
              }

              // Spokes, heavier for more shared āyahs.
              Canvas {
                id: edges
                anchors.fill: parent
                readonly property var deps: [root.companionList, network.width, network.height, root.contentForeground, root.accent]
                onDepsChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var list = root.companionList
                  var fg = root.contentForeground
                  for (var i = 0; i < list.length; i++) {
                    var t = network.maxShared > 0 ? list[i].shared / network.maxShared : 0
                    ctx.strokeStyle = i === network.hovered ? root.accent : Qt.rgba(fg.r, fg.g, fg.b, 0.14 + 0.4 * t)
                    ctx.lineWidth = 1 + 4 * t
                    ctx.beginPath()
                    ctx.moveTo(network.cx, network.cy)
                    ctx.lineTo(network.px(i), network.py(i))
                    ctx.stroke()
                  }
                }
              }

              Rectangle {
                width: centreLabel.implicitWidth + Style.space(22)
                height: centreLabel.implicitHeight + Style.space(6)
                x: network.cx - width / 2
                y: network.cy - height / 2
                radius: Style.space(6)
                color: Color.popups.background
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.45)

                PlainText {
                  id: centreLabel
                  anchors.centerIn: parent
                  text: root.shown ? root.shown.root : ""
                  font.family: root.arabicFont
                  font.pixelSize: Math.round(Style.font.title * 1.5)
                  font.weight: Font.DemiBold
                  color: root.contentForeground
                }
              }

              Repeater {
                model: root.companionList

                Rectangle {
                  id: node
                  required property var modelData
                  required property int index
                  readonly property var info: root.index ? root.index.roots[modelData.bare] : null
                  readonly property bool hot: network.hovered === index
                  width: Math.max(nodeRoot.implicitWidth, nodeGloss.width) + Style.space(14)
                  height: nodeColumn.implicitHeight + Style.space(6)
                  x: network.px(index) - width / 2
                  y: network.py(index) - height / 2
                  radius: Style.space(5)
                  color: Color.popups.background
                  border.width: 1
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, hot ? 0.5 : 0.16)

                  Column {
                    id: nodeColumn
                    anchors.centerIn: parent

                    PlainText {
                      id: nodeRoot
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: node.info ? node.info.root : node.modelData.bare
                      font.family: root.arabicFont
                      font.pixelSize: Math.round(Style.font.title * 1.15)
                      color: node.hot ? root.accent : root.contentForeground
                    }

                    PlainText {
                      id: nodeGloss
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: Math.min(implicitWidth, Style.space(96))
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                      text: node.info ? Model.shortMeaning(node.info) : ""
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      color: root.dim
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: network.hovered = node.index
                    onExited: if (network.hovered === node.index) network.hovered = -1
                    onClicked: root.pick({ bare: node.modelData.bare })
                  }
                }
              }
            }

            PlainText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              readonly property var hoveredCompanion: network.hovered >= 0 ? root.companionList[network.hovered] : null
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

            // Occurrences per sūrah, 1 to 114 in reading order.
            Column {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: strings.t("dist.perSurah").toUpperCase()
                foreground: root.contentForeground
                fontFamily: root.uiFont
              }

              Item {
                width: parent.width
                height: Style.space(40)

                Row {
                  id: histRow
                  anchors.fill: parent
                  spacing: 1
                  readonly property real slot: (width - 113) / 114

                  Repeater {
                    model: root.levels

                    Item {
                      required property real modelData
                      required property int index
                      readonly property int surah: index + 1
                      width: histRow.slot
                      height: histRow.height

                      Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: modelData > 0 ? Math.max(2, Math.round(parent.height * modelData)) : 1
                        radius: Math.min(1.5, width / 2)
                        color: root.hoveredSurah === parent.surah ? root.accent
                          : (modelData > 0 ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.35 + 0.45 * modelData)
                            : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08))
                      }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onPositionChanged: function(mouse) {
                    var bar = histRow.childAt(mouse.x, histRow.height / 2)
                    root.hoveredSurah = bar && bar.surah ? bar.surah : 0
                  }
                  onExited: root.hoveredSurah = 0
                }
              }

              PlainText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.histogramCaption
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                color: root.hoveredSurah > 0 ? root.contentForeground : root.dim
              }
            }

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
