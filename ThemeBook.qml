pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var service: null
  property var manifest: null
  property bool closingFromHost: false
  property string selectedSlug: ""
  property string promptKind: ""
  property string promptFolderId: ""
  property string promptText: ""
  property bool folderMenuOpen: false
  property string folderActionId: ""
  property string addFolderId: ""
  property string addFolderName: ""
  property string addQuery: ""
  property var addDraft: []
  property string assignSlug: ""
  property var assignDraft: []
  property var scheduleExpandIds: []
  property bool confirmRemove: false
  property string confirmFolderId: ""
  property string confirmFolderName: ""
  property string mainView: "browse"
  property string draggingFolderId: ""
  property string dropBeforeId: ""
  property bool dropAtEnd: false
  property real dropLineY: -1
  property bool cycleFolderPickOpen: false
  property bool pickerOpen: false
  property string pickerFolderId: ""
  property int pickerIndex: 0
  property string timeDraft: ""
  property string timeDraftId: ""
  property string themePickRuleId: ""
  property string themePickQuery: ""
  property var scheduleViewIds: []
  property int scheduleCursor: -1
  property int scheduleField: 0
  property bool scheduleEditTime: false
  property string stickyFolderId: ""
  property real stickyHeaderY: 0
  property var stickyHeaderRow: null

  readonly property var svc: service

  Connections {
    target: svc
    function onRequestPanelView(name) {
      if (name === "schedule" || name === "browse") root.mainView = name
    }
  }
  readonly property var themes: svc ? svc.themes : []
  readonly property var rows: svc ? svc.rows : []
  readonly property var config: svc ? svc.config : Model.defaultConfig()
  readonly property var selected: {
    if (!svc || !selectedSlug) return null
    return Model.themeBySlug(svc.themes, selectedSlug)
  }
  readonly property var addThemeChoices: {
    var draft = root.addDraft || []
    var inDraft = {}
    for (var d = 0; d < draft.length; d++) inDraft[draft[d]] = true
    var q = root.addQuery
    var listed = []
    var rest = []
    var themes = root.themes || []
    for (var i = 0; i < themes.length; i++) {
      var t = themes[i]
      if (!t || !t.slug) continue
      if (!Model.fuzzyMatch(q, t.name, t.slug)) continue
      var row = {
        slug: t.slug,
        name: t.name || t.slug,
        source: t.source === "user" ? "User" : "Stock",
        checked: !!inDraft[t.slug]
      }
      if (row.checked) listed.push(row)
      else rest.push(row)
    }
    return listed.concat(rest)
  }
  readonly property var assignFolderChoices: {
    var draft = root.assignDraft || []
    var want = {}
    for (var d = 0; d < draft.length; d++) want[draft[d]] = true
    var folders = root.config.folders || []
    var out = []
    for (var i = 0; i < folders.length; i++) {
      out.push({
        id: folders[i].id,
        name: folders[i].name || folders[i].id,
        checked: !!want[folders[i].id]
      })
    }
    return out
  }
  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color accent: Color.accent
  readonly property color muted: Util.alpha(Color.foreground, 0.62)
  readonly property string fontFamily: Style.font.family
  readonly property bool opened: window.visible

  function open(payloadJson) {
    closingFromHost = false
    var asPicker = false
    if (payloadJson) {
      try {
        var parsed = JSON.parse(String(payloadJson))
        if (parsed && parsed.picker) asPicker = true
      } catch (e) {}
    }
    if (!asPicker && String(payloadJson || "").indexOf("picker") >= 0) asPicker = true
    if (svc) svc.reloadCatalog()
    if (asPicker) {
      if (svc && typeof svc.openPicker === "function") svc.openPicker()
      return
    }
    window.visible = true
    if (svc && svc.currentSlug && !selectedSlug) selectedSlug = svc.currentSlug
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("io.github.calebhat.themebook")
    else window.visible = false
  }

  function selectOffset(delta) {
    var list = rows
    if (!list.length) return
    var idx = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].rowType === "theme" && list[i].slug === selectedSlug) { idx = i; break }
    }
    var j = idx
    while (true) {
      j += delta
      if (j < 0 || j >= list.length) return
      if (list[j].rowType === "theme") {
        selectedSlug = list[j].slug
        Qt.callLater(function() { root.revealSelected() })
        return
      }
    }
  }

  function selectedSection() {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].rowType === "theme" && rows[i].slug === selectedSlug) return rows[i].section
    }
    return ""
  }

  function applySelected() {
    if (root.folderMenuOpen || root.promptKind || root.confirmRemove) return
    if (root.addFolderId.length || root.assignSlug.length) return
    if (svc && svc.pendingManualSlug) return
    if (selected && svc) svc.requestManualApply(selected.slug)
  }

  function openAddModal(folderId) {
    if (!folderId || Model.isReservedSection(folderId)) return
    var folders = root.config.folders || []
    var name = "Folder"
    var slugs = []
    for (var i = 0; i < folders.length; i++) {
      if (folders[i].id === folderId) {
        name = folders[i].name || folderId
        slugs = (folders[i].themes || []).slice()
        break
      }
    }
    root.addFolderId = folderId
    root.addFolderName = name
    root.addDraft = slugs
    root.addQuery = ""
  }

  function closeAddModal() {
    root.addFolderId = ""
    root.addFolderName = ""
    root.addQuery = ""
    root.addDraft = []
    keyCatcher.forceActiveFocus()
  }

  function toggleAddDraft(slug) {
    if (!slug) return
    var next = (root.addDraft || []).slice()
    var i = next.indexOf(slug)
    if (i >= 0) next.splice(i, 1)
    else next.push(slug)
    root.addDraft = next
  }

  function saveAddModal() {
    if (svc && root.addFolderId) svc.setFolderThemes(root.addFolderId, root.addDraft)
    root.closeAddModal()
  }

  function openAssignModal(slug) {
    if (!slug) return
    root.folderMenuOpen = false
    root.assignSlug = slug
    root.assignDraft = Model.foldersForSlug(root.config, slug)
  }

  function closeAssignModal() {
    root.assignSlug = ""
    root.assignDraft = []
    keyCatcher.forceActiveFocus()
  }

  function toggleAssignDraft(folderId) {
    if (!folderId) return
    var next = (root.assignDraft || []).slice()
    var i = next.indexOf(folderId)
    if (i >= 0) next.splice(i, 1)
    else next.push(folderId)
    root.assignDraft = next
  }

  function saveAssignModal() {
    if (svc && root.assignSlug) svc.setThemeFolders(root.assignSlug, root.assignDraft)
    root.closeAssignModal()
  }

  function submitPrompt() {
    if (!svc || !root.promptKind) return
    var created = ""
    if (root.promptKind === "folder") created = svc.createFolder(root.promptText || "Folder")
    if (root.promptKind === "rename") svc.renameFolder(root.promptFolderId, root.promptText)
    root.promptKind = ""
    if (created && root.assignSlug) {
      var draft = (root.assignDraft || []).slice()
      draft.push(created)
      root.assignDraft = draft
      keyCatcher.forceActiveFocus()
    } else if (created) {
      root.openAddModal(created)
    } else {
      keyCatcher.forceActiveFocus()
    }
  }

  function cancelPrompt() {
    root.promptKind = ""
    keyCatcher.forceActiveFocus()
  }

  function folderShowsInPicker(id) {
    var p = root.config.picker || {}
    if (id === "favorites") return p.includeFavorites !== false
    if (id === "recents") return p.includeRecents === true
    if (id === "user") return p.includeUser === true
    if (id === "stock") return p.includeStock === true
    var folders = root.config.folders || []
    for (var i = 0; i < folders.length; i++)
      if (folders[i].id === id) return folders[i].inPicker === true
    return false
  }

  function commitTime(ruleId, text) {
    if (!svc) return
    var rule = null
    var rules = root.config.schedule.rules || []
    for (var i = 0; i < rules.length; i++) if (rules[i].id === ruleId) rule = rules[i]
    if (!rule) return
    var parsed = Model.parseClockTime(text, root.config.clock12, Model.hourIsPm(rule.time))
    if (!parsed) return
    svc.updateScheduleRule(ruleId, parsed, rule.theme, rule.enabled)
    root.timeDraftId = ""
  }

  function toggleRuleMeridiem(rule) {
    if (!svc || !rule) return
    svc.updateScheduleRule(rule.id, Model.applyMeridiem(rule.time, !Model.hourIsPm(rule.time)), rule.theme, rule.enabled)
  }

  function scheduleRuleById(id) {
    var rules = root.config.schedule.rules || []
    for (var i = 0; i < rules.length; i++) if (rules[i].id === id) return rules[i]
    return null
  }

  function loadScheduleOrder() {
    var rules = (root.config.schedule.rules || []).slice()
    rules.sort(function(a, b) { return Model.minutesOf(a.time) - Model.minutesOf(b.time) })
    var ids = []
    for (var i = 0; i < rules.length; i++) ids.push(rules[i].id)
    scheduleViewIds = ids
  }

  onMainViewChanged: {
    if (mainView === "schedule") {
      loadScheduleOrder()
      scheduleCursor = -1
      scheduleField = 0
      scheduleEditTime = false
      Qt.callLater(function() {
        keyCatcher.forceActiveFocus()
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      })
    }
  }

  function scheduleFieldNames() {
    if (config.schedule.mode === "sun") return ["theme"]
    if (root.config.clock12) return ["time", "ampm", "theme", "on", "remove"]
    return ["time", "theme", "on", "remove"]
  }

  function scheduleRowCount() {
    if (config.schedule.mode === "sun") return 2
    if (config.schedule.mode === "off") return Math.max(1, root.scheduleViewIds.length + 1)
    return root.scheduleViewIds.length + 1
  }

  function scheduleFieldName() {
    var names = scheduleFieldNames()
    var i = scheduleField
    if (i < 0) i = 0
    if (i >= names.length) i = names.length - 1
    return names[i] || "theme"
  }

  function isSchedFocus(row, field) {
    if (root.scheduleCursor < 0) return false
    return root.mainView === "schedule" && root.scheduleCursor === row && root.scheduleFieldName() === field
  }

  function scheduleMoveRow(delta) {
    var n = scheduleRowCount()
    if (n <= 0) return
    scheduleEditTime = false
    if (scheduleCursor < 0) scheduleCursor = delta > 0 ? 0 : n - 1
    else scheduleCursor = (scheduleCursor + delta + n) % n
    keyCatcher.forceActiveFocus()
  }

  function scheduleMoveField(delta) {
    var names = scheduleFieldNames()
    if (!names.length) return
    scheduleEditTime = false
    if (scheduleCursor < 0) scheduleCursor = 0
    scheduleField = (scheduleField + delta + names.length) % names.length
    keyCatcher.forceActiveFocus()
  }

  function scheduleActivate() {
    if (config.schedule.mode === "sun") {
      var which = scheduleCursor === 0 ? "day" : "night"
      root.themePickRuleId = "sun-" + which
      return
    }
    var addRow = root.scheduleViewIds.length
    if (scheduleCursor === addRow || config.schedule.mode === "off") {
      if (!svc) return
      var slug = selectedSlug || (root.themes[0] ? root.themes[0].slug : "")
      if (!slug) return
      var id = svc.addScheduleRule("07:00", slug)
      svc.setSchedule({ mode: "rules" })
      var ids = root.scheduleViewIds.slice()
      ids.push(id)
      root.scheduleViewIds = ids
      scheduleCursor = ids.length - 1
      scheduleField = 0
      return
    }
    var rid = root.scheduleViewIds[scheduleCursor]
    var rule = root.scheduleRuleById(rid)
    if (!rule) return
    var field = scheduleFieldName()
    if (field === "time") {
      scheduleEditTime = true
    } else if (field === "ampm") {
      root.toggleRuleMeridiem(rule)
    } else if (field === "theme") {
      root.themePickRuleId = rid
    } else if (field === "on") {
      svc.updateScheduleRule(rule.id, rule.time, rule.theme, !rule.enabled)
    } else if (field === "remove") {
      svc.removeScheduleRule(rid)
      var next = []
      for (var i = 0; i < root.scheduleViewIds.length; i++)
        if (root.scheduleViewIds[i] !== rid) next.push(root.scheduleViewIds[i])
      root.scheduleViewIds = next
      if (scheduleCursor >= next.length) scheduleCursor = Math.max(0, next.length)
    }
  }

  function scheduleModeId() {
    return (root.config.schedule && root.config.schedule.mode) || "off"
  }

  function scheduleModeLabel() {
    var m = root.scheduleModeId()
    if (m === "rules") return "Timed Themes"
    if (m === "sun") return "Sunrise / sunset"
    if (m === "themes") return "Theme cycle"
    if (m === "wallpapers" || m === "cycle") return "Wallpaper cycle"
    return "Off"
  }

  function isCycleMode() {
    var m = root.scheduleModeId()
    return m === "themes" || m === "wallpapers" || m === "cycle"
  }

  function isScheduleExpanded(id) {
    var ids = root.scheduleExpandIds || []
    for (var i = 0; i < ids.length; i++) if (ids[i] === id) return true
    return false
  }

  function toggleScheduleExpand(id) {
    var ids = (root.scheduleExpandIds || []).slice()
    var at = -1
    for (var i = 0; i < ids.length; i++) if (ids[i] === id) at = i
    if (at >= 0) ids.splice(at, 1)
    else ids.push(id)
    root.scheduleExpandIds = ids
  }

  function scheduleExpandableIds() {
    if (config.schedule.mode === "sun") return ["sun-day", "sun-night"]
    if (config.schedule.mode === "rules") return (root.scheduleViewIds || []).slice()
    return []
  }

  function scheduleAllExpanded() {
    var all = root.scheduleExpandableIds()
    if (!all.length) return false
    for (var i = 0; i < all.length; i++)
      if (!root.isScheduleExpanded(all[i])) return false
    return true
  }

  function setScheduleExpandAll(open) {
    root.scheduleExpandIds = open ? root.scheduleExpandableIds() : []
  }

  function cycleScheduleMode() {
    if (!svc) return
    var mode = config.schedule.mode
    if (mode === "off") svc.setSchedule({ mode: "rules" })
    else if (mode === "rules") svc.setSchedule({ mode: svc.sunwaitAvailable ? "sun" : "themes" })
    else if (mode === "sun") svc.setSchedule({ mode: "themes" })
    else if (mode === "themes") svc.setSchedule({ mode: "wallpapers" })
    else svc.setSchedule({ mode: "off" })
    scheduleCursor = -1
    scheduleField = 0
  }

  function pickerSections() {
    return Model.pickerSections(root.config, root.themes)
  }

  function filteredThemePick() {
    var q = root.themePickQuery
    var src = root.themes || []
    var out = []
    for (var i = 0; i < src.length; i++) {
      if (Model.fuzzyMatch(q, src[i].name, src[i].slug)) out.push(src[i])
    }
    return out
  }

  onThemePickRuleIdChanged: {
    if (root.themePickRuleId.length) root.themePickQuery = ""
  }

  function clearDropPreview() {
    root.dropBeforeId = ""
    root.dropAtEnd = false
    root.dropLineY = -1
  }

  function sectionHeaderLayout() {
    var headers = []
    var y = 0
    var sp = themeList ? themeList.spacing : 0
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var h = row.rowType === "header" ? Style.space(36) : Style.space(64)
      if (row.rowType === "header")
        headers.push({ id: row.id, top: y, bottom: y + h, row: row })
      y += h + sp
    }
    return headers
  }

  function updateStickyHeader() {
    var want = ""
    if (themeList && rows.length) {
      var cy = Math.max(0, themeList.contentY - (themeList.originY || 0))
      var headers = root.sectionHeaderLayout()
      for (var i = 0; i < headers.length; i++) {
        if (headers[i].top <= cy + 8) want = headers[i].id
        else break
      }
      if (!want && headers.length) want = headers[0].id
    }
    if (want !== root.stickyFolderId) root.stickyFolderId = want
  }

  function folderHeaderLayout() {
    var headers = []
    var y = 0
    var sp = themeList ? themeList.spacing : 0
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var h = row.rowType === "header" ? Style.space(36) : Style.space(64)
      if (row.rowType === "header" && Model.isReorderableSection(row.id))
        headers.push({ id: row.id, top: y, bottom: y + h })
      y += h + sp
    }
    return headers
  }

  function contentYFromPointer(item, mouseY) {
    if (!themeList || !item) return -1
    var p = item.mapToItem(themeList, 0, mouseY)
    return p.y + themeList.contentY
  }

  function updateDropTarget(item, mouseY) {
    root.dropBeforeId = ""
    root.dropAtEnd = false
    root.dropLineY = -1
    if (!themeList || !item || !root.draggingFolderId) return
    var y = root.contentYFromPointer(item, mouseY)
    var headers = root.folderHeaderLayout()
    if (!headers.length || y < 0) return

    var gaps = []
    for (var i = 0; i < headers.length; i++) {
      if (headers[i].id === root.draggingFolderId) continue
      gaps.push({ beforeId: headers[i].id, atEnd: false, y: headers[i].top })
    }
    var last = headers[headers.length - 1]
    if (last.id !== root.draggingFolderId)
      gaps.push({ beforeId: "", atEnd: true, y: last.bottom })
    else if (headers.length >= 2)
      gaps.push({ beforeId: "", atEnd: true, y: headers[headers.length - 2].bottom })
    if (!gaps.length) return

    var best = gaps[0]
    var bestDist = Math.abs(y - gaps[0].y)
    for (var g = 1; g < gaps.length; g++) {
      var dist = Math.abs(y - gaps[g].y)
      if (dist < bestDist) {
        bestDist = dist
        best = gaps[g]
      }
    }
    root.dropBeforeId = best.beforeId
    root.dropAtEnd = best.atEnd === true
    root.dropLineY = best.y
  }

  function dropFolder(fromId, item, mouseY) {
    if (!svc || !fromId || !item) return
    root.updateDropTarget(item, mouseY)
    var before = root.dropBeforeId
    var atEnd = root.dropAtEnd
    root.draggingFolderId = ""
    root.clearDropPreview()
    if (!before && !atEnd) return
    svc.moveSectionInsert(fromId, before, atEnd)
  }

  function colorKeys() {
    return ["accent", "background", "foreground", "red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
  }

  function colorFor(hex) {
    var s = String(hex || "")
    if (!/^#?[0-9a-fA-F]{3}([0-9a-fA-F]{3})?([0-9a-fA-F]{2})?$/.test(s)) return "transparent"
    return s
  }

  function revealSelected() {
    if (!themeList) return
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].rowType === "theme" && rows[i].slug === selectedSlug) {
        themeList.positionViewAtIndex(i, ListView.Visible)
        return
      }
    }
  }

  onSelectedSlugChanged: { /* user navigation calls revealSelected() */ }

  FloatingWindow {
    id: window
    title: "ThemeBook"
    color: root.bg
    implicitWidth: 1040
    implicitHeight: 760
    minimumSize: Qt.size(820, 560)
    visible: false

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("io.github.calebhat.themebook")
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (svc && svc.pendingManualSlug) {
          if (event.key === Qt.Key_Escape) { svc.cancelManualApply(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { svc.confirmManualApply(); event.accepted = true }
          return
        }
        if (root.confirmRemove) {
          if (event.key === Qt.Key_Escape) { root.confirmRemove = false; event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (svc && selectedSlug) svc.removeTheme(selectedSlug)
            root.confirmRemove = false
            event.accepted = true
          }
          return
        }
        if (root.themePickRuleId.length > 0) {
          if (event.key === Qt.Key_Escape) { root.themePickRuleId = ""; event.accepted = true }
          return
        }
        if (root.cycleFolderPickOpen) {
          if (event.key === Qt.Key_Escape) { root.cycleFolderPickOpen = false; event.accepted = true }
          return
        }
        if (root.mainView === "schedule") {
          if (root.scheduleEditTime) {
            if (event.key === Qt.Key_Escape) {
              root.scheduleEditTime = false
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
            return
          }
          if (event.key === Qt.Key_Escape) { root.mainView = "browse"; event.accepted = true }
          else if (event.key === Qt.Key_Tab) { root.cycleScheduleMode(); event.accepted = true }
          else if (event.key === Qt.Key_C) {
            if (svc) svc.setClock12(!root.config.clock12)
            event.accepted = true
          }
          else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) { root.scheduleMoveRow(1); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) { root.scheduleMoveRow(-1); event.accepted = true }
          else if (event.key === Qt.Key_Left) { root.scheduleMoveField(-1); event.accepted = true }
          else if (event.key === Qt.Key_Right) { root.scheduleMoveField(1); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.scheduleActivate(); event.accepted = true }
          else if (event.key === Qt.Key_A || event.key === Qt.Key_N) {
            root.scheduleCursor = root.scheduleViewIds.length
            root.scheduleField = 0
            root.scheduleActivate()
            event.accepted = true
          }
          return
        }
        if (root.promptKind) {
          if (event.key === Qt.Key_Escape) { root.cancelPrompt(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submitPrompt()
            event.accepted = true
          }
          return
        }
        if (root.addFolderId.length) {
          if (event.key === Qt.Key_Escape) { root.closeAddModal(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.saveAddModal(); event.accepted = true }
          return
        }
        if (root.assignSlug.length) {
          if (event.key === Qt.Key_Escape) { root.closeAssignModal(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.saveAssignModal(); event.accepted = true }
          return
        }
        if (root.folderActionId.length) {
          if (event.key === Qt.Key_Escape) { root.folderActionId = ""; event.accepted = true }
          return
        }
        if (root.folderMenuOpen) {
          if (event.key === Qt.Key_Escape) { root.folderMenuOpen = false; event.accepted = true }
          return
        }
        if (searchField.activeFocus && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Down && event.key !== Qt.Key_Up) {
          return
        }
        if (searchField.activeFocus && event.key === Qt.Key_Escape) {
          searchField.focus = false
          keyCatcher.forceActiveFocus()
          event.accepted = true
          return
        }
        var shift = event.modifiers & Qt.ShiftModifier
        if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true }
        else if (event.key === Qt.Key_Slash) { searchField.forceActiveFocus(); event.accepted = true }
        else if (shift && (event.key === Qt.Key_Up || event.key === Qt.Key_K)) {
          if (svc && selectedSlug) svc.reorder(root.selectedSection(), selectedSlug, -1)
          event.accepted = true
        }
        else if (shift && (event.key === Qt.Key_Down || event.key === Qt.Key_J)) {
          if (svc && selectedSlug) svc.reorder(root.selectedSection(), selectedSlug, 1)
          event.accepted = true
        }
        else if (shift && event.key === Qt.Key_Left) {
          if (svc) svc.moveFolder(root.selectedSection(), -1)
          event.accepted = true
        }
        else if (shift && event.key === Qt.Key_Right) {
          if (svc) svc.moveFolder(root.selectedSection(), 1)
          event.accepted = true
        }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) { root.selectOffset(1); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) { root.selectOffset(-1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.applySelected(); event.accepted = true }
        else if (event.key === Qt.Key_F) { if (svc && selectedSlug) svc.toggleFavorite(selectedSlug); event.accepted = true }
        else if (event.key === Qt.Key_H) { if (svc && selectedSlug) svc.toggleHidden(selectedSlug); event.accepted = true }
        else if (event.key === Qt.Key_E) { if (svc && root.selected) svc.openAether(root.selected); event.accepted = true }
        else if (event.key === Qt.Key_N) {
          root.promptKind = "folder"
          root.promptText = ""
          event.accepted = true
        }
        else if (event.key === Qt.Key_R) {
          if (svc) svc.randomFavorite()
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: "ThemeBook"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search themes"
            focus: false
            color: root.fg
            font.family: root.fontFamily
            background: Rectangle {
              color: Util.alpha(root.fg, 0.06)
              radius: Style.cornerRadius
              border.width: 1
              border.color: Util.alpha(root.fg, 0.12)
            }
            onTextChanged: if (svc) svc.query = text
            Keys.onEscapePressed: {
              focus = false
              keyCatcher.forceActiveFocus()
            }
          }

          Text {
            textFormat: Text.PlainText
            text: svc && svc.currentSlug ? ("Current: " + (Model.themeBySlug(root.themes, svc.currentSlug) || { name: svc.currentSlug }).name) : ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            width: schedBtn.implicitWidth + Style.space(16)
            height: Style.space(26)
            radius: Style.cornerRadius
            color: root.mainView === "schedule" || Model.isScheduleActive(root.config)
              ? Util.alpha(root.accent, 0.32) : Util.alpha(root.fg, 0.06)
            border.width: root.mainView === "schedule" || Model.isScheduleActive(root.config) ? 1 : 0
            border.color: root.accent
            Text {
              textFormat: Text.PlainText
              id: schedBtn
              anchors.centerIn: parent
              text: root.mainView === "schedule" ? "Themes" : "Schedule"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.mainView = root.mainView === "schedule" ? "browse" : "schedule"
            }
          }

        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          ColumnLayout {
            id: browsePane
            anchors.fill: parent
            visible: root.mainView === "browse"
            spacing: Style.space(10)

        Rectangle {
          visible: Model.isScheduleActive(root.config)
          Layout.fillWidth: true
          implicitHeight: schedBannerLab.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Util.alpha(root.accent, 0.16)
          border.width: 1
          border.color: root.accent
          Text {
            textFormat: Text.PlainText
            id: schedBannerLab
            anchors.fill: parent
            anchors.margins: Style.space(8)
            wrapMode: Text.WordWrap
            text: root.scheduleModeLabel() + " is running. Applying a theme by hand turns the schedule off."
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          spacing: Style.space(6)
          Repeater {
            model: [
              { id: "all", label: "All" },
              { id: "favorites", label: "Favorites" },
              { id: "user", label: "User" },
              { id: "stock", label: "Stock" },
              { id: "light", label: "Light" },
              { id: "dark", label: "Dark" },
              { id: "hidden", label: "Hidden" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: chipText.implicitWidth + Style.space(16)
              height: Style.space(26)
              radius: Style.cornerRadius
              color: (svc && svc.filter === modelData.id) ? Util.alpha(root.accent, 0.22) : Util.alpha(root.fg, 0.06)
              border.width: 1
              border.color: (svc && svc.filter === modelData.id) ? root.accent : Util.alpha(root.fg, 0.12)

              Text {
                textFormat: Text.PlainText
                id: chipText
                anchors.centerIn: parent
                text: modelData.label
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (svc) svc.filter = modelData.id
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(12)

          ColumnLayout {
            Layout.preferredWidth: 380
            Layout.maximumWidth: 380
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Style.space(6)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(6)
              Rectangle {
                Layout.preferredHeight: Style.space(26)
                Layout.preferredWidth: collapseAllLabel.implicitWidth + Style.space(12)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.06)
                Text {
                  textFormat: Text.PlainText
                  id: collapseAllLabel
                  anchors.centerIn: parent
                  text: "Collapse all"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: if (svc) svc.setCollapsedAll(true) }
              }
              Rectangle {
                Layout.preferredHeight: Style.space(26)
                Layout.preferredWidth: expandAllLabel.implicitWidth + Style.space(12)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.06)
                Text {
                  textFormat: Text.PlainText
                  id: expandAllLabel
                  anchors.centerIn: parent
                  text: "Expand all"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: if (svc) svc.setCollapsedAll(false) }
              }
              Rectangle {
                Layout.preferredHeight: Style.space(26)
                Layout.preferredWidth: newFolderLabel.implicitWidth + Style.space(12)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.06)
                Text {
                  textFormat: Text.PlainText
                  id: newFolderLabel
                  anchors.centerIn: parent
                  text: "New folder"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.promptKind = "folder"
                    root.promptText = ""
                  }
                }
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                Layout.preferredHeight: Style.space(26)
                Layout.preferredWidth: themeMenuInner.width + Style.space(14)
                radius: Style.cornerRadius
                color: (root.config.picker && root.config.picker.replaceDefault) ? Util.alpha(root.accent, 0.32) : Util.alpha(root.fg, 0.1)
                border.width: 1
                border.color: (root.config.picker && root.config.picker.replaceDefault) ? root.accent : Util.alpha(root.fg, 0.28)
                Row {
                  id: themeMenuInner
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Rectangle {
                    width: Style.space(12)
                    height: Style.space(12)
                    radius: Style.cornerRadius
                    color: (root.config.picker && root.config.picker.replaceDefault) ? root.accent : root.bg
                    border.width: 1
                    border.color: root.fg
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      visible: !!(root.config.picker && root.config.picker.replaceDefault)
                      text: "✓"
                      color: root.bg
                      font.pixelSize: 9
                      font.bold: true
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "Theme menu"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (svc) svc.setPickerAsked(!(root.config.picker && root.config.picker.replaceDefault))
                }
              }
            }

            Rectangle {
              id: stickyBar
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(36)
              Layout.minimumHeight: Style.space(36)
              radius: Style.cornerRadius
              color: Util.alpha(root.fg, 0.08)
              border.width: 1
              border.color: Util.alpha(root.fg, 0.16)
              Text {
                textFormat: Text.PlainText
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                text: {
                  var id = root.stickyFolderId
                  for (var i = 0; i < root.rows.length; i++) {
                    var row = root.rows[i]
                    if (row.rowType === "header" && row.id === id)
                      return (row.collapsed ? "▸ " : "▾ ") + (row.title || "") + " (" + String(row.themeCount != null ? row.themeCount : 0) + ")"
                  }
                  return ""
                }
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (svc && root.stickyFolderId) svc.toggleCollapsed(root.stickyFolderId)
                }
              }
            }

          ListView {
            id: themeList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            onContentYChanged: root.updateStickyHeader()
            onHeightChanged: root.updateStickyHeader()
            onCountChanged: root.updateStickyHeader()
            Component.onCompleted: root.updateStickyHeader()
            model: root.rows
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 4
                var maxY = Math.max(0, themeList.contentHeight - themeList.height)
                themeList.contentY = Math.max(0, Math.min(maxY, themeList.contentY - dy * 2))
                root.updateStickyHeader()
                event.accepted = true
              }
            }

            Rectangle {
              parent: themeList.contentItem
              visible: root.draggingFolderId.length > 0 && root.dropLineY >= 0
              x: 0
              y: root.dropLineY - 1
              width: themeList.width
              height: 2
              color: root.accent
              z: 100
            }

            delegate: Item {
              id: folderDelegate
              required property var modelData
              readonly property string folderId: String(modelData.id || "")
              readonly property string folderTitle: String(modelData.title || modelData.id || "")
              width: themeList.width
              height: modelData.rowType === "header" ? Style.space(36) : Style.space(64)

              Item {
                id: headerRow
                visible: modelData.rowType === "header"
                anchors.fill: parent
                z: root.draggingFolderId === modelData.id ? 20 : 0

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: root.draggingFolderId === modelData.id ? Util.alpha(root.fg, 0.06) : "transparent"
                }

                RowLayout {
                  anchors.fill: parent
                  spacing: Style.space(4)
                  Rectangle {
                    visible: modelData.draggable === true
                    Layout.preferredWidth: Style.space(28)
                    Layout.minimumWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                    Layout.alignment: Qt.AlignVCenter
                    radius: Style.cornerRadius
                    color: Util.alpha(root.fg, 0.08)
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "≡"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      anchors.fill: parent
                      preventStealing: true
                      hoverEnabled: true
                      cursorShape: Qt.SizeVerCursor
                      onPressed: {
                        root.draggingFolderId = modelData.id
                        root.clearDropPreview()
                      }
                      onPositionChanged: function(mouse) {
                        if (!pressed) return
                        root.updateDropTarget(this, mouse.y)
                      }
                      onReleased: function(mouse) {
                        root.dropFolder(modelData.id, this, mouse.y)
                      }
                      onCanceled: {
                        root.draggingFolderId = ""
                        root.clearDropPreview()
                      }
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (modelData.collapsed ? "▸ " : "▾ ") + (modelData.title || "") + " (" + String(modelData.themeCount != null ? modelData.themeCount : 0) + ")"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (svc) svc.toggleCollapsed(modelData.id)
                    }
                  }
                  Rectangle {
                    visible: !Model.isReservedSection(modelData.id)
                    Layout.preferredHeight: Style.space(22)
                    Layout.preferredWidth: addThemesLab.implicitWidth + Style.space(14)
                    Layout.alignment: Qt.AlignVCenter
                    radius: Style.cornerRadius
                    color: Util.alpha(root.fg, 0.08)
                    border.width: 1
                    border.color: Util.alpha(root.fg, 0.14)
                    Text {
                      textFormat: Text.PlainText
                      id: addThemesLab
                      anchors.centerIn: parent
                      text: "Add themes"
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openAddModal(modelData.id)
                    }
                  }
                  Rectangle {
                    id: folderActBtn
                    visible: !Model.isReservedSection(modelData.id)
                    Layout.preferredWidth: Style.space(26)
                    Layout.preferredHeight: Style.space(22)
                    Layout.alignment: Qt.AlignVCenter
                    radius: Style.cornerRadius
                    color: root.folderActionId === modelData.id ? Util.alpha(root.accent, 0.22) : Util.alpha(root.fg, 0.08)
                    border.width: 1
                    border.color: root.folderActionId === modelData.id ? root.accent : Util.alpha(root.fg, 0.14)
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "⋯"
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.folderActionId === modelData.id) {
                          root.folderActionId = ""
                          folderActPopup.close()
                        } else {
                          root.folderActionId = modelData.id
                          folderActPopup.open()
                        }
                      }
                    }
                    Popup {
                      id: folderActPopup
                      x: parent.width - width
                      y: parent.height + Style.space(4)
                      padding: Style.space(6)
                      modal: false
                      dim: false
                      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                      onClosed: if (root.folderActionId === folderDelegate.folderId) root.folderActionId = ""
                      background: Rectangle {
                        color: root.bg
                        radius: Style.cornerRadius
                        border.width: 1
                        border.color: Util.alpha(root.fg, 0.18)
                      }
                      contentItem: Column {
                        spacing: Style.space(2)
                        Repeater {
                          model: [
                            { id: "rename", label: "Rename" },
                            { id: "delete", label: "Delete" }
                          ]
                          delegate: Rectangle {
                            required property var modelData
                            readonly property string actId: modelData.id
                            readonly property string actLabel: modelData.label
                            width: Math.max(Style.space(96), actLab.implicitWidth + Style.space(20))
                            height: Style.space(28)
                            radius: Style.cornerRadius
                            color: actHover.containsMouse ? Util.alpha(root.accent, 0.16) : "transparent"
                            Text {
                              textFormat: Text.PlainText
                              id: actLab
                              anchors.verticalCenter: parent.verticalCenter
                              anchors.left: parent.left
                              anchors.leftMargin: Style.space(8)
                              text: actLabel
                              color: root.fg
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                            MouseArea {
                              id: actHover
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                folderActPopup.close()
                                root.folderActionId = ""
                                if (actId === "rename") {
                                  root.promptKind = "rename"
                                  root.promptFolderId = folderDelegate.folderId
                                  root.promptText = folderDelegate.folderTitle
                                  promptField.text = root.promptText
                                } else if (actId === "delete") {
                                  root.confirmFolderId = folderDelegate.folderId
                                  root.confirmFolderName = folderDelegate.folderTitle
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                    Connections {
                      target: root
                      function onFolderActionIdChanged() {
                        if (root.folderActionId !== folderDelegate.folderId && folderActPopup.opened)
                          folderActPopup.close()
                      }
                    }
                  }
                  Rectangle {
                    visible: modelData.id === "favorites" || modelData.id === "recents" || modelData.id === "user" || modelData.id === "stock" || !Model.isReservedSection(modelData.id)
                    Layout.preferredHeight: Style.space(22)
                    Layout.preferredWidth: Style.space(78)
                    radius: Style.cornerRadius
                    color: root.folderShowsInPicker(modelData.id) ? Util.alpha(root.accent, 0.32) : Util.alpha(root.fg, 0.1)
                    border.width: 1
                    border.color: root.folderShowsInPicker(modelData.id) ? root.accent : Util.alpha(root.fg, 0.28)
                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(4)
                      Rectangle {
                        width: Style.space(12)
                        height: Style.space(12)
                        radius: Style.cornerRadius
                        color: root.folderShowsInPicker(modelData.id) ? root.accent : root.bg
                        border.width: 1
                        border.color: root.fg
                        Text {
                          textFormat: Text.PlainText
                          anchors.centerIn: parent
                          visible: root.folderShowsInPicker(modelData.id)
                          text: "✓"
                          color: root.bg
                          font.pixelSize: 9
                          font.bold: true
                        }
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: "Picker"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (svc) svc.setFolderInPicker(modelData.id, !root.folderShowsInPicker(modelData.id))
                    }
                  }
                }
              }

              Rectangle {
                visible: modelData.rowType === "theme"
                anchors.fill: parent
                radius: Style.cornerRadius
                color: modelData.slug === root.selectedSlug ? Util.alpha(root.accent, 0.16) : "transparent"
                border.width: modelData.current === true ? 1 : 0
                border.color: root.accent

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(72)
                    height: parent.height
                    radius: Style.cornerRadius
                    clip: true
                    color: Util.alpha(root.fg, 0.06)
                    Image {
                      id: thumb
                      anchors.fill: parent
                      source: modelData.preview ? Util.fileUrl(modelData.preview) : ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: true
                      sourceSize.width: 160
                      sourceSize.height: 100
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: !modelData.preview || thumb.status === Image.Error
                      anchors.centerIn: parent
                      text: "—"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (Model.isReservedSection(modelData.section) ? Style.space(118) : Style.space(148))
                    spacing: 2
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: (modelData.name || modelData.slug || "")
                      elide: Text.ElideRight
                      color: modelData.current === true ? root.accent : root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: modelData.current === true
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: (modelData.source === "user" ? "User" : "Stock") + (modelData.mode ? " · " + modelData.mode : "")
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedSlug = modelData.slug
                  onDoubleClicked: if (svc) svc.requestManualApply(modelData.slug)
                }

                Row {
                  id: themeRowActs
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(2)
                  z: 3
                  Rectangle {
                    id: removeFromFolderHit
                    visible: !Model.isReservedSection(modelData.section)
                    width: Style.space(28)
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: removeFromFolderMouse.containsMouse ? Util.alpha(root.accent, 0.28) : "transparent"
                    Accessible.name: "Remove from folder"
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: "✕"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    MouseArea {
                      id: removeFromFolderMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (svc) svc.removeFromFolder(modelData.slug, modelData.section)
                    }
                  }
                  Rectangle {
                    id: starHit
                    width: Style.space(28)
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: starMouse.containsMouse ? Util.alpha(root.accent, 0.28) : "transparent"
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: root.config.favorites.indexOf(modelData.slug) >= 0 ? "★" : "☆"
                      color: root.config.favorites.indexOf(modelData.slug) >= 0 ? root.accent : root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    MouseArea {
                      id: starMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (svc) svc.toggleFavorite(modelData.slug)
                    }
                  }
                }
              }
            }
          }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.cornerRadius
            color: Util.alpha(root.fg, 0.04)
            border.width: 1
            border.color: Util.alpha(root.fg, 0.1)

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 330
                radius: Style.cornerRadius
                clip: true
                color: Util.alpha(root.fg, 0.06)
                Image {
                  id: hero
                  anchors.fill: parent
                  source: {
                    var t = root.selected
                    if (!t) return ""
                    var path = ""
                    if (svc && t.slug === svc.currentSlug && t.currentBackground)
                      path = t.currentBackground
                    else
                      path = t.preview || t.currentBackground || ""
                    return path ? Util.fileUrl(path) : ""
                  }
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  sourceSize.width: 960
                  sourceSize.height: 540
                }
                Text {
                  textFormat: Text.PlainText
                  visible: {
                    var t = root.selected
                    if (!t) return true
                    var path = (svc && t.slug === svc.currentSlug && t.currentBackground) ? t.currentBackground : (t.preview || t.currentBackground || "")
                    return !path || hero.status === Image.Error
                  }
                  anchors.centerIn: parent
                  text: !root.selected ? "Select a theme" : "No preview"
                  color: root.muted
                  font.family: root.fontFamily
                }
              }

              Text {
                textFormat: Text.PlainText
                text: root.selected ? root.selected.name : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                visible: !!root.selected
                text: {
                  if (!root.selected) return ""
                  var bits = [root.selected.source === "user" ? "User" : "Stock"]
                  if (root.selected.mode) bits.push(root.selected.mode)
                  if (root.selected.git) bits.push("git")
                  if (root.selected.current) bits.push("current")
                  return bits.join(" · ")
                }
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Row {
                spacing: Style.space(5)
                Repeater {
                  model: root.selected ? root.colorKeys() : []
                  delegate: Rectangle {
                    required property var modelData
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Style.cornerRadius
                    color: {
                      var hex = root.selected && root.selected.colors ? root.selected.colors[modelData] : ""
                      return root.colorFor(hex)
                    }
                    border.width: 1
                    border.color: Util.alpha(root.fg, 0.25)
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                visible: root.selected && root.selected.backgrounds && root.selected.backgrounds.length
                text: "Backgrounds — pin one as default for apply and picker preview"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                orientation: ListView.Horizontal
                clip: true
                spacing: Style.space(6)
                visible: root.selected && root.selected.backgrounds && root.selected.backgrounds.length
                model: root.selected && root.selected.backgrounds ? root.selected.backgrounds : []
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool isDefault: !!(root.selected && Model.defaultWallpaper(root.config, root.selected) === modelData)
                  width: 144
                  height: 84
                  radius: Style.cornerRadius
                  clip: true
                  color: Util.alpha(root.fg, 0.06)
                  border.width: isDefault || (root.selected && root.selected.currentBackground === modelData) ? 2 : 0
                  border.color: isDefault ? root.accent : Util.alpha(root.fg, 0.35)
                  Image {
                    anchors.fill: parent
                    source: Util.fileUrl(modelData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 288
                    sourceSize.height: 168
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (svc) svc.applyBackgroundAndTheme(modelData)
                  }
                  Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 3
                    width: Style.space(18)
                    height: Style.space(18)
                    radius: Style.cornerRadius
                    color: Util.alpha(root.bg, 0.72)
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: isDefault ? "★" : "☆"
                      color: isDefault ? root.accent : root.muted
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (svc && root.selected) svc.setDefaultWallpaper(root.selected.slug, modelData)
                    }
                  }
                }
              }

              Flow {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Repeater {
                  model: [
                    { id: "folder", label: "Move to folder" },
                    { id: "fav", label: "Favorite" },
                    { id: "aether", label: "Edit in Aether" },
                    { id: "hide", label: "Hide" },
                    { id: "show", label: "Show" },
                    { id: "random", label: "Random favorite" },
                    { id: "update", label: "Update git themes" },
                    { id: "remove", label: "Remove" },
                    { id: "apply", label: "Apply theme" }
                  ]
                  delegate: Rectangle {
                    required property var modelData
                    visible: {
                      if (!root.selected && modelData.id !== "random") return false
                      if (modelData.id === "aether") return !!(svc && svc.aetherAvailable)
                      if (modelData.id === "hide") return root.config.hidden.indexOf(root.selectedSlug) < 0
                      if (modelData.id === "show") return root.config.hidden.indexOf(root.selectedSlug) >= 0
                      if (modelData.id === "update") return !!(root.selected && root.selected.git)
                      if (modelData.id === "remove") return !!(root.selected && root.selected.source === "user" && root.selected.slug !== (svc ? svc.currentSlug : ""))
                      if (modelData.id === "random") return !!(root.config.favorites && root.config.favorites.length)
                      return true
                    }
                    width: btnLabel.implicitWidth + Style.space(16)
                    height: Style.space(30)
                    radius: Style.cornerRadius
                    color: modelData.id === "apply" ? Util.alpha(root.accent, 0.28) : Util.alpha(root.fg, 0.08)
                    Text {
                      textFormat: Text.PlainText
                      id: btnLabel
                      anchors.centerIn: parent
                      text: {
                        if (modelData.id === "fav" && root.config.favorites.indexOf(root.selectedSlug) >= 0)
                          return "Unfavorite"
                        return modelData.label
                      }
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (!svc) return
                        if (modelData.id === "folder" && selectedSlug) root.openAssignModal(selectedSlug)
                        else if (modelData.id === "fav" && selectedSlug) svc.toggleFavorite(selectedSlug)
                        else if (modelData.id === "aether" && root.selected) svc.openAether(root.selected)
                        else if (modelData.id === "hide" && selectedSlug) svc.toggleHidden(selectedSlug)
                        else if (modelData.id === "show" && selectedSlug) svc.toggleHidden(selectedSlug)
                        else if (modelData.id === "random") svc.randomFavorite()
                        else if (modelData.id === "update") svc.updateGitThemes()
                        else if (modelData.id === "remove") root.confirmRemove = true
                        else if (modelData.id === "apply") root.applySelected()
                      }
                    }
                  }
                }
              }

              Item { Layout.fillHeight: true }
            }
          }
        }
          }

          ColumnLayout {
            id: schedulePane
            anchors.fill: parent
            visible: root.mainView === "schedule"
            spacing: Style.space(12)

          RowLayout {
            Layout.fillWidth: true
            Text {
              textFormat: Text.PlainText
              text: "Schedule"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Item { Layout.fillWidth: true }
            Rectangle {
              visible: !root.isCycleMode()
              width: clockLab.implicitWidth + Style.space(16)
              height: Style.space(26)
              radius: Style.cornerRadius
              color: Util.alpha(root.fg, 0.08)
              Text {
                textFormat: Text.PlainText
                id: clockLab
                anchors.centerIn: parent
                text: root.config.clock12 ? "12-hour" : "24-hour"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (svc) svc.setClock12(!root.config.clock12)
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            visible: !!(svc && svc.otherSchedulerEnabled)
            text: "Another theme scheduler is enabled — ThemeBook stays off."
            color: root.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Repeater {
              model: [
                { id: "off", label: "Off" },
                { id: "rules", label: "Timed Themes" },
                { id: "sun", label: "Sunrise / sunset" },
                { id: "themes", label: "Theme cycle" },
                { id: "wallpapers", label: "Wallpaper cycle" }
              ]
              delegate: Rectangle {
                required property var modelData
                readonly property bool selected: root.scheduleModeId() === modelData.id
                visible: modelData.id !== "sun" || (svc && svc.sunwaitAvailable)
                width: modeRow.implicitWidth + Style.space(16)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: selected ? Util.alpha(root.accent, 0.32) : Util.alpha(root.fg, 0.08)
                border.width: 1
                border.color: selected ? root.accent : Util.alpha(root.fg, 0.14)
                Row {
                  id: modeRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Rectangle {
                    width: Style.space(12)
                    height: Style.space(12)
                    radius: Style.cornerRadius
                    color: selected ? root.accent : root.bg
                    border.width: 1
                    border.color: selected ? root.accent : root.fg
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      visible: selected
                      text: "✓"
                      color: root.bg
                      font.pixelSize: 9
                      font.bold: true
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: selected
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (svc) svc.setSchedule({ mode: modelData.id })
                }
              }
            }
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.scheduleModeId() === "off"
              ? "No schedule is running. Choose one type — only one can be on."
              : (root.scheduleModeLabel() + " is on. Choosing another type turns this one off.")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
              id: cyclePane
              visible: root.isCycleMode()
              width: parent.width
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.scheduleModeId() === "themes"
                  ? "Walks through themes in a folder. Optionally also rotate wallpapers while a theme is current."
                  : "Rotates wallpapers of the current theme only. Needs at least two images. Does not change the theme."
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                visible: root.scheduleModeId() === "themes"
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: 72
                  text: "Folder"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Rectangle {
                  width: Math.max(180, cyclePane.width - 88)
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: Util.alpha(root.fg, 0.08)
                  border.width: 1
                  border.color: Util.alpha(root.fg, 0.14)
                  Text {
                    textFormat: Text.PlainText
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    text: {
                      var id = root.config.themeCycle ? root.config.themeCycle.folderId : ""
                      if (!id) return "Choose folder…"
                      return Model.sectionDisplayName(root.config, id) || "Choose folder…"
                    }
                    color: root.fg
                    font.family: root.fontFamily
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycleFolderPickOpen = true
                  }
                }
              }

              Row {
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: 72
                  text: root.scheduleModeId() === "themes" ? "Themes" : "Every"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  id: cycleMinutesField
                  width: 72
                  color: root.fg
                  font.family: root.fontFamily
                  text: root.scheduleModeId() === "themes"
                    ? String((root.config.themeCycle && root.config.themeCycle.minutes) || 30)
                    : String((root.config.wallpaperCycle && root.config.wallpaperCycle.minutes) || 5)
                  inputMethodHints: Qt.ImhDigitsOnly
                  onEditingFinished: {
                    if (!svc) return
                    var n = parseInt(text, 10)
                    if (isNaN(n)) n = root.scheduleModeId() === "themes" ? 30 : 5
                    if (root.scheduleModeId() === "themes") svc.setThemeCycle({ minutes: n, resetStamp: true })
                    else svc.setWallpaperCycle({ minutes: n, resetStamp: true })
                  }
                  background: Rectangle {
                    color: Util.alpha(root.fg, 0.08)
                    radius: Style.cornerRadius
                    border.width: 1
                    border.color: Util.alpha(root.fg, 0.14)
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "minutes"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Rectangle {
                visible: root.scheduleModeId() === "themes"
                width: nestedWpLab.implicitWidth + Style.space(28)
                height: Style.space(28)
                radius: Style.cornerRadius
                color: (root.config.themeCycle && root.config.themeCycle.wallpaperEnabled) ? Util.alpha(root.accent, 0.32) : Util.alpha(root.fg, 0.08)
                border.width: 1
                border.color: (root.config.themeCycle && root.config.themeCycle.wallpaperEnabled) ? root.accent : Util.alpha(root.fg, 0.14)
                Row {
                  anchors.centerIn: parent
                  spacing: Style.space(6)
                  Rectangle {
                    width: Style.space(12)
                    height: Style.space(12)
                    radius: Style.cornerRadius
                    color: (root.config.themeCycle && root.config.themeCycle.wallpaperEnabled) ? root.accent : root.bg
                    border.width: 1
                    border.color: root.fg
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      visible: !!(root.config.themeCycle && root.config.themeCycle.wallpaperEnabled)
                      text: "✓"
                      color: root.bg
                      font.pixelSize: 9
                      font.bold: true
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    id: nestedWpLab
                    text: "Also cycle wallpapers"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (svc) svc.setThemeCycle({
                    wallpaperEnabled: !(root.config.themeCycle && root.config.themeCycle.wallpaperEnabled)
                  })
                }
              }

              Row {
                visible: root.scheduleModeId() === "themes"
                spacing: Style.space(8)
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: 72
                  text: "Wallpapers"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  width: 72
                  color: root.fg
                  font.family: root.fontFamily
                  text: String((root.config.themeCycle && root.config.themeCycle.wallpaperMinutes) || 5)
                  inputMethodHints: Qt.ImhDigitsOnly
                  onEditingFinished: {
                    if (!svc) return
                    var n = parseInt(text, 10)
                    if (isNaN(n)) n = 5
                    svc.setThemeCycle({ wallpaperMinutes: n, resetStamp: true })
                  }
                  background: Rectangle {
                    color: Util.alpha(root.fg, 0.08)
                    radius: Style.cornerRadius
                    border.width: 1
                    border.color: Util.alpha(root.fg, 0.14)
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "minutes"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            ColumnLayout {
              id: timedPane
              visible: !root.isCycleMode()
              anchors.fill: parent
              spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: config.schedule.mode === "sun"
              ? "Sunrise and sunset use your weather location. Pick a theme for each. Expand a row to cycle wallpapers while that period is active."
              : "Type a time and pick a theme. ThemeBook applies the latest Timed Theme whose time has already passed. Expand a row to cycle wallpapers for that theme."
            color: root.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          RowLayout {
            visible: config.schedule.mode === "rules" || config.schedule.mode === "sun"
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Rectangle {
              Layout.preferredWidth: expandAllLab.implicitWidth + Style.space(16)
              Layout.preferredHeight: Style.space(26)
              radius: Style.cornerRadius
              color: Util.alpha(root.fg, 0.08)
              Text {
                textFormat: Text.PlainText
                id: expandAllLab
                anchors.centerIn: parent
                text: root.scheduleAllExpanded() ? "Collapse all" : "Expand all"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setScheduleExpandAll(!root.scheduleAllExpanded())
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(8)
            Layout.rightMargin: Style.space(8)
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              Layout.preferredWidth: 96
              text: config.schedule.mode === "sun" ? "When" : "Time"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              visible: !!root.config.clock12
              Layout.preferredWidth: 52
              text: config.schedule.mode === "sun" ? "" : "AM/PM"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: "Theme"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              Layout.preferredWidth: 64
              horizontalAlignment: Text.AlignHCenter
              text: config.schedule.mode === "sun" ? "" : "On"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              textFormat: Text.PlainText
              Layout.preferredWidth: 80
              horizontalAlignment: Text.AlignHCenter
              text: ""
              font.pixelSize: 1
            }
            Item { Layout.preferredWidth: Style.space(28) }
          }

          Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: schedCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: schedCol
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: config.schedule.mode === "sun" || root.isCycleMode() ? [] : root.scheduleViewIds
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  readonly property var rule: root.scheduleRuleById(modelData)
                  readonly property bool expanded: root.isScheduleExpanded(String(modelData))
                  visible: !!rule
                  width: schedCol.width
                  height: expanded ? Style.space(92) : Style.space(44)
                  radius: Style.cornerRadius
                  color: Util.alpha(root.fg, 0.06)
                  border.width: rule && rule.enabled ? 1 : 0
                  border.color: root.accent
                  Column {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: 0
                  RowLayout {
                    width: parent.width
                    height: Style.space(44)
                    spacing: Style.space(8)
                    TextField {
                      Layout.preferredWidth: 96
                      Layout.minimumWidth: 96
                      color: root.fg
                      font.family: root.fontFamily
                      activeFocusOnTab: false
                      selectByMouse: true
                      text: root.timeDraftId === modelData ? root.timeDraft : Model.formatHourMinute(rule ? rule.time : "", root.config.clock12)
                      placeholderText: root.config.clock12 ? "7:00" : "19:00"
                      onActiveFocusChanged: {
                        if (activeFocus && rule) {
                          root.timeDraftId = modelData
                          root.timeDraft = Model.formatHourMinute(rule.time, root.config.clock12)
                          if (root.scheduleEditTime)
                            Qt.callLater(function() { selectAll() })
                          else
                            Qt.callLater(function() { deselect(); cursorPosition = length })
                        } else if (!activeFocus && root.scheduleEditTime && root.scheduleCursor === index) {
                          root.scheduleEditTime = false
                          keyCatcher.forceActiveFocus()
                        }
                      }
                      onTextChanged: if (root.timeDraftId === modelData) root.timeDraft = text
                      onAccepted: root.commitTime(modelData, text)
                      onEditingFinished: root.commitTime(modelData, text)
                      background: Rectangle {
                        color: Util.alpha(root.fg, 0.08)
                        radius: Style.cornerRadius
                        border.width: 1
                        border.color: (activeFocus && root.scheduleEditTime) || root.isSchedFocus(index, "time")
                          ? root.accent
                          : Util.alpha(root.fg, 0.14)
                      }
                    }
                    Rectangle {
                      visible: !!root.config.clock12
                      Layout.preferredWidth: 52
                      Layout.minimumWidth: 52
                      Layout.preferredHeight: Style.space(32)
                      radius: Style.cornerRadius
                      color: Util.alpha(root.fg, 0.08)
                      border.width: 1
                      border.color: root.isSchedFocus(index, "ampm") ? root.accent : Util.alpha(root.fg, 0.14)
                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: rule && Model.hourIsPm(rule.time) ? "PM" : "AM"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (rule) root.toggleRuleMeridiem(rule)
                      }
                    }
                    Rectangle {
                      Layout.fillWidth: true
                      Layout.preferredHeight: Style.space(32)
                      radius: Style.cornerRadius
                      color: Util.alpha(root.fg, 0.08)
                      border.width: 1
                      border.color: root.isSchedFocus(index, "theme") ? root.accent : Util.alpha(root.fg, 0.14)
                      Text {
                        textFormat: Text.PlainText
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(8)
                        anchors.rightMargin: Style.space(8)
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        text: (Model.themeBySlug(root.themes, rule ? rule.theme : "") || { name: "Choose theme…" }).name
                        color: root.fg
                        font.family: root.fontFamily
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.themePickRuleId = modelData
                      }
                    }
                    Rectangle {
                      Layout.preferredWidth: 64
                      Layout.preferredHeight: Style.space(28)
                      radius: Style.cornerRadius
                      color: rule && rule.enabled ? Util.alpha(root.accent, 0.28) : Util.alpha(root.fg, 0.08)
                      border.width: 1
                      border.color: root.isSchedFocus(index, "on") ? root.accent : "transparent"
                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: rule && rule.enabled ? "On" : "Off"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        anchors.fill: parent
                        onClicked: if (svc && rule) svc.updateScheduleRule(rule.id, rule.time, rule.theme, !rule.enabled)
                      }
                    }
                    Rectangle {
                      Layout.preferredWidth: 80
                      Layout.preferredHeight: Style.space(28)
                      radius: Style.cornerRadius
                      color: Util.alpha(root.fg, 0.08)
                      border.width: 1
                      border.color: root.isSchedFocus(index, "remove") ? root.accent : "transparent"
                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "Remove"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        anchors.fill: parent
                        onClicked: {
                          if (svc) svc.removeScheduleRule(modelData)
                          var ids = []
                          for (var i = 0; i < root.scheduleViewIds.length; i++)
                            if (root.scheduleViewIds[i] !== modelData) ids.push(root.scheduleViewIds[i])
                          root.scheduleViewIds = ids
                        }
                      }
                    }
                    Rectangle {
                      Layout.preferredWidth: Style.space(28)
                      Layout.preferredHeight: Style.space(28)
                      radius: Style.cornerRadius
                      color: expanded ? Util.alpha(root.accent, 0.28) : Util.alpha(root.fg, 0.08)
                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: expanded ? "▼" : "▶"
                        color: (rule && rule.wallpaperEnabled) ? root.accent : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleScheduleExpand(String(modelData))
                      }
                    }
                  }
                  Row {
                    visible: expanded
                    width: parent.width
                    height: Style.space(44)
                    spacing: Style.space(8)
                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Wallpapers"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Rectangle {
                      width: wpOnLab.implicitWidth + Style.space(28)
                      height: Style.space(28)
                      anchors.verticalCenter: parent.verticalCenter
                      radius: Style.cornerRadius
                      color: rule && rule.wallpaperEnabled ? Util.alpha(root.accent, 0.32) : Util.alpha(root.fg, 0.08)
                      border.width: 1
                      border.color: rule && rule.wallpaperEnabled ? root.accent : Util.alpha(root.fg, 0.14)
                      Row {
                        anchors.centerIn: parent
                        spacing: Style.space(6)
                        Rectangle {
                          width: Style.space(12)
                          height: Style.space(12)
                          radius: Style.cornerRadius
                          color: rule && rule.wallpaperEnabled ? root.accent : root.bg
                          border.width: 1
                          border.color: root.fg
                          Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            visible: !!(rule && rule.wallpaperEnabled)
                            text: "✓"
                            color: root.bg
                            font.pixelSize: 9
                            font.bold: true
                          }
                        }
                        Text {
                          textFormat: Text.PlainText
                          id: wpOnLab
                          text: rule && rule.wallpaperEnabled ? "On" : "Off"
                          color: root.fg
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (svc && rule) svc.updateScheduleRule(rule.id, rule.time, rule.theme, rule.enabled, {
                          enabled: !(rule.wallpaperEnabled)
                        })
                      }
                    }
                    TextField {
                      width: 72
                      anchors.verticalCenter: parent.verticalCenter
                      color: root.fg
                      font.family: root.fontFamily
                      text: String((rule && rule.wallpaperMinutes) || 5)
                      inputMethodHints: Qt.ImhDigitsOnly
                      onEditingFinished: {
                        if (!svc || !rule) return
                        var n = parseInt(text, 10)
                        if (isNaN(n)) n = 5
                        svc.updateScheduleRule(rule.id, rule.time, rule.theme, rule.enabled, { minutes: n })
                      }
                      background: Rectangle {
                        color: Util.alpha(root.fg, 0.08)
                        radius: Style.cornerRadius
                        border.width: 1
                        border.color: Util.alpha(root.fg, 0.14)
                      }
                    }
                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "minutes"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  }
                }
              }

              Repeater {
                model: config.schedule.mode === "sun" ? [{ id: "day", label: "Sunrise" }, { id: "night", label: "Sunset" }] : []
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  readonly property bool expanded: root.isScheduleExpanded("sun-" + modelData.id)
                  readonly property bool wpOn: modelData.id === "day"
                    ? !!(config.schedule.sun && config.schedule.sun.dayWallpaperEnabled)
                    : !!(config.schedule.sun && config.schedule.sun.nightWallpaperEnabled)
                  readonly property int wpMin: modelData.id === "day"
                    ? ((config.schedule.sun && config.schedule.sun.dayWallpaperMinutes) || 5)
                    : ((config.schedule.sun && config.schedule.sun.nightWallpaperMinutes) || 5)
                  width: schedCol.width
                  height: expanded ? Style.space(92) : Style.space(44)
                  radius: Style.cornerRadius
                  color: Util.alpha(root.fg, 0.06)
                  border.width: root.scheduleCursor === index ? 1 : 0
                  border.color: root.accent
                  Column {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: 0
                  RowLayout {
                    width: parent.width
                    height: Style.space(44)
                    spacing: Style.space(8)
                    Text {
                      textFormat: Text.PlainText
                      Layout.preferredWidth: 96
                      text: modelData.label
                      color: root.fg
                      font.family: root.fontFamily
                    }
                    Item {
                      visible: !!root.config.clock12
                      Layout.preferredWidth: 52
                    }
                    Rectangle {
                      Layout.fillWidth: true
                      Layout.preferredHeight: Style.space(32)
                      radius: Style.cornerRadius
                      color: Util.alpha(root.fg, 0.08)
                      border.width: 1
                      border.color: root.isSchedFocus(index, "theme") ? root.accent : Util.alpha(root.fg, 0.14)
                      Text {
                        textFormat: Text.PlainText
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(8)
                        anchors.rightMargin: Style.space(8)
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        text: (Model.themeBySlug(root.themes, modelData.id === "day" ? config.schedule.sun.day : config.schedule.sun.night) || { name: "Choose theme…" }).name
                        color: root.fg
                        font.family: root.fontFamily
                      }
                      MouseArea {
                        anchors.fill: parent
                        onClicked: root.themePickRuleId = "sun-" + modelData.id
                      }
                    }
                    Item { Layout.preferredWidth: 64 }
                    Item { Layout.preferredWidth: 80 }
                    Rectangle {
                      Layout.preferredWidth: Style.space(28)
                      Layout.preferredHeight: Style.space(28)
                      radius: Style.cornerRadius
                      color: expanded ? Util.alpha(root.accent, 0.28) : Util.alpha(root.fg, 0.08)
                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: expanded ? "▼" : "▶"
                        color: wpOn ? root.accent : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleScheduleExpand("sun-" + modelData.id)
                      }
                    }
                  }
                  Row {
                    visible: expanded
                    width: parent.width
                    height: Style.space(44)
                    spacing: Style.space(8)
                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Wallpapers"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Rectangle {
                      width: Style.space(56)
                      height: Style.space(28)
                      anchors.verticalCenter: parent.verticalCenter
                      radius: Style.cornerRadius
                      color: wpOn ? Util.alpha(root.accent, 0.32) : Util.alpha(root.fg, 0.08)
                      border.width: 1
                      border.color: wpOn ? root.accent : Util.alpha(root.fg, 0.14)
                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: wpOn ? "On" : "Off"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (svc) {
                          if (modelData.id === "day") svc.setSchedule({ dayWallpaperEnabled: !wpOn })
                          else svc.setSchedule({ nightWallpaperEnabled: !wpOn })
                        }
                      }
                    }
                    TextField {
                      width: 72
                      anchors.verticalCenter: parent.verticalCenter
                      color: root.fg
                      font.family: root.fontFamily
                      text: String(wpMin)
                      inputMethodHints: Qt.ImhDigitsOnly
                      onEditingFinished: {
                        if (!svc) return
                        var n = parseInt(text, 10)
                        if (isNaN(n)) n = 5
                        if (modelData.id === "day") svc.setSchedule({ dayWallpaperMinutes: n })
                        else svc.setSchedule({ nightWallpaperMinutes: n })
                      }
                      background: Rectangle {
                        color: Util.alpha(root.fg, 0.08)
                        radius: Style.cornerRadius
                        border.width: 1
                        border.color: Util.alpha(root.fg, 0.14)
                      }
                    }
                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: "minutes"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  }
                }
              }

              Rectangle {
                visible: config.schedule.mode !== "sun" && !root.isCycleMode()
                width: addRuleLab.implicitWidth + Style.space(16)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.22)
                border.width: root.scheduleCursor === root.scheduleViewIds.length ? 1 : 0
                border.color: root.accent
                Text {
                  textFormat: Text.PlainText
                  id: addRuleLab
                  anchors.centerIn: parent
                  text: "Add time"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (!svc) return
                    var slug = selectedSlug || (root.themes[0] ? root.themes[0].slug : "")
                    if (!slug) return
                    var id = svc.addScheduleRule("07:00", slug)
                    svc.setSchedule({ mode: "rules" })
                    var ids = root.scheduleViewIds.slice()
                    ids.push(id)
                    root.scheduleViewIds = ids
                  }
                }
              }
            }
          }
          }
        }
        }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: root.mainView === "schedule"
            ? "Esc catalog   Tab mode   C 12/24   ↑/↓ row   ←/→ field   Enter activate   A add time"
            : "F Favorite   H Hide   Shift+↑/↓ Sort in folder   Shift+←/→ Sort folders   N New folder   Enter Apply   E Aether   R Random favorite   / Search   Esc Close"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Rectangle {
        visible: root.addFolderId.length > 0
        anchors.fill: parent
        z: 36
        color: Util.alpha(root.bg, 0.72)
        onVisibleChanged: if (visible) Qt.callLater(function() { addSearchField.forceActiveFocus() })
        MouseArea { anchors.fill: parent; onClicked: root.closeAddModal() }
        Rectangle {
          width: 480
          height: 520
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { } }
          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(16)
            spacing: Style.space(10)
            Text {
              textFormat: Text.PlainText
              text: "Add themes"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              text: "Check to add. Uncheck to remove. Themes in “" + root.addFolderName + "”."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            TextField {
              id: addSearchField
              Layout.fillWidth: true
              placeholderText: "Filter themes"
              text: root.addQuery
              onTextChanged: root.addQuery = text
              Keys.onEscapePressed: root.closeAddModal()
            }
            ListView {
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              model: root.addThemeChoices
              spacing: Style.space(2)
              delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: Style.space(36)
                radius: Style.cornerRadius
                color: addThemeHover.containsMouse ? Util.alpha(root.accent, 0.12) : "transparent"
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)
                  Rectangle {
                    Layout.preferredWidth: Style.space(16)
                    Layout.preferredHeight: Style.space(16)
                    radius: Style.cornerRadius
                    color: modelData.checked ? root.accent : root.bg
                    border.width: 1
                    border.color: root.fg
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      visible: modelData.checked
                      text: "✓"
                      color: root.bg
                      font.pixelSize: 10
                      font.bold: true
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.source
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                MouseArea {
                  id: addThemeHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleAddDraft(modelData.slug)
                }
              }
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: 80
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Cancel"; color: root.fg; font.family: root.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: root.closeAddModal() }
              }
              Rectangle {
                width: addSaveLab.implicitWidth + Style.space(20)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.28)
                Text {
                  textFormat: Text.PlainText
                  id: addSaveLab
                  anchors.centerIn: parent
                  text: "Save folder"
                  color: root.fg
                  font.family: root.fontFamily
                }
                MouseArea { anchors.fill: parent; onClicked: root.saveAddModal() }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.assignSlug.length > 0
        anchors.fill: parent
        z: 36
        color: Util.alpha(root.bg, 0.72)
        MouseArea { anchors.fill: parent; onClicked: root.closeAssignModal() }
        Rectangle {
          width: 420
          height: 460
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { } }
          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(16)
            spacing: Style.space(10)
            Text {
              textFormat: Text.PlainText
              text: "Move to folder"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              text: "Check folders to add this theme. Uncheck to remove. A theme can be in more than one folder."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            ListView {
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              model: root.assignFolderChoices
              spacing: Style.space(2)
              delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: Style.space(36)
                radius: Style.cornerRadius
                color: assignHover.containsMouse ? Util.alpha(root.accent, 0.12) : "transparent"
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)
                  Rectangle {
                    Layout.preferredWidth: Style.space(16)
                    Layout.preferredHeight: Style.space(16)
                    radius: Style.cornerRadius
                    color: modelData.checked ? root.accent : root.bg
                    border.width: 1
                    border.color: root.fg
                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      visible: modelData.checked
                      text: "✓"
                      color: root.bg
                      font.pixelSize: 10
                      font.bold: true
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
                MouseArea {
                  id: assignHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleAssignDraft(modelData.id)
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              text: "+ New folder"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.promptKind = "folder"
                  root.promptText = ""
                }
              }
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: 80
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Cancel"; color: root.fg; font.family: root.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: root.closeAssignModal() }
              }
              Rectangle {
                width: assignSaveLab.implicitWidth + Style.space(20)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.28)
                Text {
                  textFormat: Text.PlainText
                  id: assignSaveLab
                  anchors.centerIn: parent
                  text: "Save folders"
                  color: root.fg
                  font.family: root.fontFamily
                }
                MouseArea { anchors.fill: parent; onClicked: root.saveAssignModal() }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.promptKind.length > 0
        anchors.fill: parent
        z: 40
        color: Util.alpha(root.bg, 0.72)
        onVisibleChanged: if (visible) Qt.callLater(function() { promptField.forceActiveFocus() })
        MouseArea { anchors.fill: parent; onClicked: root.cancelPrompt() }

        Rectangle {
          width: 380
          height: 168
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { /* keep dialog open */ } }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(10)
            Text {
              textFormat: Text.PlainText
              text: root.promptKind === "rename" ? "Rename folder" : "New folder"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }
            TextField {
              id: promptField
              width: 320
              text: root.promptText
              onTextChanged: root.promptText = text
              onAccepted: root.submitPrompt()
              Keys.onEscapePressed: root.cancelPrompt()
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: cancelLabel.implicitWidth + Style.space(16)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.08)
                Text {
                  textFormat: Text.PlainText
                  id: cancelLabel
                  anchors.centerIn: parent
                  text: "Cancel"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.cancelPrompt() }
              }
              Rectangle {
                width: okLabel.implicitWidth + Style.space(16)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.28)
                Text {
                  textFormat: Text.PlainText
                  id: okLabel
                  anchors.centerIn: parent
                  text: root.promptKind === "rename" ? "Rename" : "Create"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.submitPrompt() }
              }
            }
          }
        }
      }

      Rectangle {
        visible: !!(svc && svc.pendingManualSlug)
        anchors.fill: parent
        z: 34
        color: Util.alpha(root.bg, 0.72)
        MouseArea { anchors.fill: parent; onClicked: if (svc) svc.cancelManualApply() }
        Rectangle {
          width: 440
          height: 180
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { } }
          Column {
            anchors.centerIn: parent
            spacing: Style.space(12)
            width: 400
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: {
                var name = (Model.themeBySlug(root.themes, svc ? svc.pendingManualSlug : "") || { name: "this theme" }).name
                return "Apply “" + name + "”? " + root.scheduleModeLabel() + " is on and will be turned off."
              }
              color: root.fg
              font.family: root.fontFamily
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: 80
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Cancel"; color: root.fg; font.family: root.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: if (svc) svc.cancelManualApply() }
              }
              Rectangle {
                width: applyStopLab.implicitWidth + Style.space(20)
                height: Style.space(32)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.28)
                Text {
                  textFormat: Text.PlainText
                  id: applyStopLab
                  anchors.centerIn: parent
                  text: "Apply and stop schedule"
                  color: root.fg
                  font.family: root.fontFamily
                }
                MouseArea { anchors.fill: parent; onClicked: if (svc) svc.confirmManualApply() }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.confirmRemove
        anchors.fill: parent
        z: 30
        color: Util.alpha(root.bg, 0.72)
        MouseArea { anchors.fill: parent; onClicked: root.confirmRemove = false }

        Rectangle {
          width: 420
          height: 160
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { } }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(12)
            width: 380
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.selected ? ("Remove user theme “" + root.selected.name + "”? This deletes that theme from your user themes folder.") : "Remove this user theme from disk?"
              color: root.fg
              font.family: root.fontFamily
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: 80
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Cancel"; color: root.fg; font.family: root.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: root.confirmRemove = false }
              }
              Rectangle {
                width: 90
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.28)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Remove"; color: root.fg; font.family: root.fontFamily }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (svc && selectedSlug) svc.removeTheme(selectedSlug)
                    root.confirmRemove = false
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.confirmFolderId.length > 0
        anchors.fill: parent
        z: 31
        color: Util.alpha(root.bg, 0.72)
        MouseArea { anchors.fill: parent; onClicked: root.confirmFolderId = "" }
        Rectangle {
          width: 420
          height: 150
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          Column {
            anchors.centerIn: parent
            spacing: Style.space(12)
            width: 380
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Delete folder “" + root.confirmFolderName + "”? Themes stay installed; they just leave this folder."
              color: root.fg
              font.family: root.fontFamily
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: 80
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Cancel"; color: root.fg; font.family: root.fontFamily }
                MouseArea { anchors.fill: parent; onClicked: root.confirmFolderId = "" }
              }
              Rectangle {
                width: 90
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.28)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Delete"; color: root.fg; font.family: root.fontFamily }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (svc) svc.deleteFolder(root.confirmFolderId)
                    root.confirmFolderId = ""
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.cycleFolderPickOpen
        anchors.fill: parent
        z: 33
        color: Util.alpha(root.bg, 0.72)
        MouseArea { anchors.fill: parent; onClicked: root.cycleFolderPickOpen = false }
        Rectangle {
          width: 380
          height: 360
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { } }
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(14)
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: "Folder"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }
            ListView {
              width: parent.width
              height: parent.height - Style.space(36)
              clip: true
              model: Model.cycleFolderChoices(root.config)
              delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: Style.space(36)
                radius: Style.cornerRadius
                color: cycleFolderMouse.containsMouse ? Util.alpha(root.accent, 0.16) : "transparent"
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  text: modelData.name || modelData.id
                  color: root.fg
                  font.family: root.fontFamily
                }
                MouseArea {
                  id: cycleFolderMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    if (svc) {
                      if (root.scheduleModeId() === "themes")
                        svc.setThemeCycle({ folderId: modelData.id, resetStamp: true })
                      else
                        svc.setWallpaperCycle({ folderId: modelData.id, resetStamp: true })
                    }
                    root.cycleFolderPickOpen = false
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.themePickRuleId.length > 0
        anchors.fill: parent
        z: 32
        color: Util.alpha(root.bg, 0.72)
        MouseArea { anchors.fill: parent; onClicked: root.themePickRuleId = "" }
        Rectangle {
          width: 420
          height: 420
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { } }
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(14)
            spacing: Style.space(8)
            Text {
              textFormat: Text.PlainText
              text: "Choose theme"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }
            TextField {
              id: themePickSearch
              width: parent.width
              color: root.fg
              font.family: root.fontFamily
              placeholderText: "Fuzzy search"
              text: root.themePickQuery
              onTextChanged: root.themePickQuery = text
              Keys.onEscapePressed: root.themePickRuleId = ""
              background: Rectangle {
                color: Util.alpha(root.fg, 0.08)
                radius: Style.cornerRadius
                border.width: 1
                border.color: Util.alpha(root.fg, 0.14)
              }
            }
            ListView {
              width: parent.width
              height: parent.height - Style.space(80)
              clip: true
              model: root.filteredThemePick()
              delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: Style.space(36)
                color: themePickMouse.containsMouse ? Util.alpha(root.accent, 0.16) : "transparent"
                radius: Style.cornerRadius
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  text: modelData.name || modelData.slug
                  color: root.fg
                  font.family: root.fontFamily
                }
                MouseArea {
                  id: themePickMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    if (!svc) return
                    if (root.themePickRuleId === "sun-day") svc.setSchedule({ day: modelData.slug })
                    else if (root.themePickRuleId === "sun-night") svc.setSchedule({ night: modelData.slug })
                    else {
                      var rules = root.config.schedule.rules || []
                      for (var i = 0; i < rules.length; i++) {
                        if (rules[i].id === root.themePickRuleId)
                          svc.updateScheduleRule(rules[i].id, rules[i].time, modelData.slug, rules[i].enabled)
                      }
                    }
                    root.themePickRuleId = ""
                  }
                }
              }
            }
          }
        }
        onVisibleChanged: if (visible) Qt.callLater(function() { themePickSearch.forceActiveFocus() })
      }
    }
  }

}
