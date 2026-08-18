import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.yelbaz.arr-plus"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property string app:      hostWidget ? hostWidget.app : "radarr"
  readonly property string url:      hostWidget ? hostWidget.url : ""
  readonly property string apiKeyFile: hostWidget ? hostWidget.apiKeyFile : ""
  readonly property string title:    hostWidget ? hostWidget.displayName : "Arr+"
  readonly property bool   fetching: hostWidget ? hostWidget.fetching === true : false
  readonly property int    defaultQualityProfileId: hostWidget ? hostWidget.qualityProfileId : 1
  readonly property string rootFolderPath:   hostWidget ? hostWidget.rootFolderPath : "/data"
  readonly property bool   defaultSeasonFolder: hostWidget ? hostWidget.seasonFolder : true

  readonly property int pageSize: 15

  // "library" | "add" | "queue"
  property string activeTab: "library"

  // ---------------------------------------------------------------------
  // Library tab
  // ---------------------------------------------------------------------
  property var    libraryItems: []
  property bool   libraryLoaded: false
  property string librarySearch: ""
  property string libraryFilter: "all" // "all" | "downloaded" | "missing"
  property int    libraryPage: 0

  readonly property var filteredLibrary: {
    var items = libraryItems
    if (libraryFilter === "downloaded") items = items.filter(function (it) { return it.hasFile })
    else if (libraryFilter === "missing") items = items.filter(function (it) { return it.monitored && !it.hasFile })
    if (librarySearch) {
      var needle = librarySearch.toLowerCase()
      items = items.filter(function (it) { return it.title.toLowerCase().indexOf(needle) !== -1 })
    }
    items = items.slice() // don't sort the original array in place
    if (librarySort === "titleAsc")
      items.sort(function (a, b) { return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : 1 })
    else if (librarySort === "titleDesc")
      items.sort(function (a, b) { return a.title.toLowerCase() > b.title.toLowerCase() ? -1 : 1 })
    else if (librarySort === "addedDesc")
      items.sort(function (a, b) { return (a.added || "") < (b.added || "") ? 1 : -1 })
    else if (librarySort === "addedAsc")
      items.sort(function (a, b) { return (a.added || "") > (b.added || "") ? 1 : -1 })
    return items
  }
  readonly property int libraryPageCount: Math.max(1, Math.ceil(filteredLibrary.length / pageSize))
  readonly property var pagedLibrary: filteredLibrary.slice(libraryPage * pageSize, libraryPage * pageSize + pageSize)

  property string librarySort: "titleAsc" // "titleAsc" | "titleDesc" | "addedDesc" | "addedAsc"
  property var    expandedLibraryId: null

  onLibraryFilterChanged: libraryPage = 0
  onLibrarySearchChanged: libraryPage = 0
  onLibrarySortChanged: libraryPage = 0

  // ---------------------------------------------------------------------
  // Add tab
  // ---------------------------------------------------------------------
  property var    lookupResults: []
  property bool   lookupBusy: false
  property string addSearchTerm: ""
  property int    addPage: 0
  readonly property int addPageCount: Math.max(1, Math.ceil(lookupResults.length / pageSize))
  readonly property var pagedResults: lookupResults.slice(addPage * pageSize, addPage * pageSize + pageSize)

  property var    profiles: []
  property bool   profilesLoaded: false

  // key = tmdbId/tvdbId of the result currently expanded for add-config
  property var    expandedId: null
  property int    expandedProfileId: 0
  property bool   expandedSeasonFolder: true
  property var    expandedSeasons: ({}) // {seasonNumber: bool}

  property var    addBusyIds: ({})
  property var    addedIds: ({})

  readonly property string libraryScriptPath:
    Qt.resolvedUrl("bin/arr-library.sh").toString().replace(/^file:\/\//, "")
  readonly property string queueScriptPath:
    Qt.resolvedUrl("bin/arr-queue.sh").toString().replace(/^file:\/\//, "")
  readonly property string lookupScriptPath:
    Qt.resolvedUrl("bin/arr-lookup.sh").toString().replace(/^file:\/\//, "")
  readonly property string addScriptPath:
    Qt.resolvedUrl("bin/arr-add.sh").toString().replace(/^file:\/\//, "")
  readonly property string profilesScriptPath:
    Qt.resolvedUrl("bin/arr-profiles.sh").toString().replace(/^file:\/\//, "")

  // ---------------------------------------------------------------------
  // Queue tab
  // ---------------------------------------------------------------------
  property var    queueItems: []
  property bool   queueLoaded: false

  function open()  { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // Reload whatever tab is visible every time the panel opens, so it never
  // shows stale/empty data until a manual refresh (was the #1 complaint).
  onOpenedChanged: if (root.opened) root.selectTab(root.activeTab)

  function selectTab(tab) {
    root.activeTab = tab
    root.expandedId = null
    if (tab === "library") root.loadLibrary()
    else if (tab === "queue") root.loadQueue()
    else if (tab === "add") {
      if (!root.profilesLoaded) root.loadProfiles()
      Qt.callLater(function () { addSearchField.forceActiveFocus() })
    }
  }

  function loadLibrary() {
    if (libraryProc.running) return
    libraryProc.command = [root.libraryScriptPath, root.app, root.url, root.apiKeyFile]
    libraryProc.running = true
  }

  function loadQueue() {
    if (queueProc.running) return
    queueProc.command = [root.queueScriptPath, root.app, root.url, root.apiKeyFile]
    queueProc.running = true
  }

  function loadProfiles() {
    if (profilesProc.running) return
    profilesProc.command = [root.profilesScriptPath, root.app, root.url, root.apiKeyFile]
    profilesProc.running = true
  }

  function runLookup() {
    if (lookupProc.running || !root.addSearchTerm) return
    root.lookupBusy = true
    root.addPage = 0
    root.expandedId = null
    lookupProc.command = [root.lookupScriptPath, root.app, root.url, root.apiKeyFile, root.addSearchTerm]
    lookupProc.running = true
  }

  function extIdOf(result) { return root.app === "radarr" ? result.tmdbId : result.tvdbId }

  function toggleExpand(result) {
    var id = root.extIdOf(result)
    if (root.expandedId === id) {
      root.expandedId = null
      return
    }
    root.expandedId = id
    root.expandedProfileId = root.profiles.length ? root.profiles[0].id : root.defaultQualityProfileId
    root.expandedSeasonFolder = root.defaultSeasonFolder
    var seasons = {}
    if (result.seasons) {
      for (var i = 0; i < result.seasons.length; i++)
        seasons[result.seasons[i].seasonNumber] = result.seasons[i].monitored
    }
    root.expandedSeasons = seasons
  }

  function toggleSeason(seasonNumber) {
    // Rebuild a fresh object (not mutate-in-place) so QML's change
    // notification actually fires — reassigning the same object reference
    // is a no-op as far as property bindings are concerned.
    var s = {}
    for (var k in root.expandedSeasons) s[k] = root.expandedSeasons[k]
    s[seasonNumber] = !s[seasonNumber]
    root.expandedSeasons = s
  }

  function confirmAdd(result) {
    var id = root.extIdOf(result)
    if (addProc.running) return
    var busy = {}
    for (var bk in root.addBusyIds) busy[bk] = root.addBusyIds[bk]
    busy[id] = true
    root.addBusyIds = busy
    root.expandedId = null

    if (root.app === "radarr") {
      addProc.command = [root.addScriptPath, "radarr", root.url, root.apiKeyFile,
                          String(id), String(root.expandedProfileId), root.rootFolderPath, "true"]
    } else {
      // If the user ends up with zero seasons checked (whether they never
      // touched the picker, or unchecked everything they started with),
      // fall back to Sonarr's own "all" default rather than silently
      // monitoring nothing — a no-op add is a much worse failure mode than
      // over-monitoring.
      var seasonsCsv = "_all"
      var picked = []
      for (var num in root.expandedSeasons) if (root.expandedSeasons[num]) picked.push(num)
      if (picked.length > 0) seasonsCsv = picked.join(",")
      addProc.command = [root.addScriptPath, "sonarr", root.url, root.apiKeyFile,
                          String(id), String(root.expandedProfileId), root.rootFolderPath, "true",
                          root.expandedSeasonFolder ? "true" : "false", seasonsCsv]
    }
    addProc.lastId = id
    addProc.running = true
  }

  Process {
    id: libraryProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.libraryLoaded = true
        root.libraryPage = 0
        try {
          var payload = JSON.parse(this.text)
          root.libraryItems = payload.error ? [] : payload
        } catch (e) {
          root.libraryItems = []
        }
      }
    }
  }

  Process {
    id: queueProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.queueLoaded = true
        try {
          var payload = JSON.parse(this.text)
          root.queueItems = payload.error ? [] : payload
        } catch (e) {
          root.queueItems = []
        }
      }
    }
  }

  Process {
    id: profilesProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.profilesLoaded = true
        try {
          var payload = JSON.parse(this.text)
          root.profiles = payload.error ? [] : payload
        } catch (e) {
          root.profiles = []
        }
      }
    }
  }

  Process {
    id: lookupProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.lookupBusy = false
        try {
          var payload = JSON.parse(this.text)
          root.lookupResults = payload.error ? [] : payload
        } catch (e) {
          root.lookupResults = []
        }
      }
    }
  }

  Process {
    id: addProc
    property var lastId: null
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var id = addProc.lastId
        var busy = {}
        for (var bk in root.addBusyIds) if (bk != id) busy[bk] = root.addBusyIds[bk]
        root.addBusyIds = busy
        try {
          var payload = JSON.parse(this.text)
          if (payload.ok) {
            var added = {}
            for (var ak in root.addedIds) added[ak] = root.addedIds[ak]
            added[id] = true
            root.addedIds = added
          }
        } catch (e) { /* leave un-added on parse failure, user can retry */ }
      }
    }
  }

  function gib(bytes) { return (bytes / 1073741824).toFixed(1) }

  function openImdb(imdbId) {
    if (!imdbId) return
    openUrlProc.command = ["xdg-open", "https://www.imdb.com/title/" + imdbId]
    openUrlProc.running = true
  }

  Process {
    id: openUrlProc
    running: false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(560)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Image {
              anchors.verticalCenter: parent.verticalCenter
              source: root.hostWidget ? root.hostWidget.logoSource : ""
              width: Style.space(22)
              height: Style.space(22)
              fillMode: Image.PreserveAspectFit
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.title
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Item { width: parent.width - Style.space(260); height: 1 }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Refresh"
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              fontSize: Style.font.icon + 4
              onClicked: {
                if (root.activeTab === "library") {
                  root.libraryLoaded = false
                  root.loadLibrary()
                } else if (root.activeTab === "queue") {
                  root.queueLoaded = false
                  root.loadQueue()
                } else if (root.activeTab === "add" && root.addSearchTerm) {
                  root.runLookup()
                }
                if (root.hostWidget) root.hostWidget.refresh()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: [
                { key: "library", label: "Bibliothèque" },
                { key: "add",     label: "Ajouter" },
                { key: "queue",   label: "File" }
              ]
              delegate: Rectangle {
                width: tabText.implicitWidth + Style.space(20)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: root.activeTab === modelData.key
                  ? Util.alpha(root.barForeground, 0.18)
                  : Util.alpha(root.barForeground, 0.06)

                Text {
                  id: tabText
                  anchors.centerIn: parent
                  text: modelData.label
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: root.activeTab === modelData.key
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.selectTab(modelData.key)
                }
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ---------------------------------------------------------------
          // Library tab
          // ---------------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.activeTab === "library"

            Item {
              width: parent.width
              height: Style.space(32)

              TextField {
                id: librarySearchField
                anchors.fill: parent
                rightPadding: Style.space(26)
                placeholderText: "Filter by title…"
                text: root.librarySearch
                onTextChanged: root.librarySearch = text
              }

              Text {
                visible: root.librarySearch.length > 0
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                color: Util.alpha(root.barForeground, 0.6)
                font.pixelSize: Style.font.bodySmall
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(6)
                  onClicked: { librarySearchField.text = ""; root.librarySearch = "" }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [
                  { key: "all",        label: "Tout" },
                  { key: "downloaded", label: "Téléchargé" },
                  { key: "missing",    label: "Manquant" }
                ]
                delegate: Rectangle {
                  width: filterText.implicitWidth + Style.space(16)
                  height: Style.space(24)
                  radius: Style.cornerRadius
                  color: root.libraryFilter === modelData.key
                    ? Util.alpha(root.barForeground, 0.18)
                    : Util.alpha(root.barForeground, 0.06)

                  Text {
                    id: filterText
                    anchors.centerIn: parent
                    text: modelData.label
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: root.libraryFilter === modelData.key
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.libraryFilter = modelData.key
                  }
                }
              }

              Item { width: Style.space(8); height: 1 }

              Dropdown {
                readonly property var sortOptions: [
                  { key: "titleAsc",  label: "A→Z" },
                  { key: "titleDesc", label: "Z→A" },
                  { key: "addedDesc", label: "Récent→Ancien" },
                  { key: "addedAsc",  label: "Ancien→Récent" }
                ]
                anchors.verticalCenter: parent.verticalCenter
                showLabel: false
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                rowHeight: Style.space(24)
                options: sortOptions.map(function (o) { return o.label })
                value: {
                  var match = sortOptions.filter(function (o) { return o.key === root.librarySort })
                  return match.length ? match[0].label : sortOptions[0].label
                }
                onChanged: function (v) {
                  var match = sortOptions.filter(function (o) { return o.label === v })
                  if (match.length) root.librarySort = match[0].key
                }
              }
            }

            Text {
              visible: !root.libraryLoaded
              text: "Loading…"
              color: root.barForeground
              font.pixelSize: Style.font.body
            }

            Text {
              visible: root.libraryLoaded && root.filteredLibrary.length === 0
              text: "Nothing to show"
              color: Util.alpha(root.barForeground, 0.7)
              font.pixelSize: Style.font.body
            }

            Column {
              width: parent.width
              spacing: Style.space(2)
              visible: root.libraryLoaded

              Repeater {
                model: root.pagedLibrary
                delegate: Column {
                  readonly property int itemId: modelData.id
                  readonly property bool expanded: root.expandedLibraryId === itemId
                  width: content.width
                  spacing: 0

                  Rectangle {
                    width: parent.width
                    height: Style.space(52)
                    radius: Style.cornerRadius
                    color: expanded ? Util.alpha(root.barForeground, 0.1)
                      : (index % 2 === 0 ? Util.alpha(root.barForeground, 0.04) : "transparent")

                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.expandedLibraryId = expanded ? null : itemId
                    }

                    Row {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.margins: Style.space(6)
                      spacing: Style.space(8)

                      Image {
                        width: Style.space(32)
                        height: Style.space(44)
                        fillMode: Image.PreserveAspectCrop
                        source: modelData.poster || ""
                        asynchronous: true
                      }

                      Column {
                        width: parent.width - Style.space(32) - Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(1)

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: modelData.title + " (" + modelData.year + ")" + (modelData.monitored ? "" : " ⏸")
                          color: root.barForeground
                          font.pixelSize: Style.font.body
                        }

                        Row {
                          spacing: Style.space(8)

                          Text {
                            visible: modelData.audioLanguages !== undefined
                            text: "🔊 " + (modelData.audioLanguages && modelData.audioLanguages.length
                              ? modelData.audioLanguages.join(", ") : "—")
                            color: Util.alpha(root.barForeground, 0.7)
                            font.pixelSize: Style.font.bodySmall
                          }

                          Text {
                            visible: modelData.subtitles !== undefined && modelData.subtitles.length > 0
                            text: modelData.subtitles ? "💬 " + modelData.subtitles.join(",") : ""
                            color: Util.alpha(root.barForeground, 0.7)
                            font.pixelSize: Style.font.bodySmall
                          }

                          Text {
                            visible: modelData.episodeCount !== undefined
                            text: modelData.episodeCount !== undefined
                              ? modelData.episodeFileCount + "/" + modelData.episodeCount + " ép." : ""
                            color: Util.alpha(root.barForeground, 0.7)
                            font.pixelSize: Style.font.bodySmall
                          }
                        }
                      }
                    }
                  }

                  // Mini fiche : synopsis complet, dépliée au clic sur la ligne
                  Rectangle {
                    width: parent.width
                    visible: expanded
                    height: visible ? libDetailCol.implicitHeight + Style.space(16) : 0
                    radius: Style.cornerRadius
                    color: Util.alpha(root.barForeground, 0.05)
                    border.width: 1
                    border.color: Util.alpha(root.barForeground, 0.12)

                    Column {
                      id: libDetailCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(8)
                      spacing: Style.space(6)

                      Text {
                        width: libDetailCol.width
                        wrapMode: Text.WordWrap
                        text: modelData.overview && modelData.overview.length
                          ? modelData.overview : "Pas de synopsis disponible."
                        color: Util.alpha(root.barForeground, 0.85)
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        visible: modelData.imdbId !== undefined && modelData.imdbId !== ""
                        text: "IMDb ↗"
                        color: Color.accent
                        font.pixelSize: Style.font.bodySmall
                        font.underline: true
                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -Style.space(4)
                          onClicked: root.openImdb(modelData.imdbId)
                        }
                      }
                    }
                  }
                }
              }
            }

            // Pagination
            Row {
              width: parent.width
              visible: root.libraryLoaded && root.filteredLibrary.length > 0
              spacing: Style.space(10)

              PanelActionButton {
                iconText: "󰅁"
                tooltipText: "Previous page"
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.icon
                opacity: root.libraryPage > 0 ? 1.0 : 0.35
                onClicked: if (root.libraryPage > 0) root.libraryPage -= 1
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Page " + (root.libraryPage + 1) + " / " + root.libraryPageCount
                  + " (" + root.filteredLibrary.length + ")"
                color: Util.alpha(root.barForeground, 0.7)
                font.pixelSize: Style.font.bodySmall
              }

              PanelActionButton {
                iconText: "󰅂"
                tooltipText: "Next page"
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.icon
                opacity: root.libraryPage < root.libraryPageCount - 1 ? 1.0 : 0.35
                onClicked: if (root.libraryPage < root.libraryPageCount - 1) root.libraryPage += 1
              }
            }
          }

          // ---------------------------------------------------------------
          // Add tab
          // ---------------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.activeTab === "add"

            Row {
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width - addSearchBtn.width - Style.space(6)
                height: Style.space(32)

                TextField {
                  id: addSearchField
                  anchors.fill: parent
                  rightPadding: Style.space(26)
                  placeholderText: "Search a title to add…"
                  text: root.addSearchTerm
                  onTextChanged: root.addSearchTerm = text
                  Keys.onReturnPressed: root.runLookup()
                }

                Text {
                  visible: root.addSearchTerm.length > 0
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "✕"
                  color: Util.alpha(root.barForeground, 0.6)
                  font.pixelSize: Style.font.bodySmall
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    onClicked: {
                      addSearchField.text = ""
                      root.addSearchTerm = ""
                      root.lookupResults = []
                      root.addPage = 0
                      root.expandedId = null
                    }
                  }
                }
              }

              PanelActionButton {
                id: addSearchBtn
                iconText: "󰍉"
                tooltipText: "Search"
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.icon + 4
                onClicked: root.runLookup()
              }
            }

            Text {
              visible: root.lookupBusy
              text: "Searching…"
              color: root.barForeground
              font.pixelSize: Style.font.body
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.pagedResults
                delegate: Column {
                  readonly property int extId: root.extIdOf(modelData)
                  readonly property bool expanded: root.expandedId === extId
                  width: content.width
                  spacing: 0

                  Rectangle {
                    width: parent.width
                    height: Style.space(64)
                    radius: Style.cornerRadius
                    color: Util.alpha(root.barForeground, expanded ? 0.09 : 0.04)

                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        if (modelData.alreadyAdded || root.addedIds[extId] || root.addBusyIds[extId]) return
                        root.toggleExpand(modelData)
                      }
                    }

                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      spacing: Style.space(8)

                      Image {
                        width: Style.space(40)
                        height: Style.space(52)
                        fillMode: Image.PreserveAspectCrop
                        source: modelData.poster || ""
                        asynchronous: true
                      }

                      Column {
                        width: parent.width - Style.space(40) - addResultBtn.width - Style.space(20)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          text: modelData.title + " (" + modelData.year + ")"
                          color: root.barForeground
                          font.pixelSize: Style.font.body
                          font.bold: true
                        }
                        Text {
                          width: parent.width
                          elide: Text.ElideRight
                          wrapMode: Text.NoWrap
                          text: modelData.overview
                          color: Util.alpha(root.barForeground, 0.7)
                          font.pixelSize: Style.font.bodySmall
                        }
                      }

                      PanelActionButton {
                        id: addResultBtn
                        anchors.verticalCenter: parent.verticalCenter
                        scale: 1.0
                        iconText: modelData.alreadyAdded || root.addedIds[extId]
                          ? "󰄬" : (root.addBusyIds[extId] ? "…" : (expanded ? "󰅁" : "󰐕"))
                        tooltipText: modelData.alreadyAdded || root.addedIds[extId]
                          ? "Déjà dans la bibliothèque" : "Configurer et ajouter"
                        foreground: root.barForeground
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        fontSize: Style.font.icon + 4

                        Behavior on scale { NumberAnimation { duration: 100 } }

                        onClicked: {
                          if (modelData.alreadyAdded || root.addedIds[extId] || root.addBusyIds[extId]) return
                          addResultBtn.scale = 0.7
                          resetScale.restart()
                          root.toggleExpand(modelData)
                        }

                        Timer {
                          id: resetScale
                          interval: 80
                          onTriggered: addResultBtn.scale = 1.0
                        }
                      }
                    }
                  }

                  // Expanded add-config: quality profile (+ season folder /
                  // per-season picker for Sonarr) before actually adding.
                  Rectangle {
                    width: parent.width
                    visible: expanded
                    height: visible ? configCol.implicitHeight + Style.space(16) : 0
                    radius: Style.cornerRadius
                    color: Util.alpha(root.barForeground, 0.06)
                    border.width: 1
                    border.color: Util.alpha(root.barForeground, 0.15)

                    Column {
                      id: configCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(8)
                      spacing: Style.space(8)

                      Text {
                        width: configCol.width
                        wrapMode: Text.WordWrap
                        text: modelData.overview && modelData.overview.length
                          ? modelData.overview : "Pas de synopsis disponible."
                        color: Util.alpha(root.barForeground, 0.85)
                        font.pixelSize: Style.font.bodySmall
                      }

                      Text {
                        visible: modelData.imdbId !== undefined && modelData.imdbId !== ""
                        text: "IMDb ↗"
                        color: Color.accent
                        font.pixelSize: Style.font.bodySmall
                        font.underline: true
                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -Style.space(4)
                          onClicked: root.openImdb(modelData.imdbId)
                        }
                      }

                      Dropdown {
                        width: Style.spacing.dropdownWidth
                        label: "Profil qualité"
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        options: root.profiles.map(function (p) { return p.name })
                        value: {
                          var match = root.profiles.filter(function (p) { return p.id === root.expandedProfileId })
                          return match.length ? match[0].name : ""
                        }
                        onChanged: function (v) {
                          var match = root.profiles.filter(function (p) { return p.name === v })
                          if (match.length) root.expandedProfileId = match[0].id
                        }
                      }

                      Row {
                        visible: root.app === "sonarr"
                        spacing: Style.space(8)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: "Season folder"
                          color: root.barForeground
                          font.pixelSize: Style.font.bodySmall
                        }

                        ToggleSwitch {
                          anchors.verticalCenter: parent.verticalCenter
                          checked: root.expandedSeasonFolder
                          onToggled: root.expandedSeasonFolder = !root.expandedSeasonFolder
                        }
                      }

                      Flow {
                        width: configCol.width
                        visible: root.app === "sonarr" && modelData.seasons && modelData.seasons.length > 0
                        spacing: Style.space(4)

                        Repeater {
                          model: modelData.seasons || []
                          delegate: Rectangle {
                            readonly property bool on: root.expandedSeasons[modelData.seasonNumber] === true
                            width: seasonLabel.implicitWidth + Style.space(14)
                            height: Style.space(24)
                            radius: Style.cornerRadius
                            border.width: on ? 0 : 1
                            border.color: Util.alpha(root.barForeground, 0.25)
                            color: on ? Color.accent : "transparent"

                            Text {
                              id: seasonLabel
                              anchors.centerIn: parent
                              text: (on ? "✓ S" : "S") + modelData.seasonNumber
                              color: on ? Color.background : root.barForeground
                              font.pixelSize: Style.font.bodySmall
                              font.bold: on
                            }

                            MouseArea {
                              anchors.fill: parent
                              onClicked: root.toggleSeason(modelData.seasonNumber)
                            }
                          }
                        }
                      }

                      Rectangle {
                        width: confirmText.implicitWidth + Style.space(20)
                        height: Style.space(26)
                        radius: Style.cornerRadius
                        color: Util.alpha(root.barForeground, 0.18)

                        Text {
                          id: confirmText
                          anchors.centerIn: parent
                          text: "Add"
                          color: root.barForeground
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }

                        MouseArea {
                          anchors.fill: parent
                          onClicked: root.confirmAdd(modelData)
                        }
                      }
                    }
                  }
                }
              }
            }

            // Pagination
            Row {
              width: parent.width
              visible: root.lookupResults.length > 0
              spacing: Style.space(10)

              PanelActionButton {
                iconText: "󰅁"
                tooltipText: "Previous page"
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.icon
                opacity: root.addPage > 0 ? 1.0 : 0.35
                onClicked: if (root.addPage > 0) root.addPage -= 1
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Page " + (root.addPage + 1) + " / " + root.addPageCount
                  + " (" + root.lookupResults.length + ")"
                color: Util.alpha(root.barForeground, 0.7)
                font.pixelSize: Style.font.bodySmall
              }

              PanelActionButton {
                iconText: "󰅂"
                tooltipText: "Next page"
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.icon
                opacity: root.addPage < root.addPageCount - 1 ? 1.0 : 0.35
                onClicked: if (root.addPage < root.addPageCount - 1) root.addPage += 1
              }
            }
          }

          // ---------------------------------------------------------------
          // Queue tab
          // ---------------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.activeTab === "queue"

            Text {
              visible: !root.queueLoaded
              text: "Loading…"
              color: Util.alpha(root.barForeground, 0.7)
              font.pixelSize: Style.font.body
            }

            Text {
              visible: root.queueLoaded && root.queueItems.length === 0
              text: "Queue empty"
              color: Util.alpha(root.barForeground, 0.7)
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.queueItems
              delegate: Column {
                width: content.width
                spacing: Style.space(2)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    width: parent.width - Style.space(140)
                    elide: Text.ElideRight
                    text: modelData.title
                    color: root.barForeground
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: modelData.downloadClient + " · " + Math.round(modelData.progress) + "%"
                    color: Util.alpha(root.barForeground, 0.7)
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(4)
                  radius: 2
                  color: Util.alpha(root.barForeground, 0.15)

                  Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, modelData.progress)) / 100
                    height: parent.height
                    radius: 2
                    color: modelData.trackedStatus === "error" ? Color.urgent : root.barForeground
                  }
                }

                Text {
                  visible: modelData.errorMessage !== ""
                  text: modelData.errorMessage
                  color: Color.urgent
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }
      }
    }
  }
}
