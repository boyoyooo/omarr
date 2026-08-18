import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.yelbaz.arr-plus"

  // --- settings, read from this widget's shell.json entry -------------------
  readonly property string app:           setting("app", "radarr")
  readonly property string url:           setting("url", "http://localhost:7878")
  readonly property string apiKeyFile:    setting("apiKeyFile", "")
  readonly property int    interval:      setting("interval", 60)
  readonly property string label:         setting("label", "")
  readonly property int    qualityProfileId: setting("qualityProfileId", 1)
  readonly property string rootFolderPath: setting("rootFolderPath", "/data")
  // Sonarr-only, ignored by the radarr scripts:
  readonly property bool   seasonFolder:  setting("seasonFolder", true)
  readonly property string monitorMode:   setting("monitorMode", "all")

  readonly property string logoSource: app === "sonarr"
    ? Qt.resolvedUrl("sonarr.png") : Qt.resolvedUrl("radarr.png")
  readonly property string displayName: label || (app === "sonarr" ? "Sonarr" : "Radarr")

  // --- state, consumed by Panel.qml ----------------------------------------
  property var    status: null
  property string errorText: ""
  property bool   everLoaded: false
  property bool   fetching: false

  readonly property bool healthy: errorText === ""
  readonly property int  missingCount: status ? (status.missing || 0) : 0
  readonly property int  queueCount:   status ? (status.queue || 0) : 0
  readonly property bool alerting: everLoaded && !healthy

  readonly property string statusScriptPath:
    Qt.resolvedUrl("bin/arr-status.sh").toString().replace(/^file:\/\//, "")

  // --- panel plumbing (same contract as the built-in clock) -----------------
  readonly property bool opened:
    panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing:
    panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open()   { if (panelLoader.item) panelLoader.item.open() }
  function close()  { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  // --- polling (lightweight counts only, full library is fetched on-demand
  // by Panel.qml when the Library tab is opened) -----------------------------
  function applyPayload(text) {
    root.everLoaded = true
    var payload
    try {
      payload = JSON.parse(text)
    } catch (e) {
      root.errorText = "invalid response from poller"
      return
    }
    if (payload.error) {
      root.errorText = String(payload.error)
      return
    }
    root.errorText = ""
    root.status = payload
  }

  function refresh() {
    if (fetcher.running) return
    fetcher.running = true
  }

  onOpenedChanged: if (root.opened) root.refresh()

  Process {
    id: fetcher
    running: false
    command: [root.statusScriptPath, root.app, root.url, root.apiKeyFile]
    onRunningChanged: root.fetching = fetcher.running
    stdout: StdioCollector {
      onStreamFinished: root.applyPayload(this.text)
    }
  }

  Timer {
    // Fast retry (5s) while the last fetch errored — smooths over the boot
    // race where quickshell starts before the LAN route to the NAS is up.
    interval: (root.opened ? 30
      : root.errorText !== "" ? 5
      : Math.max(30, root.interval)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
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

  MouseArea {
    id: button
    anchors.fill: parent
    implicitWidth: rowContent.implicitWidth + Style.space(16)
    implicitHeight: Style.bar.sizeHorizontal
    hoverEnabled: true
    onClicked: function (mouse) {
      if (mouse.button === Qt.LeftButton) root.toggle()
      else if (mouse.button === Qt.MiddleButton) root.refresh()
    }

    Row {
      id: rowContent
      anchors.centerIn: parent
      spacing: Style.space(6)

      Image {
        anchors.verticalCenter: parent.verticalCenter
        source: root.logoSource
        width: Style.space(16)
        height: Style.space(16)
        fillMode: Image.PreserveAspectFit
        smooth: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
          if (!root.everLoaded) return "…"
          if (!root.healthy) return "!"
          var t = String(root.missingCount)
          if (root.queueCount > 0) t += " ↓" + root.queueCount
          return t
        }
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
