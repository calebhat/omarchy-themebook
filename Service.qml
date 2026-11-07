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
  property bool pendingApplyFromSchedule: false
  property string pendingConfigWrite: ""
  property string pendingBg: ""
  property bool pendingBgNext: false
  property string wallpaperPeriodKey: ""
  property string pendingManualSlug: ""
  property string pendingRemoveSlug: ""
  property string pendingRenameFrom: ""
  property string pendingRenameTo: ""
  property string pendingBgOp: ""
  property string pendingBgFrom: ""
  property string pendingBgPath: ""
  property string pendingBgTo: ""
  property string actionError: ""
  signal themeRenamed(string from, string to)
  signal backgroundRemoved(string path)
  property bool updateOpen: false
  property bool updateRunning: false
  property int updateTotal: 0
  property var updateRows: []
  signal requestPanelView(string name)
  property bool manualOverride: false
  property bool installing: false
  property bool thumbsWarming: false
  property string lastThumbKey: ""
  property string lastPosterKey: ""
  property string configStamp: ""

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

  function reloadConfig() {
    configReader.running = true
  }

  function knownTheme(slug) {
    return !!Model.themeBySlug(root.themes, slug)
  }

  function flushConfigWrite() {
    var payload = root.pendingConfigWrite
    if (!payload || configWriter.running) return
    root.pendingConfigWrite = ""
    configWriter.command = [scriptPath("config"), "write", payload]
    configWriter.running = true
  }

  function saveConfig(next) {
    var pruned = Model.pruneConfig(next, root.themes)
    var payload = JSON.stringify(pruned)
    if (payload.length > Model.maxConfigChars()) return
    root.config = pruned
    root.pendingConfigWrite = payload
    root.flushConfigWrite()
  }

  function stopScheduleForManualApply() {
    if (!Model.isScheduleActive(root.config)) return
    var next = Model.clearSchedule(root.config)
    root.manualOverride = true
    root.overridePeriod = ""
    root.lastScheduledPeriod = ""
    root.lastAppliedBySchedule = ""
    root.wallpaperPeriodKey = ""
    root.pendingBgNext = false
    saveConfig(next)
  }

  function requestManualApply(slug) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    if (Model.isScheduleActive(root.config)) {
      root.pendingManualSlug = slug
      return
    }
    root.pendingManualSlug = ""
    applyTheme(slug, false)
  }

  function confirmManualApply() {
    var slug = root.pendingManualSlug
    root.pendingManualSlug = ""
    root.stopScheduleForManualApply()
    if (slug) applyTheme(slug, false)
  }

  function cancelManualApply() {
    root.pendingManualSlug = ""
    root.pendingBg = ""
  }

  function applyTheme(slug, fromSchedule) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    if (!fromSchedule) root.stopScheduleForManualApply()
    if (applyProc.running) {
      root.pendingApply = slug
      root.pendingApplyFromSchedule = fromSchedule === true
      if (!fromSchedule) {
        var queuedBgSlug = Model.themeSlugForBackground(root.themes, root.pendingBg)
        if (root.pendingBg && queuedBgSlug && queuedBgSlug !== slug) root.pendingBg = ""
        root.pendingBgNext = false
      }
      return
    }
    var next = Model.normalizeConfig(root.config)
    if (!root.pendingBg) {
      var theme = Model.themeBySlug(root.themes, slug)
      var def = Model.defaultWallpaper(next, theme)
      if (!def && theme) {
        var prev = String(theme.preview || "")
        var bgs = theme.backgrounds || []
        for (var i = 0; i < bgs.length; i++) {
          if (bgs[i] === prev) { def = prev; break }
        }
      }
      if (def) root.pendingBg = def
    }
    if (slug === root.currentSlug) {
      if (root.pendingBg) {
        var same = root.pendingBg
        root.pendingBg = ""
        applyBackground(same)
      }
      next.recents = Model.pushRecent(next.recents, slug)
      saveConfig(next)
      return
    }
    applyProc.command = ["omarchy", "theme", "set", slug]
    applyProc.running = true
    next.recents = Model.pushRecent(next.recents, slug)
    if (fromSchedule) root.manualOverride = false
    else {
      root.manualOverride = true
      root.overridePeriod = ""
      root.lastScheduledPeriod = ""
      root.wallpaperPeriodKey = ""
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
    root.patchCurrentBackground(path)
  }

  function patchCurrentBackground(path) {
    var list = root.themes.slice()
    var changed = false
    for (var i = 0; i < list.length; i++) {
      if (list[i].slug !== root.currentSlug) continue
      var t = {}
      for (var k in list[i]) t[k] = list[i][k]
      t.currentBackground = path
      list[i] = t
      changed = true
    }
    if (changed) {
      root.themes = list
      root.catalogRevision++
    }
  }

  function applyNextBackground() {
    if (!Model.activeWallpaperSpec(root.config, root.solarPeriod).on) {
      root.pendingBgNext = false
      return
    }
    if (applyProc.running || bgProc.running) {
      root.pendingBgNext = true
      return
    }
    bgProc.command = ["omarchy", "theme", "bg", "next"]
    bgProc.running = true
  }

  function applyBackgroundAndTheme(path) {
    var slug = Model.themeSlugForBackground(root.themes, path)
    if (slug && (slug !== root.currentSlug || Model.activeWallpaperSpec(root.config, root.solarPeriod).on)) {
      root.pendingBg = path
      root.requestManualApply(slug)
      return
    }
    applyBackground(path)
  }

  function closeGitUpdate() {
    if (root.updateRunning) return
    root.updateOpen = false
    root.updateRows = []
    root.updateTotal = 0
  }

  function ingestGitUpdateLine(line) {
    var o = Model.parseGitUpdateLine(line)
    if (!o) return
    if (o.event === "start") {
      root.updateTotal = o.total
      return
    }
    if (o.event === "done") return
    if (o.event !== "theme") return
    var rows = (root.updateRows || []).slice()
    var found = false
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].slug === o.slug) {
        rows[i] = { slug: o.slug, name: o.name, status: o.status, detail: o.detail }
        found = true
        break
      }
    }
    if (!found)
      rows.push({ slug: o.slug, name: o.name, status: o.status, detail: o.detail })
    if (rows.length > Model.maxThemes()) rows = rows.slice(0, Model.maxThemes())
    root.updateRows = rows
  }

  function updateGitThemes() {
    if (updateProc.running) {
      root.updateOpen = true
      return
    }
    var cmd = scriptPath("update-git")
    if (!cmd) return
    root.updateOpen = true
    root.updateRunning = true
    root.updateTotal = 0
    root.updateRows = []
    updateProc.command = [cmd]
    updateProc.running = true
  }

  function removeTheme(slug) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var t = Model.themeBySlug(root.themes, slug)
    if (!Model.canDeleteFromOs(t, root.currentSlug)) return
    if (removeProc.running) return
    var cmd = scriptPath("remove")
    if (!cmd) return
    root.pendingRemoveSlug = slug
    removeProc.command = [cmd, slug]
    removeProc.running = true
  }

  function patchThemeRename(from, to, rewrites) {
    var list = (root.themes || []).slice()
    for (var i = 0; i < list.length; i++) {
      if (!list[i] || list[i].slug !== from) continue
      var copy = {}
      for (var k in list[i]) copy[k] = list[i][k]
      copy.slug = to
      copy.name = Model.themeTitle(to)
      var bgs = copy.backgrounds || []
      var nextBgs = []
      for (var b = 0; b < bgs.length; b++) nextBgs.push(Model.mapRewrittenPath(bgs[b], rewrites))
      copy.backgrounds = nextBgs
      var owned = copy.ownedBackgrounds || []
      var nextOwned = []
      for (var n = 0; n < owned.length; n++) nextOwned.push(Model.mapRewrittenPath(owned[n], rewrites))
      copy.ownedBackgrounds = nextOwned
      if (copy.preview) copy.preview = Model.mapRewrittenPath(copy.preview, rewrites)
      if (copy.appPreview) copy.appPreview = Model.mapRewrittenPath(copy.appPreview, rewrites)
      if (copy.path) copy.path = Model.mapRewrittenPath(copy.path, rewrites)
      if (copy.thumbnail) copy.thumbnail = Model.mapRewrittenPath(copy.thumbnail, rewrites)
      list[i] = copy
    }
    root.themes = list
  }

  function renameTheme(slug, name) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var theme = Model.themeBySlug(root.themes, slug)
    if (!Model.canRenameTheme(theme)) {
      root.actionError = "Stock themes cannot be renamed."
      return
    }
    var to = Model.slugifyThemeName(name)
    if (!to) {
      root.actionError = "Use a name that becomes a theme slug."
      return
    }
    if (to === slug) {
      root.actionError = ""
      return
    }
    if (knownTheme(to)) {
      root.actionError = "A theme with that name already exists."
      return
    }
    if (renameProc.running) return
    var cmd = scriptPath("rename")
    if (!cmd) return
    root.actionError = ""
    root.pendingRenameFrom = slug
    root.pendingRenameTo = to
    renameProc.command = [cmd, slug, to]
    renameProc.running = true
  }

  function finishRename(code, payload) {
    var from = root.pendingRenameFrom
    var to = root.pendingRenameTo
    root.pendingRenameFrom = ""
    root.pendingRenameTo = ""
    var info = Model.parseToolResult(payload)
    if (code === 0 && info && info.ok && info.to) {
      var dest = info.to
      var rewrites = info.rewrites || []
      patchThemeRename(from, dest, rewrites)
      if (root.currentSlug === from) root.currentSlug = dest
      var next = Model.renameSlugInConfig(root.config, from, dest)
      next = Model.rewriteConfigPaths(next, rewrites)
      saveConfig(next)
      root.themeRenamed(from, dest)
      if (info.background)
        Quickshell.execDetached(["omarchy", "theme", "bg", "set", info.background])
    } else {
      root.actionError = Model.toolErrorText(info)
    }
    root.reloadCatalog()
  }

  function patchBackgroundLists(fromSlug, toSlug, oldPath, newPath, removing) {
    var list = (root.themes || []).slice()
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      var copy = null
      if (removing && t.slug === fromSlug) {
        copy = {}
        for (var k in t) copy[k] = t[k]
        var bgs = []
        var raw = t.backgrounds || []
        for (var b = 0; b < raw.length; b++) if (raw[b] !== oldPath) bgs.push(raw[b])
        copy.backgrounds = bgs
        var owned = []
        var rawOwned = t.ownedBackgrounds || []
        for (var n = 0; n < rawOwned.length; n++) if (rawOwned[n] !== oldPath) owned.push(rawOwned[n])
        copy.ownedBackgrounds = owned
      }
      if (newPath && t.slug === toSlug) {
        if (!copy) {
          copy = {}
          for (var k2 in t) copy[k2] = t[k2]
          copy.backgrounds = (t.backgrounds || []).slice()
          copy.ownedBackgrounds = (t.ownedBackgrounds || []).slice()
        }
        if (copy.backgrounds.indexOf(newPath) < 0) copy.backgrounds.push(newPath)
        if (copy.ownedBackgrounds.indexOf(newPath) < 0) copy.ownedBackgrounds.push(newPath)
      }
      if (copy) list[i] = copy
    }
    root.themes = list
  }

  function runBackground(op, fromSlug, path, toSlug) {
    if (!Model.isValidSlug(fromSlug) || !path || String(path).indexOf("..") >= 0) return
    if (op !== "delete" && !Model.isValidSlug(toSlug)) return
    if (fileProc.running) return
    var cmd = scriptPath("background")
    if (!cmd) return
    var theme = Model.themeBySlug(root.themes, fromSlug)
    if (!theme) return
    var known = false
    var bgs = theme.backgrounds || []
    for (var i = 0; i < bgs.length; i++) if (bgs[i] === path) known = true
    if (!known) return
    if (op !== "copy" && !Model.backgroundOwned(theme, path)) {
      root.actionError = "Packaged wallpapers can be copied, not moved or deleted."
      return
    }
    root.actionError = ""
    root.pendingBgOp = op
    root.pendingBgFrom = fromSlug
    root.pendingBgPath = path
    root.pendingBgTo = toSlug || ""
    var args = [cmd, op, fromSlug, path]
    if (op !== "delete") args.push(toSlug)
    fileProc.command = args
    fileProc.running = true
  }

  function copyBackground(fromSlug, path, toSlug) {
    runBackground("copy", fromSlug, path, toSlug)
  }

  function moveBackground(fromSlug, path, toSlug) {
    runBackground("move", fromSlug, path, toSlug)
  }

  function deleteBackground(slug, path) {
    runBackground("delete", slug, path, "")
  }

  function finishBackground(code, payload) {
    var op = root.pendingBgOp
    var from = root.pendingBgFrom
    var oldPath = root.pendingBgPath
    var to = root.pendingBgTo
    var wasCurrent = false
    var list = root.themes || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].currentBackground === oldPath) wasCurrent = true
    }
    var wasDefault = !!(root.config.defaultWallpapers && root.config.defaultWallpapers[from] === oldPath)
    root.pendingBgOp = ""
    root.pendingBgFrom = ""
    root.pendingBgPath = ""
    root.pendingBgTo = ""
    var info = Model.parseToolResult(payload)
    if (code === 0 && info && info.ok) {
      root.actionError = ""
      if (op === "delete") {
        patchBackgroundLists(from, "", oldPath, "", true)
        saveConfig(Model.dropBackgroundPath(root.config, oldPath))
        root.backgroundRemoved(oldPath)
      } else if (op === "move" && info.path) {
        patchBackgroundLists(from, to, oldPath, info.path, true)
        var next = Model.dropBackgroundPath(root.config, oldPath)
        if (wasDefault) next.defaultWallpapers[to] = info.path
        saveConfig(next)
        root.backgroundRemoved(oldPath)
        if (wasCurrent)
          Quickshell.execDetached(["omarchy", "theme", "bg", "set", info.path])
      }
    } else {
      root.actionError = Model.toolErrorText(info)
    }
    root.reloadCatalog()
  }

  function openPicker() {
    pickerOverlay.open()
  }

  function closePicker() {
    if (pickerOverlay.opened) pickerOverlay.close()
  }

  function togglePicker() {
    if (pickerOverlay.opened) {
      pickerOverlay.close()
      return "closed"
    }
    pickerOverlay.open()
    return "open"
  }

  function openAether(theme) {
    if (!root.aetherAvailable || !theme) return
    var wallpaper = ""
    var def = Model.defaultWallpaper(root.config, theme)
    if (def) wallpaper = def
    else if (theme.backgrounds && theme.backgrounds.length && String(theme.backgrounds[0]).indexOf("..") < 0)
      wallpaper = theme.backgrounds[0]
    else if (theme.preview && String(theme.preview).indexOf("..") < 0)
      wallpaper = theme.preview
    var cmd = [scriptPath("open-aether")]
    if (wallpaper) cmd.push(wallpaper)
    aetherProc.command = cmd
    aetherProc.running = true
  }

  function toggleFavorite(slug) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var next = Model.normalizeConfig(root.config)
    next.favorites = Model.toggleInList(next.favorites, slug)
    saveConfig(next)
    root.syncCycles()
  }

  function toggleHidden(slug) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var next = Model.normalizeConfig(root.config)
    next.hidden = Model.toggleInList(next.hidden, slug)
    saveConfig(next)
    root.syncCycles()
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
    root.syncCycles()
  }

  function createFolder(name) {
    var next = Model.normalizeConfig(root.config)
    var id = Model.newFolderId(next.folders)
    next.folders.push({ id: id, name: Model.sanitizeFolderName(name), themes: [], inPicker: true })
    var order = next.sectionOrder.slice()
    var anchor = order.indexOf("added")
    if (anchor < 0) anchor = order.indexOf("recents")
    var user = order.indexOf("user")
    var at = anchor >= 0 ? anchor + 1 : (user >= 0 ? user : order.length)
    order.splice(at, 0, id)
    next.sectionOrder = Model.normalizeSectionOrder(order, next.folders)
    saveConfig(next)
    root.syncCycles()
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
    root.foldersChanged()
  }

  function deleteFolder(id) {
    if (Model.isReservedSection(id)) return
    var next = Model.normalizeConfig(root.config)
    next.folders = next.folders.filter(function(f) { return f.id !== id })
    var kept = []
    for (var i = 0; i < next.sectionOrder.length; i++)
      if (next.sectionOrder[i] !== id) kept.push(next.sectionOrder[i])
    next.sectionOrder = Model.normalizeSectionOrder(kept, next.folders)
    if (next.themeCycle.folderId === id) next.themeCycle.folderId = ""
    saveConfig(next)
    root.syncCycles()
  }

  function moveFolder(id, delta) {
    if (!Model.isReorderableSection(id)) return
    var next = Model.normalizeConfig(root.config)
    next.sectionOrder = Model.moveInList(next.sectionOrder, id, delta)
    saveConfig(next)
    root.foldersChanged()
  }

  function moveFolderBefore(fromId, toId) {
    root.moveSectionInsert(fromId, toId, false)
  }

  function moveSectionInsert(fromId, beforeId, atEnd) {
    if (!Model.isReorderableSection(fromId)) return
    if (!atEnd && (!beforeId || !Model.isReorderableSection(beforeId))) return
    if (!atEnd && fromId === beforeId) return
    var next = Model.normalizeConfig(root.config)
    var order = next.sectionOrder.slice()
    var from = order.indexOf(fromId)
    if (from < 0) return
    order.splice(from, 1)
    if (atEnd === true) {
      order.push(fromId)
    } else {
      var to = order.indexOf(beforeId)
      if (to < 0) return
      order.splice(to, 0, fromId)
    }
    if (order.join("\n") === next.sectionOrder.join("\n")) return
    next.sectionOrder = order
    saveConfig(next)
    root.foldersChanged()
  }

  function toggleCollapsed(id) {
    if (!id) return
    var next = Model.normalizeConfig(root.config)
    next.collapsed[id] = !Model.isCollapsed(next, id)
    saveConfig(next)
  }

  function setFolderInPicker(id, on) {
    var next = Model.normalizeConfig(root.config)
    if (id === "favorites") next.picker.includeFavorites = on === true
    else if (id === "recents") next.picker.includeRecents = on === true
    else if (id === "added") next.picker.includeAdded = on === true
    else if (id === "user") next.picker.includeUser = on === true
    else if (id === "stock") next.picker.includeStock = on === true
    else {
      for (var i = 0; i < next.folders.length; i++) {
        if (next.folders[i].id === id) next.folders[i].inPicker = on === true
      }
    }
    saveConfig(next)
    root.foldersChanged()
  }

  function setPickerLocation(folderId, slug, focusRow) {
    var next = Model.normalizeConfig(root.config)
    next.picker.lastFolder = String(folderId || "")
    next.picker.lastSlug = String(slug || "")
    next.picker.lastFocusRow = focusRow === "folders" ? "folders" : "themes"
    saveConfig(next)
  }

  function setPickerDefault(id) {
    var next = Model.normalizeConfig(root.config)
    next.picker.defaultFolder = String(id || "all")
    saveConfig(next)
  }

  function setClock12(on) {
    var next = Model.normalizeConfig(root.config)
    next.clock12 = on === true
    saveConfig(next)
  }

  function syncPickerMenu() {
    var on = !!(root.config.picker && root.config.picker.replaceDefault)
    pickerMenuProc.command = [scriptPath("set-default-picker"), on ? "replace" : "restore"]
    pickerMenuProc.running = true
  }

  // Same strip as scripts/set-default-picker restore. argv python so this still
  // runs after plugin-remove deletes the checkout (disable destroys the service
  // first, but the script file may already be gone).
  readonly property string restoreMenuPy: "import pathlib,sys\npath=pathlib.Path(sys.argv[1])\nif not path.exists(): raise SystemExit(0)\nout=[]\nfor line in path.read_text().splitlines(True):\n    key=line.lstrip()\n    if key.startswith('\"style.theme\"') or key.startswith('\"appearance.theme\"'): continue\n    out.append(line)\npath.write_text(''.join(out).replace(',\\n}','\\n}'))"

  function restorePickerMenuNow() {
    var menu = root.home + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    Quickshell.execDetached(["python3", "-c", root.restoreMenuPy, menu])
  }

  function setPickerAsked(yes) {
    var next = Model.normalizeConfig(root.config)
    next.picker.asked = true
    next.picker.replaceDefault = yes === true
    saveConfig(next)
    pickerMenuProc.command = [scriptPath("set-default-picker"), yes === true ? "replace" : "restore"]
    pickerMenuProc.running = true
  }

  function folderInPicker(id) {
    var cfg = Model.normalizeConfig(root.config)
    if (id === "favorites") return cfg.picker.includeFavorites
    if (id === "recents") return cfg.picker.includeRecents
    if (id === "added") return cfg.picker.includeAdded
    if (id === "user") return cfg.picker.includeUser
    if (id === "stock") return cfg.picker.includeStock
    for (var i = 0; i < cfg.folders.length; i++)
      if (cfg.folders[i].id === id) return cfg.folders[i].inPicker === true
    return false
  }

  function setCollapsedAll(collapsed) {
    var next = Model.normalizeConfig(root.config)
    var ids = ["favorites", "recents", "added", "user", "stock", "hidden"]
    for (var i = 0; i < next.folders.length; i++) ids.push(next.folders[i].id)
    for (var j = 0; j < ids.length; j++) next.collapsed[ids[j]] = collapsed === true
    saveConfig(next)
  }

  function knownMap() {
    var map = {}
    var list = root.themes || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].slug) map[list[i].slug] = true
    }
    return map
  }

  function addToFolder(slug, folderId) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    saveConfig(Model.addSlugToFolder(root.config, folderId, slug))
    root.syncCycles()
  }

  function removeFromFolder(slug, folderId) {
    if (!Model.isValidSlug(slug)) return
    saveConfig(Model.dropSlugFromFolder(root.config, folderId, slug))
    root.syncCycles()
  }

  function setFolderThemes(folderId, slugs) {
    saveConfig(Model.replaceFolderThemes(root.config, folderId, slugs, root.knownMap()))
    root.syncCycles()
  }

  function setThemeFolders(slug, folderIds) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    saveConfig(Model.setThemeFolders(root.config, slug, folderIds))
    root.syncCycles()
  }

  function moveToFolder(slug, folderId) {
    root.addToFolder(slug, folderId)
  }

  function setSchedule(patch) {
    var next = Model.normalizeConfig(root.config)
    var s = next.schedule
    if (patch.mode === "off") {
      next = Model.clearSchedule(next)
      s = next.schedule
    } else if (patch.mode === "sun") {
      s.enabled = false
      s.sun.enabled = true
      s.mode = "sun"
    } else if (patch.mode === "rules" || patch.mode === "clock") {
      s.enabled = true
      s.sun.enabled = false
      s.mode = "rules"
    } else if (patch.mode === "themes" || patch.mode === "theme") {
      s.enabled = false
      s.sun.enabled = false
      s.mode = "themes"
      next.themeCycle.lastAt = Date.now()
      next.themeCycle.wallpaperLastAt = Date.now()
    } else if (patch.mode === "wallpapers" || patch.mode === "cycle" || patch.mode === "wallpaper") {
      s.enabled = false
      s.sun.enabled = false
      s.mode = "wallpapers"
      next.wallpaperCycle.lastAt = Date.now()
    }
    if (patch.enabled !== undefined) {
      s.enabled = patch.enabled === true
      if (s.enabled) s.sun.enabled = false
      s.mode = s.sun.enabled ? "sun" : (s.enabled ? "rules" : "off")
    }
    if (patch.day !== undefined) {
      s.sun.day = patch.day
      if (patch.day) s.sun.dayFolderId = ""
    }
    if (patch.night !== undefined) {
      s.sun.night = patch.night
      if (patch.night) s.sun.nightFolderId = ""
    }
    if (patch.dayFolderId !== undefined) {
      s.sun.dayFolderId = patch.dayFolderId
      if (patch.dayFolderId) s.sun.day = ""
      s.sun.dayCycleLastAt = Date.now()
      s.sun.dayLastSlug = ""
    }
    if (patch.nightFolderId !== undefined) {
      s.sun.nightFolderId = patch.nightFolderId
      if (patch.nightFolderId) s.sun.night = ""
      s.sun.nightCycleLastAt = Date.now()
      s.sun.nightLastSlug = ""
    }
    if (patch.dayCycleMinutes !== undefined) {
      s.sun.dayCycleMinutes = patch.dayCycleMinutes
      s.sun.dayCycleLastAt = Date.now()
    }
    if (patch.nightCycleMinutes !== undefined) {
      s.sun.nightCycleMinutes = patch.nightCycleMinutes
      s.sun.nightCycleLastAt = Date.now()
    }
    if (patch.dayWallpaperEnabled !== undefined) s.sun.dayWallpaperEnabled = patch.dayWallpaperEnabled === true
    if (patch.nightWallpaperEnabled !== undefined) s.sun.nightWallpaperEnabled = patch.nightWallpaperEnabled === true
    if (patch.dayWallpaperMinutes !== undefined) s.sun.dayWallpaperMinutes = patch.dayWallpaperMinutes
    if (patch.nightWallpaperMinutes !== undefined) s.sun.nightWallpaperMinutes = patch.nightWallpaperMinutes
    if (patch.resetDayWallpaper) s.sun.dayWallpaperLastAt = Date.now()
    if (patch.resetNightWallpaper) s.sun.nightWallpaperLastAt = Date.now()
    if (patch.dayWallpaperEnabled === true) s.sun.dayWallpaperLastAt = Date.now()
    if (patch.nightWallpaperEnabled === true) s.sun.nightWallpaperLastAt = Date.now()
    next.schedule = Model.normalizeSchedule(s)
    next.wallpaperCycle = Model.normalizeWallpaperCycle(next.wallpaperCycle)
    next.themeCycle = Model.normalizeThemeCycle(next.themeCycle)
    var wallpaperOnly = patch.dayWallpaperEnabled !== undefined
      || patch.nightWallpaperEnabled !== undefined
      || patch.dayWallpaperMinutes !== undefined
      || patch.nightWallpaperMinutes !== undefined
      || patch.resetDayWallpaper || patch.resetNightWallpaper
    if (!wallpaperOnly) {
      root.manualOverride = false
      root.lastScheduledPeriod = ""
      root.wallpaperPeriodKey = ""
    }
    saveConfig(next)
  }

  function addScheduleRule(time, theme) {
    var next = Model.normalizeConfig(root.config)
    if (next.schedule.rules.length >= 24) return ""
    var id = Model.newRuleId(next.schedule.rules)
    next.schedule.rules.push({
      id: id,
      time: Model.normalizeHHMM(time, "07:00"),
      theme: Model.scheduleThemeKey(theme),
      enabled: true
    })
    next.schedule.enabled = true
    next.schedule.sun.enabled = false
    next.schedule.mode = "rules"
    next.wallpaperCycle.enabled = false
    root.manualOverride = false
    root.lastScheduledPeriod = ""
    saveConfig(next)
    return id
  }

  function removeScheduleRule(id) {
    var next = Model.normalizeConfig(root.config)
    next.schedule.rules = next.schedule.rules.filter(function(r) { return r.id !== id })
    root.manualOverride = false
    root.lastScheduledPeriod = ""
    saveConfig(next)
  }

  function updateScheduleRule(id, time, theme, enabled, wallpaper) {
    var next = Model.normalizeConfig(root.config)
    for (var i = 0; i < next.schedule.rules.length; i++) {
      if (next.schedule.rules[i].id !== id) continue
      if (time !== undefined && time !== "") next.schedule.rules[i].time = Model.normalizeHHMM(time, next.schedule.rules[i].time)
      if (theme !== undefined) {
        next.schedule.rules[i].theme = Model.scheduleThemeKey(theme)
        if (next.schedule.rules[i].theme) next.schedule.rules[i].folderId = ""
      }
      if (enabled !== undefined) next.schedule.rules[i].enabled = enabled === true
      if (wallpaper && typeof wallpaper === "object") {
        if (wallpaper.enabled !== undefined) {
          next.schedule.rules[i].wallpaperEnabled = wallpaper.enabled === true
          if (wallpaper.enabled === true) next.schedule.rules[i].wallpaperLastAt = Date.now()
        }
        if (wallpaper.minutes !== undefined) {
          next.schedule.rules[i].wallpaperMinutes = wallpaper.minutes
          next.schedule.rules[i].wallpaperLastAt = Date.now()
        }
        if (wallpaper.folderId !== undefined) {
          next.schedule.rules[i].folderId = String(wallpaper.folderId || "")
          if (wallpaper.folderId) next.schedule.rules[i].theme = ""
          next.schedule.rules[i].cycleLastAt = Date.now()
          next.schedule.rules[i].lastSlug = ""
        }
        if (wallpaper.cycleMinutes !== undefined) {
          next.schedule.rules[i].cycleMinutes = wallpaper.cycleMinutes
          next.schedule.rules[i].cycleLastAt = Date.now()
        }
      }
      break
    }
    if (!wallpaper) {
      root.manualOverride = false
      root.lastScheduledPeriod = ""
    }
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
    var pool = []
    for (var i = 0; i < cfg.favorites.length; i++) {
      if (cfg.favorites[i] !== root.currentSlug) pool.push(cfg.favorites[i])
    }
    if (!pool.length) pool = cfg.favorites.slice()
    if (!pool.length) return
    root.requestManualApply(pool[Math.floor(Math.random() * pool.length)])
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
    var folderSpec = Model.activeFolderCycle(cfg, root.solarPeriod)
    if (folderSpec.on) {
      var hold = Model.folderHoldSlug(cfg, root.themes, folderSpec.folderId, folderSpec.lastSlug, root.currentSlug)
      var entered = Date.now()
      saveConfig(Model.stampFolderCycle(cfg, folderSpec, {
        lastSlug: hold || folderSpec.lastSlug,
        cycleLastAt: entered,
        resetWallpaper: true
      }))
      root.lastScheduledPeriod = period
      root.lastAppliedBySchedule = hold || root.currentSlug || period
      if (hold && hold !== root.currentSlug) applyTheme(hold, true)
      return
    }
    var slug = Model.pickScheduledSlug(cfg, root.themes, period, root.currentSlug)
    if (!slug || slug === root.currentSlug) {
      root.lastScheduledPeriod = period
      return
    }
    root.lastScheduledPeriod = period
    root.lastAppliedBySchedule = slug
    applyTheme(slug, true)
  }

  function setWallpaperCycle(patch) {
    var next = Model.normalizeConfig(root.config)
    var w = next.wallpaperCycle
    if (patch.enabled !== undefined) w.enabled = patch.enabled === true
    if (patch.folderId !== undefined) w.folderId = String(patch.folderId || "")
    if (patch.minutes !== undefined) w.minutes = patch.minutes
    if (patch.resetStamp) {
      w.lastAt = Date.now()
      w.lastPath = ""
    }
    next.wallpaperCycle = Model.normalizeWallpaperCycle(w)
    saveConfig(next)
  }

  function setThemeCycle(patch) {
    var next = Model.normalizeConfig(root.config)
    var t = next.themeCycle
    if (patch.folderId !== undefined) t.folderId = String(patch.folderId || "")
    if (patch.minutes !== undefined) t.minutes = patch.minutes
    if (patch.wallpaperEnabled !== undefined) t.wallpaperEnabled = patch.wallpaperEnabled === true
    if (patch.wallpaperMinutes !== undefined) t.wallpaperMinutes = patch.wallpaperMinutes
    if (patch.seconds !== undefined) t.seconds = patch.seconds
    if (patch.wallpaperSeconds !== undefined) t.wallpaperSeconds = patch.wallpaperSeconds
    if (patch.resetStamp) {
      t.lastAt = Date.now()
      t.wallpaperLastAt = Date.now()
    }
    if (patch.wallpaperEnabled === true)
      t.wallpaperLastAt = Date.now()
    next.themeCycle = Model.normalizeThemeCycle(t)
    saveConfig(next)
  }

  function tickFolderSchedule() {
    if (root.otherSchedulerEnabled) return
    var cfg = Model.normalizeConfig(root.config)
    var mode = cfg.schedule.mode
    if (mode !== "rules" && mode !== "sun") return
    var period = Model.currentPeriod(cfg, root.solarPeriod)
    if (!period || period !== root.lastScheduledPeriod) return
    if (root.manualOverride && period === root.overridePeriod) return
    var spec = Model.activeFolderCycle(cfg, root.solarPeriod)
    if (!spec.on) return
    var now = Date.now()
    if (!spec.cycleLastAt) {
      saveConfig(Model.stampFolderCycle(cfg, spec, { cycleLastAt: now }))
      return
    }
    if ((now - spec.cycleLastAt) < Model.cycleIntervalMs(spec.minutes, 0, 30)) return
    var slugs = Model.cycleSlugs(cfg, root.themes, spec.folderId)
    if (!slugs.length) return
    var nextSlug = Model.nextWallpaper(slugs, spec.lastSlug || root.currentSlug)
    if (!nextSlug) return
    var changed = nextSlug !== root.currentSlug
    saveConfig(Model.stampFolderCycle(cfg, spec, {
      lastSlug: nextSlug,
      cycleLastAt: now,
      resetWallpaper: changed
    }))
    if (changed) applyTheme(nextSlug, true)
  }

  function tickThemeCycle() {
    if (root.otherSchedulerEnabled) return
    var cfg = Model.normalizeConfig(root.config)
    if (cfg.schedule.mode !== "themes") {
      root.tickFolderSchedule()
      return
    }
    var t = cfg.themeCycle
    if (!t.folderId) return
    var now = Date.now()
    if (!t.lastAt) {
      t.lastAt = now
      cfg.themeCycle = t
      saveConfig(cfg)
      return
    }
    if ((now - t.lastAt) < Model.cycleIntervalMs(t.minutes, t.seconds, 30)) return
    var usable = Model.cycleSlugs(cfg, root.themes, t.folderId)
    if (!usable.length) return
    var nextSlug = Model.nextWallpaper(usable, t.lastSlug || root.currentSlug)
    if (!nextSlug) return
    t.lastSlug = nextSlug
    t.lastAt = now
    t.wallpaperLastAt = now
    t.lastPath = ""
    cfg.themeCycle = t
    saveConfig(cfg)
    if (nextSlug !== root.currentSlug) applyTheme(nextSlug, true)
  }

  function tickWallpaper() {
    if (root.otherSchedulerEnabled) return
    var cfg = Model.normalizeConfig(root.config)
    var spec = Model.activeWallpaperSpec(cfg, root.solarPeriod)
    if (!spec.on) {
      root.wallpaperPeriodKey = ""
      return
    }
    if (spec.theme && spec.theme !== "__random_favorite__" && spec.theme !== root.currentSlug)
      return
    var now = Date.now()
    if (root.wallpaperPeriodKey !== spec.key) {
      root.wallpaperPeriodKey = spec.key
      saveConfig(Model.stampWallpaperLastAt(cfg, spec, now))
      return
    }
    var waitMs = Model.cycleIntervalMs(spec.minutes, spec.seconds, 5)
    if (!spec.lastAt) {
      saveConfig(Model.stampWallpaperLastAt(cfg, spec, now))
      return
    }
    if ((now - spec.lastAt) < waitMs) return
    saveConfig(Model.stampWallpaperLastAt(cfg, spec, now))
    root.applyNextBackground()
  }

  function missingThumbPaths(themes) {
    var list = Array.isArray(themes) ? themes : root.themes
    var need = []
    for (var i = 0; i < list.length; i++) {
      var preview = list[i].preview
      if (preview && (!list[i].thumbnail || list[i].thumbnail === list[i].preview)) {
        need.push(list[i].slug)
        need.push(preview)
      }
    }
    return need
  }

  function missingLivePosters(themes) {
    var list = Array.isArray(themes) ? themes : root.themes
    var need = []
    var seen = {}
    for (var i = 0; i < list.length; i++) {
      var bgs = list[i].backgrounds || []
      var posters = list[i].backgroundPosters || {}
      for (var j = 0; j < bgs.length; j++) {
        var path = bgs[j]
        if (!Model.isLivePath(path) || posters[path] || seen[path]) continue
        seen[path] = true
        need.push(path)
        if (need.length >= 40) return need
      }
    }
    return need
  }

  function ensureLivePosters(themes) {
    var need = missingLivePosters(themes)
    if (!need.length || posterProc.running) return
    var key = need.slice().sort().join("\n")
    if (key === root.lastPosterKey) return
    root.lastPosterKey = key
    var cmd = [root.scriptPath("warm-posters")]
    for (var i = 0; i < need.length; i++) cmd.push(need[i])
    posterProc.command = cmd
    posterProc.running = true
  }

  function ensureThumbs(themes) {
    var need = missingThumbPaths(themes)
    if (!need.length || root.thumbsWarming) return
    var key = need.slice().sort().join("\n")
    if (key === root.lastThumbKey) return
    root.lastThumbKey = key
    root.thumbsWarming = true
    var cmd = [root.scriptPath("warm-thumbs")]
    for (var t = 0; t < need.length; t++) cmd.push(need[t])
    thumbsProc.command = cmd
    thumbsProc.running = true
  }

  function setDefaultWallpaper(slug, path) {
    if (!Model.isValidSlug(slug) || !knownTheme(slug)) return
    var next = Model.normalizeConfig(root.config)
    var cur = next.defaultWallpapers[slug] || ""
    if (cur === path) delete next.defaultWallpapers[slug]
    else {
      if (!path || String(path).indexOf("..") >= 0) return
      var t = Model.themeBySlug(root.themes, slug)
      var bgs = t && t.backgrounds ? t.backgrounds : []
      var ok = false
      for (var i = 0; i < bgs.length; i++) if (bgs[i] === path) ok = true
      if (!ok) return
      next.defaultWallpapers[slug] = path
    }
    saveConfig(next)
    root.themes = Model.applyDefaultPreviews(root.themes, next)
    root.catalogRevision++
    root.ensureThumbs(root.themes)
  }

  function foldersChanged() {
    root.catalogRevision++
    root.lastThumbKey = ""
    root.ensureThumbs(root.themes)
  }

  function applyCycleState() {
    var next = Model.syncScheduleFolders(Model.syncThemeCycleState(root.config, root.themes, root.currentSlug))
    if (JSON.stringify(root.config.themeCycle || {}) !== JSON.stringify(next.themeCycle || {})
        || JSON.stringify(root.config.schedule || {}) !== JSON.stringify(next.schedule || {}))
      root.config = next
  }

  function syncCycles() {
    var next = Model.syncScheduleFolders(Model.syncThemeCycleState(root.config, root.themes, root.currentSlug))
    if (JSON.stringify(root.config.themeCycle || {}) !== JSON.stringify(next.themeCycle || {})
        || JSON.stringify(root.config.schedule || {}) !== JSON.stringify(next.schedule || {}))
      saveConfig(next)
    root.foldersChanged()
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
          var raw = String(text || "")
          if (raw.length > Model.maxCatalogChars()) return
          var parsed = Model.boundCatalog(JSON.parse(raw || "[]"))
          if (Array.isArray(parsed)) {
            var cur = ""
            for (var i = 0; i < parsed.length; i++) if (parsed[i].current) cur = parsed[i].slug
            if (cur) root.currentSlug = cur
            if (!(root.pendingConfigWrite || configWriter.running)) {
              var pruned = Model.pruneConfig(root.config, parsed)
              root.config = Model.syncScheduleFolders(Model.syncThemeCycleState(pruned, parsed, cur || root.currentSlug))
            }
            root.themes = Model.applyDefaultPreviews(parsed, root.config)
            root.catalogRevision++
            root.ensureThumbs(root.themes)
            root.ensureLivePosters(root.themes)
          }
        } catch (e) {
          console.warn("themebook catalog:", e)
        }
      }
    }
  }

  Process {
    id: posterProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").indexOf("updated") < 0) return
        root.lastPosterKey = ""
        root.reloadCatalog()
      }
    }
  }

  Process {
    id: thumbsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var list = root.themes.slice()
        var changed = false
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2) continue
          var slug = parts[0]
          var thumb = String(parts[1] || "")
          if (!slug || !thumb || thumb.indexOf("..") >= 0) continue
          for (var j = 0; j < list.length; j++) {
            if (list[j].slug !== slug) continue
            var t = {}
            for (var k in list[j]) t[k] = list[j][k]
            t.thumbnail = thumb
            list[j] = t
            changed = true
          }
        }
        if (changed) {
          root.themes = list
          root.catalogRevision++
        }
      }
    }
    onExited: root.thumbsWarming = false
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
    onExited: Qt.callLater(function() { root.flushConfigWrite() })
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      root.reloadCatalog()
      if (root.pendingApply) {
        var next = root.pendingApply
        var fromSchedule = root.pendingApplyFromSchedule
        root.pendingApply = ""
        root.pendingApplyFromSchedule = false
        root.applyTheme(next, fromSchedule)
        return
      }
      if (root.pendingBg) {
        var bg = root.pendingBg
        root.pendingBg = ""
        root.applyBackground(bg)
      } else if (root.pendingBgNext) {
        root.pendingBgNext = false
        root.applyNextBackground()
      }
    }
  }

  Process {
    id: bgProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.pendingBgNext) {
        root.pendingBgNext = false
        root.applyNextBackground()
      }
    }
  }

  Process {
    id: updateProc
    stdout: SplitParser {
      onRead: function(line) { root.ingestGitUpdateLine(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { root.ingestGitUpdateLine(line) }
    }
    onExited: function() {
      root.updateRunning = false
      root.updateOpen = true
      root.reloadCatalog()
    }
  }

  Process {
    id: removeProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      var slug = root.pendingRemoveSlug
      root.pendingRemoveSlug = ""
      if (code === 0 && slug)
        saveConfig(Model.dropThemeFromConfig(root.config, slug))
      root.reloadCatalog()
    }
  }

  Process {
    id: renameProc
    property string payload: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: renameProc.payload = String(text || "")
    }
    onExited: function(code) {
      var payload = renameProc.payload
      renameProc.payload = ""
      root.finishRename(code, payload)
    }
  }

  Process {
    id: fileProc
    property string payload: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: fileProc.payload = String(text || "")
    }
    onExited: function(code) {
      var payload = fileProc.payload
      fileProc.payload = ""
      root.finishBackground(code, payload)
    }
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
    id: pickerMenuProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
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

  Process {
    id: configReader
    command: [root.scriptPath("config"), "read"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pendingConfigWrite || configWriter.running) return
        try {
          var raw = String(text || "")
          if (raw.length > Model.maxConfigChars()) raw = "{}"
          root.config = Model.normalizeConfig(JSON.parse(raw || "{}"))
        } catch (e) {
          root.config = Model.defaultConfig()
        }
        root.syncPickerMenu()
      }
    }
  }

  Process {
    id: configStampProc
    command: [root.scriptPath("config"), "stamp"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s = String(text || "").trim()
        if (!s) return
        if (s !== root.configStamp) {
          root.configStamp = s
          root.reloadConfig()
        }
      }
    }
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

  Timer {
    interval: 2000
    running: true
    repeat: true
    property int scan: 0
    onTriggered: {
      var mode = (root.config.schedule && root.config.schedule.mode) || ""
      scan += 1
      if (scan % 2 === 0) configStampProc.running = true
      if ((mode === "themes" || mode === "wallpapers") && scan % 4 === 0)
        root.reloadCatalog()
      root.tickThemeCycle()
      root.tickWallpaper()
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
      root.applyTheme(slug, false)
      return "ok"
    }

    function makeFolder(name: string): string {
      return root.createFolder(name)
    }

    function moveTo(slug: string, folderId: string): string {
      root.addToFolder(slug, folderId)
      return folderId
    }

    function addTo(slug: string, folderId: string): string {
      root.addToFolder(slug, folderId)
      return folderId
    }

    function removeFrom(slug: string, folderId: string): string {
      root.removeFromFolder(slug, folderId)
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

    function setThemeCycleOpts(folder: string, wallpaperOn: string, themeSec: string, wallSec: string): string {
      root.setSchedule({ mode: "themes" })
      var next = Model.normalizeConfig(root.config)
      next.schedule.mode = "themes"
      next.themeCycle.folderId = folder || "favorites"
      next.themeCycle.wallpaperEnabled = wallpaperOn === "1" || wallpaperOn === "true"
      next.themeCycle.seconds = Number(themeSec)
      next.themeCycle.wallpaperSeconds = Number(wallSec)
      next.themeCycle.lastAt = Date.now()
      next.themeCycle.wallpaperLastAt = Date.now()
      next.themeCycle.lastSlug = root.currentSlug
      next.themeCycle.lastPath = ""
      root.saveConfig(next)
      return JSON.stringify(next.themeCycle)
    }

    function setScheduleTheme(which: string, slug: string): string {
      if (which === "night") root.setSchedule({ night: slug })
      else root.setSchedule({ day: slug })
      return which
    }

    function addRule(time: string, theme: string): string {
      return root.addScheduleRule(time, theme)
    }

    function dropRule(id: string): string {
      root.removeScheduleRule(id)
      return id
    }

    function collapse(id: string): string {
      root.toggleCollapsed(id)
      return id
    }

    function collapseAll(): string {
      root.setCollapsedAll(true)
      return "ok"
    }

    function expandAll(): string {
      root.setCollapsedAll(false)
      return "ok"
    }

    function setAsked(yes: string): string {
      root.setPickerAsked(yes === "1" || yes === "true")
      return "ok"
    }

    function pick(): string {
      return root.togglePicker()
    }

    function updateGit(): string {
      root.updateGitThemes()
      return "ok"
    }

    function showPanel(view: string): string {
      var v = String(view || "")
      if (v !== "schedule" && v !== "browse") return "rejected"
      root.requestPanelView(v)
      return v
    }

    function configJson(): string {
      return JSON.stringify(root.config)
    }
  }

  ThemePicker {
    id: pickerOverlay
    service: root
    shell: root.shell
    catalogOpen: false
  }

  Component.onCompleted: {
    root.reloadConfig()
    configStampProc.running = true
    root.reloadTools()
    root.reloadCatalog()
    root.installLaunchers()
    Qt.callLater(function() { root.tickSchedule() })
  }

  Component.onDestruction: root.restorePickerMenuNow()
}
