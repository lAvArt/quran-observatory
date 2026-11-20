import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Today's root in the bar, and the host for the panel.
//
// The root of the day is worked out here from the cached index, exactly as
// quranobservatory.org works it out in the browser, so the bar and the
// site's homepage always agree. Left click opens the panel; right click
// opens today's root on the site.
BarWidget {
  id: root
  moduleName: "io.github.lavart.quran-observatory"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string labelStyle: String(setting("label", "Root and meaning"))
  readonly property string arabicFont: String(setting("arabicFont", "Noto Naskh Arabic")) || "Noto Naskh Arabic"

  // Local days since the epoch; the root changes when this does.
  property int day: Model.epochDay(new Date())

  readonly property var index: data.index
  readonly property var forms: data.forms
  readonly property var concordance: data.concordance
  readonly property int textRevision: data.textRevision
  readonly property string dataStatus: data.status
  readonly property bool dataBusy: data.busy
  readonly property bool updatesOff: data.updateInterval === "Off"
  readonly property var today: Model.rootOfTheDay(index, day)

  readonly property string icon: ""

  // "196×": how often today's root occurs, shown after it unless turned off.
  readonly property bool showCount: String(setting("showCount", "On")) !== "Off"
  readonly property string countText: today && showCount ? strings.t("result.count").arg(Commons.I18n.formatNumber(today.count)) : ""

  // A direction mark first, so the Arabic root and the English gloss sit in
  // reading order for the interface language whichever comes first.
  readonly property string labelText: {
    var s = Model.barLabel(today, labelStyle, countText)
    if (!s) return ""
    return (Commons.I18n.rightToLeft ? "‏" : "‎") + s
  }

  readonly property string tooltipText: {
    if (!today) return strings.t("bar.tooltipEmpty")
    var lines = [strings.t("bar.tooltip").arg(today.root).arg(today.translit)]
    if (today.gloss) lines.push(today.gloss)
    lines.push(strings.tn("stat.occurrences", today.count).arg(Commons.I18n.formatNumber(today.count)))
    return lines.join("\n")
  }

  function refreshData() { data.refresh(true) }
  function concordanceText() { return data.concordanceText() }

  function openRootOnSite(bare) {
    var target = bare || (today ? today.bare : "")
    if (target) Qt.openUrlExternally(Model.rootUrl(target, Model.siteLanguage(Commons.I18n.language)))
  }

  // ---- Panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function openSearch(query) { if (panelLoader.item) panelLoader.item.openWithQuery(String(query || "")) }
  function openView(name) { if (panelLoader.item) panelLoader.item.openView(String(name || "")) }

  readonly property real openPanelIndicatorWidth: customLabel ? customRow.implicitWidth
    : (button.labelWidth > 0 ? button.labelWidth : Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55)))
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  RootIndex {
    id: data
    updateInterval: String(root.setting("updates", "Weekly"))
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.day = Model.epochDay(date)
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.lavart.quran-observatory"

    function today(): string { return Model.todayText(root.today) }
    function refresh(): void { root.refreshData() }
    function search(query: string): void { root.openSearch(query) }
    // verses | companions | concordance | distribution
    function view(name: string): void { root.openView(name) }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ---- The label.
  //
  // "Chip" (the default) sets the widget apart from the plain-text clock and
  // indicators around it: a faint, softly rounded frame in the bar's own
  // foreground (no theme colour), a hairline before the meaning, and the
  // count in a small badge. "Plain" is the same content without the frame.
  //
  // Either way the label is drawn here rather than by WidgetButton: its single
  // bar-font Text leaves the Arabic to a fallback font whose taller line box
  // lifts the rest off the bar's baseline. Here the root gets a real Arabic
  // font and sits on the meaning's baseline, centred on figure height the way
  // WidgetButton centres its own labels.
  readonly property bool chip: String(setting("barStyle", "Chip")) !== "Plain"
  readonly property bool arabicRoot: labelStyle === "Root and meaning" || labelStyle === "Root"
  readonly property bool customLabel: !vertical && !!today && labelStyle !== "Icon only" && (chip || arabicRoot)
  readonly property bool showsMeaning: labelStyle !== "Root" && glossText !== ""
  readonly property string glossText: {
    if (!today) return ""
    if (labelStyle === "Transliteration and meaning") return today.gloss
    return today.gloss || Model.compactTranslit(today.translit)
  }
  readonly property bool hot: button.tooltipHovered || opened

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.customLabel ? "" : (root.vertical || root.labelText === "" ? root.icon : root.labelText)
    labelVisible: !root.customLabel
    hasVisualContent: root.customLabel || text !== ""
    fixedWidth: root.customLabel ? Math.ceil(capsule.width + 2 * Style.space(root.chip ? 4 : 8.75)) : -1
    tooltipText: root.opened ? "" : root.tooltipText
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openRootOnSite("")
      else root.togglePanel()
    }

    FontMetrics {
      id: barMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
    }

    // Neutral on purpose: a faint tint of the bar's own foreground and a
    // hairline edge, so it reads as one unit without competing with the theme.
    Rectangle {
      id: capsule
      visible: root.customLabel
      anchors.centerIn: parent
      width: customRow.implicitWidth + (root.chip ? 2 * Style.space(10) : 0)
      height: Math.round(Math.min(button.height - 2, Style.bar.sizeHorizontal * 0.88))
      radius: Style.space(5)
      scale: button.pressScale
      color: root.chip ? Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, root.hot ? 0.12 : 0.06) : "transparent"
      border.width: root.chip ? 1 : 0
      border.color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, root.hot ? 0.34 : 0.18)
      Behavior on color { ColorAnimation { duration: Style.duration(140) } }

      Item {
        id: labelBox
        // Latin text is centred on figure height, as WidgetButton does.
        readonly property real figureOffset: (barMetrics.descent - barMetrics.ascent + barMetrics.tightBoundingRect("0").height) / 2
        // The capsule's middle, in this item's coordinates.
        readonly property real middle: height / 2 - figureOffset
        anchors.centerIn: parent
        anchors.verticalCenterOffset: figureOffset
        width: customRow.implicitWidth
        height: glossLabel.implicitHeight

        // The Arabic root's ink, measured at a fixed reference size so its
        // own font size can depend on it without a binding loop.
        FontMetrics {
          id: arabicRef
          font.family: root.arabicFont
          font.pixelSize: 100
          font.weight: root.chip ? Font.DemiBold : Font.Normal
        }

        Row {
          id: customRow
          spacing: Style.space(7)

          PlainText {
            id: iconLabel
            visible: root.chip
            anchors.baseline: glossLabel.baseline
            text: root.icon
            font.family: button.fontFamily
            font.pixelSize: Math.round(button.fontSize * 0.85)
            color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.6)
          }

          // Arabic is centred on its own ink, not set on the Latin baseline:
          // Naskh hangs its tails and dots far below the line, so a shared
          // baseline sank the root to the capsule's bottom edge. Its size is
          // also capped so the ink always clears the edges.
          PlainText {
            id: rootLabel
            readonly property rect ink: arabicRef.tightBoundingRect(text)
            readonly property real inkRoom: capsule.height - 2 * Style.space(4)
            readonly property real arabicSize: ink.height > 0
              ? Math.min(button.fontSize * 1.15, inkRoom * 100 / ink.height) : button.fontSize * 1.15
            text: !root.today ? "" : (root.arabicRoot ? root.today.root : Model.compactTranslit(root.today.translit))
            font.family: root.arabicRoot ? root.arabicFont : button.fontFamily
            font.pixelSize: root.arabicRoot ? Math.max(1, Math.floor(arabicSize)) : button.fontSize
            font.weight: root.chip ? Font.DemiBold : Font.Normal
            color: button.foreground
            y: root.arabicRoot
              ? labelBox.middle - (ink.y + ink.height / 2) * font.pixelSize / 100 - baselineOffset
              : glossLabel.baselineOffset - baselineOffset
          }

          // A hairline rather than a dot, so the separator doesn't read as
          // one more glyph among the clock's.
          Rectangle {
            visible: root.showsMeaning
            anchors.verticalCenter: glossLabel.verticalCenter
            width: 1
            height: Math.round(button.fontSize * 0.9)
            color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.35)
          }

          // The meaning text. Always present: the root, icon and badge sit on
          // its baseline even when it is hidden in the "Root" style.
          PlainText {
            id: glossLabel
            visible: root.showsMeaning
            text: root.glossText
            font.family: button.fontFamily
            font.pixelSize: button.fontSize
            renderType: Text.NativeRendering
            color: button.foreground
          }

          Rectangle {
            id: countBadge
            visible: root.countText !== ""
            anchors.verticalCenter: glossLabel.verticalCenter
            width: countLabel.implicitWidth + Style.space(10)
            height: Math.round(countLabel.implicitHeight * 0.95)
            radius: Style.space(3)
            color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, root.chip ? 0.08 : 0)

            PlainText {
              id: countLabel
              anchors.centerIn: parent
              text: root.countText
              font.family: button.fontFamily
              font.pixelSize: Math.round(button.fontSize * 0.85)
              renderType: Text.NativeRendering
              color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.7)
            }
          }
        }
      }
    }
  }
}
