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
  readonly property string dataStatus: data.status
  readonly property bool dataBusy: data.busy
  readonly property bool updatesOff: data.updateInterval === "Off"
  readonly property var today: Model.rootOfTheDay(index, day)

  readonly property string icon: ""

  // A direction mark first, so the Arabic root and the English gloss sit in
  // reading order for the interface language whichever comes first.
  // "196×": how often today's root occurs, shown after it unless turned off.
  readonly property bool showCount: String(setting("showCount", "On")) !== "Off"
  readonly property string countText: today && showCount ? strings.t("result.count").arg(Commons.I18n.formatNumber(today.count)) : ""

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
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // Labels with Arabic in them are drawn here rather than by WidgetButton:
  // its single bar-font Text leaves the root to a fallback font whose taller
  // line box lifts the gloss off the bar's baseline. Here the root gets a
  // real Arabic font and sits on the gloss's baseline, and the pair is
  // centred on figure height exactly as WidgetButton centres its own label.
  readonly property bool customLabel: !vertical && !!today && (labelStyle === "Root and meaning" || labelStyle === "Root")
  readonly property string glossText: today ? (today.gloss || Model.compactTranslit(today.translit)) : ""

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.customLabel ? "" : (root.vertical || root.labelText === "" ? root.icon : root.labelText)
    labelVisible: !root.customLabel
    hasVisualContent: root.customLabel || text !== ""
    fixedWidth: root.customLabel ? Math.ceil(customRow.implicitWidth + 2 * scaledHorizontalMargin) : -1
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

    Item {
      id: customLabelBox
      visible: root.customLabel
      anchors.centerIn: parent
      anchors.verticalCenterOffset: (barMetrics.descent - barMetrics.ascent + barMetrics.tightBoundingRect("0").height) / 2
      width: customRow.implicitWidth
      height: glossLabel.implicitHeight
      scale: button.pressScale

      Row {
        id: customRow
        spacing: Style.space(6)

        PlainText {
          id: rootLabel
          anchors.baseline: glossLabel.baseline
          text: root.today ? root.today.root : ""
          font.family: root.arabicFont
          font.pixelSize: Math.round(button.fontSize * 1.35)
          color: button.foreground
        }

        PlainText {
          id: glossLabel
          visible: root.labelStyle === "Root and meaning" && root.glossText !== ""
          text: "· " + root.glossText
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
          color: button.foreground
        }

        PlainText {
          id: countLabel
          anchors.baseline: glossLabel.baseline
          visible: root.countText !== ""
          text: "· " + root.countText
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
          color: button.foreground
        }
      }
    }
  }
}
