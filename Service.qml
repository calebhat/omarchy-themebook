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
  property string pendingBg: ""
  property bool pendingBgNext: false
  property string wallpaperPeriodKey: ""
  property string pendingManualSlug: ""
  signal requestPanelView(string name)
  property bool manualOverride: false
  property bool installing: false
  property bool thumbsWarming: false
  property string lastThumbKey: ""
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

  function saveConfig(next) {
    var pruned = Model.pruneConfig(next, root.themes)
    var payload = JSON.stringify(pruned)
    if (payload.length > Model.maxConfigChars()) return
    root.config = pruned
    configWriter.command = [scriptPath("config"), "write", payload]
    configWriter.running = true
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
    if (slug) applyTheme(slug, false)
  }

  function cancelManualApply() {
    root.pendingManualSlug = ""
    root.pendingBg = ""
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
    if (!root.pendingBg) {
      var def = Model.defaultWallpaper(next, Model.themeBySlug(root.themes, slug))
      if (def) root.pendingBg = def
    }
    if (fromSchedule) {
      root.manualOverride = false
    } else {
      next.schedule.enabled = false
      next.schedule.sun.enabled = false
      next.schedule.mode = "off"
      next.schedule = Model.normalizeSchedule(next.schedule)
      next.wallpaperCycle.enabled = false
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
  }

  function applyNextBackground() {
    if (applyProc.running || bgProc.running) {
      root.pendingBgNext = true
      return
    }
    bgProc.command = ["omarchy", "theme", "bg", "next"]
    bgProc.running = true
  }

  function applyBackgroundAndTheme(path) {
    var slug = Model.themeSlugForBackground(root.themes, path)
    if (slug && slug !== root.currentSlug) {
      root.pendingBg = path
      root.requestManualApply(slug)
      return
    }
    applyBackground(path)
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

  function openPicker() {
    pickerOverlay.open()
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
    var rec = order.indexOf("recents")
    var user = order.indexOf("user")
    var at = rec >= 0 ? rec + 1 : (user >= 0 ? user : order.length)
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
    next.picker.defaultFolder = String(id || "favorites")
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
    if (id === "user") return cfg.picker.includeUser
    if (id === "stock") return cfg.picker.includeStock
    for (var i = 0; i < cfg.folders.length; i++)
      if (cfg.folders[i].id === id) return cfg.folders[i].inPicker === true
    return false
  }

  function setCollapsedAll(collapsed) {
    var next = Model.normalizeConfig(root.config)
    var ids = ["favorites", "recents", "user", "stock", "hidden"]
    for (var i = 0; i < next.folders.length; i++) ids.push(next.folders[i].id)
    for (var j = 0; j < ids.length; j++) next.collapsed[ids[j]] = collapsed === true
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
    root.syncCycles()
  }

  function setSchedule(patch) {
    var next = Model.normalizeConfig(root.config)
    var s = next.schedule
    if (patch.mode === "off") {
      s.enabled = false
      s.sun.enabled = false
      s.mode = "off"
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
    if (patch.day !== undefined) s.sun.day = patch.day
    if (patch.night !== undefined) s.sun.night = patch.night
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
      if (theme !== undefined) next.schedule.rules[i].theme = Model.scheduleThemeKey(theme)
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

  function tickThemeCycle() {
    if (root.otherSchedulerEnabled) return
    var cfg = Model.normalizeConfig(root.config)
    if (cfg.schedule.mode !== "themes") return
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
    var next = Model.syncThemeCycleState(root.config, root.themes, root.currentSlug)
    if (JSON.stringify(root.config.themeCycle || {}) !== JSON.stringify(next.themeCycle || {}))
      root.config = next
  }

  function syncCycles() {
    var next = Model.syncThemeCycleState(root.config, root.themes, root.currentSlug)
    if (JSON.stringify(root.config.themeCycle || {}) !== JSON.stringify(next.themeCycle || {}))
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
            var pruned = Model.pruneConfig(root.config, parsed)
            root.config = Model.syncThemeCycleState(pruned, parsed, cur || root.currentSlug)
            root.themes = Model.applyDefaultPreviews(parsed, root.config)
            root.catalogRevision++
            root.ensureThumbs(root.themes)
          }
        } catch (e) {
          console.warn("themebook catalog:", e)
        }
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
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      root.reloadCatalog()
      if (root.pendingBg) {
        var bg = root.pendingBg
        root.pendingBg = ""
        root.applyBackground(bg)
      } else if (root.pendingBgNext) {
        root.pendingBgNext = false
        root.applyNextBackground()
      }
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
    onExited: {
      root.reloadCatalog()
      if (root.pendingBgNext) {
        root.pendingBgNext = false
        root.applyNextBackground()
      }
    }
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
      root.openPicker()
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
}
