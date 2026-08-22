import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var settings: ({})
  property var manifest: null

  property var themes: []
  property var config: Model.defaultConfig()
  property int catalogRevision: 0
  property string currentSlug: ""
  property bool aetherAvailable: false
  property bool sunwaitAvailable: false
  property bool uwsmAvailable: false
  property bool otherSchedulerEnabled: false
  property string solarPeriod: "unknown"
  property string lastScheduledPeriod: ""
  property string lastAppliedBySchedule: ""
  property string overridePeriod: ""
  property string pendingApply: ""
  property bool manualOverride: false
  property bool installing: false

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("./manifest.json"))
    if (u.indexOf("file://") === 0) u = u.slice(7)
    try { u = decodeURIComponent(u) } catch (e) {}
    var i = u.lastIndexOf("/")
    return i > 0 ? u.slice(0, i) : u
  }
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/themebook.json"
  readonly property var rows: Model.flatten(root.themes, root.config, root.filter, root.query)
  property string filter: "all"
  property string query: ""

  function scriptPath(name) {
    var n = String(name || "")
    if (!n || n.indexOf("/") >= 0 || n.indexOf("..") >= 0) return ""
    return root.pluginDir + "/scripts/" + n
  }

  function reloadCatalog() {
    catalogProc.running = true
  }

  function reloadTools() {
    toolsProc.running = true
    schedulerCheck.running = true
    sunProc.running = true
  }

  function knownTheme(slug) {
    return !!Model.themeBySlug(root.themes, slug)
  }

  function saveConfig(next) {
    var pruned = Model.pruneConfig(next, root.themes)
    root.config = pruned
    configWriter.command = [scriptPath("config"), "write", JSON.stringify(pruned)]
    configWriter.running = true
  }

  function applyTheme(slug, fromSchedule) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    if (applyProc.running) {
      root.pendingApply = slug
      return
    }
    applyProc.command = ["omarchy", "theme", "set", slug]
    applyProc.running = true
    var next = Model.normalizeConfig(root.config)
    next.recents = Model.pushRecent(next.recents, slug)
    if (fromSchedule) {
      root.manualOverride = false
    } else {
      root.manualOverride = true
      root.overridePeriod = Model.currentPeriod(next, root.solarPeriod)
    }
    saveConfig(next)
  }

  function applyBackground(path) {
    if (!path || String(path).indexOf("..") >= 0) return
    var ok = false
    for (var i = 0; i < root.themes.length; i++) {
      var bgs = root.themes[i].backgrounds || []
      for (var j = 0; j < bgs.length; j++) {
        if (bgs[j] === path) { ok = true; break }
      }
      if (ok) break
    }
    if (!ok) return
    bgProc.command = ["omarchy", "theme", "bg", "set", path]
    bgProc.running = true
  }

  function updateGitThemes() {
    updateProc.command = ["omarchy", "theme", "update"]
    updateProc.running = true
  }

  function removeTheme(slug) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var t = Model.themeBySlug(root.themes, slug)
    if (!t || t.source !== "user" || slug === root.currentSlug) return
    removeProc.command = ["omarchy", "theme", "remove", slug]
    removeProc.running = true
  }

  function openAether(theme) {
    if (!root.aetherAvailable || !theme) return
    var args = []
    if (root.uwsmAvailable) {
      args.push("uwsm-app")
      args.push("--")
    }
    args.push("aether")
    if (theme.source === "user" && theme.path && String(theme.path).indexOf("..") < 0 && String(theme.path).indexOf(root.home + "/.config/omarchy/themes/") === 0) {
      args.push("--import-colors-toml")
      args.push(theme.path + "/colors.toml")
      if (theme.backgrounds && theme.backgrounds.length && String(theme.backgrounds[0]).indexOf("..") < 0) {
        args.push("--wallpaper")
        args.push(theme.backgrounds[0])
      }
    }
    aetherProc.command = args
    aetherProc.running = true
  }

  function toggleFavorite(slug) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var next = Model.normalizeConfig(root.config)
    next.favorites = Model.toggleInList(next.favorites, slug)
    saveConfig(next)
  }

  function toggleHidden(slug) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var next = Model.normalizeConfig(root.config)
    next.hidden = Model.toggleInList(next.hidden, slug)
    saveConfig(next)
  }

  function reorder(section, slug, delta) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var next = Model.normalizeConfig(root.config)
    if (section === "favorites") {
      next.favorites = Model.moveInList(next.favorites, slug, delta)
    } else {
      for (var i = 0; i < next.folders.length; i++) {
        if (next.folders[i].id === section) {
          next.folders[i].themes = Model.moveInList(next.folders[i].themes, slug, delta)
          break
        }
      }
    }
    saveConfig(next)
  }

  function createFolder(name) {
    var next = Model.normalizeConfig(root.config)
    var id = Model.newFolderId(next.folders)
    next.folders.push({ id: id, name: Model.sanitizeFolderName(name), themes: [] })
    saveConfig(next)
    return id
  }

  function renameFolder(id, name) {
    if (Model.isReservedSection(id)) return
    var next = Model.normalizeConfig(root.config)
    for (var i = 0; i < next.folders.length; i++) {
      if (next.folders[i].id === id) {
        next.folders[i].name = Model.sanitizeFolderName(name || next.folders[i].name)
        break
      }
    }
    saveConfig(next)
  }

  function deleteFolder(id) {
    if (Model.isReservedSection(id)) return
    var next = Model.normalizeConfig(root.config)
    next.folders = next.folders.filter(function(f) { return f.id !== id })
    saveConfig(next)
  }

  function moveFolder(id, delta) {
    var next = Model.normalizeConfig(root.config)
    var ids = next.folders.map(function(f) { return f.id })
    var moved = Model.moveInList(ids, id, delta)
    var map = {}
    for (var i = 0; i < next.folders.length; i++) map[next.folders[i].id] = next.folders[i]
    next.folders = moved.map(function(fid) { return map[fid] })
    saveConfig(next)
  }

  function moveToFolder(slug, folderId) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var next = Model.normalizeConfig(root.config)
    for (var i = 0; i < next.folders.length; i++) {
      next.folders[i].themes = next.folders[i].themes.filter(function(s) { return s !== slug })
    }
    if (folderId && folderId !== "user" && folderId !== "stock" && folderId !== "favorites" && folderId !== "recents") {
      for (var j = 0; j < next.folders.length; j++) {
        if (next.folders[j].id === folderId) {
          next.folders[j].themes.push(slug)
          break
        }
      }
    }
    saveConfig(next)
  }

  function setSchedule(patch) {
    var next = Model.normalizeConfig(root.config)
    var s = next.schedule
    if (patch.mode !== undefined) s.mode = patch.mode
    if (patch.day !== undefined) s.day = patch.day
    if (patch.night !== undefined) s.night = patch.night
    if (patch.dayAt !== undefined) s.dayAt = patch.dayAt
    if (patch.nightAt !== undefined) s.nightAt = patch.nightAt
    next.schedule = Model.normalizeSchedule(s)
    root.manualOverride = false
    root.lastScheduledPeriod = ""
    saveConfig(next)
  }

  function bumpScheduleTime(which, delta) {
    var next = Model.normalizeConfig(root.config)
    if (which === "night")
      next.schedule.nightAt = Model.bumpHHMM(next.schedule.nightAt, delta)
    else
      next.schedule.dayAt = Model.bumpHHMM(next.schedule.dayAt, delta)
    saveConfig(next)
  }

  function randomFavorite() {
    var cfg = Model.normalizeConfig(root.config)
    cfg.schedule.day = "__random_favorite__"
    var slug = Model.pickScheduledSlug(cfg, root.themes, "day", root.currentSlug)
    if (slug) applyTheme(slug)
  }

  function tickSchedule() {
    if (root.otherSchedulerEnabled) return
    var cfg = Model.normalizeConfig(root.config)
    var period = Model.currentPeriod(cfg, root.solarPeriod)
    if (!period) return
    if (root.manualOverride && period === root.overridePeriod) return
    if (root.manualOverride && period !== root.overridePeriod)
      root.manualOverride = false
    if (period === root.lastScheduledPeriod && root.lastAppliedBySchedule) return
    var slug = Model.pickScheduledSlug(cfg, root.themes, period, root.currentSlug)
    if (!slug || slug === root.currentSlug) {
      root.lastScheduledPeriod = period
      return
    }
    root.lastScheduledPeriod = period
    root.lastAppliedBySchedule = slug
    applyTheme(slug, true)
  }

  function installLaunchers() {
    if (root.installing) return
    root.installing = true
    installProc.command = [scriptPath("desktop-entry"), root.pluginDir]
    installProc.running = true
  }

  Process {
    id: catalogProc
    command: [root.scriptPath("catalog")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "[]"))
          if (Array.isArray(parsed)) {
            root.themes = parsed
            root.config = Model.pruneConfig(root.config, parsed)
            root.catalogRevision++
            var cur = ""
            for (var i = 0; i < parsed.length; i++) if (parsed[i].current) cur = parsed[i].slug
            if (cur) root.currentSlug = cur
          }
        } catch (e) {
          console.warn("themebook catalog:", e)
        }
      }
    }
  }

  Process {
    id: configWriter
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw.length) console.warn("themebook config:", raw)
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      root.reloadCatalog()
      if (root.pendingApply) {
        var next = root.pendingApply
        root.pendingApply = ""
        root.applyTheme(next)
      }
    }
  }

  Process {
    id: bgProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: root.reloadCatalog()
  }

  Process {
    id: updateProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: root.reloadCatalog()
  }

  Process {
    id: removeProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: root.reloadCatalog()
  }

  Process {
    id: aetherProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: installProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: root.installing = false
  }

  Process {
    id: toolsProc
    command: [root.scriptPath("tools")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var t = JSON.parse(String(text || "{}"))
          root.aetherAvailable = t.aether === true
          root.sunwaitAvailable = t.sunwait === true
          root.uwsmAvailable = t.uwsm === true
        } catch (e) {
          root.aetherAvailable = false
          root.sunwaitAvailable = false
          root.uwsmAvailable = false
        }
      }
    }
  }

  Process {
    id: schedulerCheck
    command: ["omarchy", "plugin", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(String(text || "[]"))
          root.otherSchedulerEnabled = false
          for (var i = 0; i < list.length; i++) {
            if (list[i].id === "acrogenesis.theme-scheduler" && list[i].enabled)
              root.otherSchedulerEnabled = true
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: sunProc
    command: [root.scriptPath("sun")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p === "day" || p === "night" || p === "unknown") root.solarPeriod = p
      }
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root.config = Model.normalizeConfig(JSON.parse(String(text() || "{}")))
      } catch (e) {
        root.config = Model.defaultConfig()
      }
    }
    onLoadFailed: root.config = Model.defaultConfig()
  }

  FileView {
    id: currentThemeFile
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.currentSlug = String(text() || "").trim()
      root.reloadCatalog()
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      sunProc.running = true
      root.tickSchedule()
    }
  }

  IpcHandler {
    target: "themebook"

    function favorite(slug: string): string {
      root.toggleFavorite(slug)
      return JSON.stringify(root.config.favorites)
    }

    function hide(slug: string): string {
      root.toggleHidden(slug)
      return JSON.stringify(root.config.hidden)
    }

    function apply(slug: string): string {
      if (!Model.isValidSlug(slug) || !root.knownTheme(slug)) return "rejected"
      root.applyTheme(slug)
      return "ok"
    }

    function makeFolder(name: string): string {
      return root.createFolder(name)
    }

    function moveTo(slug: string, folderId: string): string {
      root.moveToFolder(slug, folderId)
      return folderId
    }

    function dropFolder(id: string): string {
      root.deleteFolder(id)
      return id
    }

    function setFilter(id: string): string {
      root.filter = id
      return root.filter
    }

    function setScheduleMode(mode: string): string {
      root.setSchedule({ mode: mode })
      return root.config.schedule.mode
    }

    function setScheduleTheme(which: string, slug: string): string {
      if (which === "night") root.setSchedule({ night: slug })
      else root.setSchedule({ day: slug })
      return which
    }

    function configJson(): string {
      return JSON.stringify(root.config)
    }
  }

  Component.onCompleted: {
    configFile.reload()
    root.reloadTools()
    root.reloadCatalog()
    root.installLaunchers()
    Qt.callLater(function() { root.tickSchedule() })
  }
}
