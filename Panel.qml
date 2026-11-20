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
// Keyboard: type to search, Up/Down and Enter pick a result, Escape steps
// back (clears the search, returns to today's root, then closes). With the
// search empty, Left/Right step through the verses and Enter opens the root
// on quranobservatory.org; Ctrl+Enter always searches the corpus there.
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

  onShownChanged: { exampleIndex = 0; hoveredSurah = 0 }
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

          // Occurrences per sūrah, 1 to 114 in reading order.
          Column {
            width: parent.width
            spacing: Style.space(4)

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

          PanelSeparator { width: parent.width; foreground: root.contentForeground }

          // ---- Verses ----
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

          // Each word its own plain Text, so the root's words can be coloured
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
