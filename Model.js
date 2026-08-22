.pragma library

function defaultConfig() {
  return {
    favorites: [],
    hidden: [],
    recents: [],
    folders: [],
    collapsed: { recents: true },
    clock12: false,
    picker: {
      asked: true,
      replaceDefault: true,
      defaultFolder: "favorites",
      includeFavorites: true,
      includeUser: false,
      includeStock: false,
      includeRecents: false,
      lastFolder: "",
      lastSlug: "",
      lastFocusRow: "themes"
    },
    sectionOrder: ["favorites", "recents", "user", "stock"],
    schedule: {
      enabled: false,
      rules: [],
      sun: { enabled: false, day: "", night: "" },
      mode: "off"
    },
    wallpaperCycle: {
      enabled: false,
      folderId: "",
      minutes: 5,
      seconds: 0,
      lastPath: "",
      lastAt: 0
    },
    defaultWallpapers: {},
    themeCycle: {
      folderId: "",
      minutes: 30,
      seconds: 0,
      lastSlug: "",
      lastAt: 0,
      wallpaperEnabled: false,
      wallpaperMinutes: 5,
      wallpaperSeconds: 0,
      lastPath: "",
      wallpaperLastAt: 0
    }
  }
}

var RESERVED_SECTIONS = {
  recents: true,
  favorites: true,
  user: true,
  stock: true,
  hidden: true,
  all: true
}

function isValidSlug(slug) {
  var s = String(slug || "")
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(s) && s.indexOf("..") < 0
}

function isReservedSection(id) {
  return !!RESERVED_SECTIONS[String(id || "")]
}

function asStringArray(value) {
  if (!Array.isArray(value)) return []
  var out = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    var s = String(value[i] || "").trim()
    if (!isValidSlug(s) || seen[s]) continue
    seen[s] = true
    out.push(s)
  }
  return out
}

function normalizeFolders(raw) {
  if (!Array.isArray(raw)) return []
  var out = []
  var seenId = {}
  for (var i = 0; i < raw.length; i++) {
    var f = raw[i] || {}
    var id = String(f.id || "").trim()
    var name = String(f.name || "").trim().slice(0, 40)
    if (!id) id = "folder-" + (i + 1)
    if (isReservedSection(id) || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id) || id.indexOf("..") >= 0)
      continue
    if (!name) name = id
    if (seenId[id]) continue
    seenId[id] = true
    out.push({
      id: id,
      name: name,
      themes: asStringArray(f.themes),
      inPicker: f.inPicker === true
    })
  }
  return out
}

function normalizeRule(raw, index) {
  var r = raw && typeof raw === "object" ? raw : {}
  var id = String(r.id || "").trim()
  if (!id || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id) || id.indexOf("..") >= 0)
    id = "rule-" + (index + 1)
  var lastAt = Number(r.wallpaperLastAt)
  if (!isFinite(lastAt) || lastAt < 0) lastAt = 0
  return {
    id: id,
    time: normalizeHHMM(r.time || r.at, "07:00"),
    theme: scheduleThemeKey(r.theme),
    enabled: r.enabled !== false,
    wallpaperEnabled: r.wallpaperEnabled === true,
    wallpaperMinutes: clampMinutes(r.wallpaperMinutes, 5),
    wallpaperLastAt: lastAt
  }
}

function newRuleId(rules) {
  var n = 1
  var ids = {}
  var list = Array.isArray(rules) ? rules : []
  for (var i = 0; i < list.length; i++) ids[list[i].id] = true
  while (ids["rule-" + n]) n++
  return "rule-" + n
}

function normalizeSchedule(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  var rules = []
  var seen = {}
  if (Array.isArray(s.rules) && s.rules.length) {
    for (var i = 0; i < s.rules.length && rules.length < 24; i++) {
      var rule = normalizeRule(s.rules[i], i)
      if (seen[rule.id]) rule.id = newRuleId(rules)
      seen[rule.id] = true
      rules.push(rule)
    }
  } else if (s.dayAt || s.nightAt || s.day || s.night) {
    rules.push(normalizeRule({ id: "rule-day", time: s.dayAt || "07:00", theme: s.day, enabled: s.mode === "clock" }, 0))
    rules.push(normalizeRule({ id: "rule-night", time: s.nightAt || "19:30", theme: s.night, enabled: s.mode === "clock" }, 1))
  }
  var sunSrc = s.sun && typeof s.sun === "object" ? s.sun : {}
  var rawMode = String(s.mode || "")
  if (rawMode === "cycle" || rawMode === "wallpaper") rawMode = "wallpapers"
  if (rawMode === "theme") rawMode = "themes"
  var cycling = rawMode === "themes" || rawMode === "wallpapers"
  var sunEnabled = !cycling && (sunSrc.enabled === true || rawMode === "sun")
  var enabled = false
  if (cycling || rawMode === "off") enabled = false
  else if (rawMode === "clock" || rawMode === "rules") enabled = true
  else if (s.enabled === true) enabled = true
  if (sunEnabled) enabled = false
  var mode = "off"
  if (rawMode === "themes" || rawMode === "wallpapers") mode = rawMode
  else if (sunEnabled) mode = "sun"
  else if (enabled) mode = "rules"
  return {
    enabled: enabled,
    rules: rules,
    sun: {
      enabled: sunEnabled,
      day: scheduleThemeKey(sunSrc.day || s.day),
      night: scheduleThemeKey(sunSrc.night || s.night),
      dayWallpaperEnabled: sunSrc.dayWallpaperEnabled === true,
      nightWallpaperEnabled: sunSrc.nightWallpaperEnabled === true,
      dayWallpaperMinutes: clampMinutes(sunSrc.dayWallpaperMinutes, 5),
      nightWallpaperMinutes: clampMinutes(sunSrc.nightWallpaperMinutes, 5),
      dayWallpaperLastAt: Number(sunSrc.dayWallpaperLastAt) > 0 ? Number(sunSrc.dayWallpaperLastAt) : 0,
      nightWallpaperLastAt: Number(sunSrc.nightWallpaperLastAt) > 0 ? Number(sunSrc.nightWallpaperLastAt) : 0
    },
    mode: mode,
    day: scheduleThemeKey(s.day),
    night: scheduleThemeKey(s.night),
    dayAt: normalizeHHMM(s.dayAt, "07:00"),
    nightAt: normalizeHHMM(s.nightAt, "19:30")
  }
}

function normalizeCollapsed(raw) {
  var out = { recents: true }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
  var keys = Object.keys(raw)
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    if (!k || k.indexOf("..") >= 0) continue
    out[k] = raw[k] === true
  }
  if (raw.recents === false) out.recents = false
  return out
}

function isCollapsed(config, id) {
  var c = config && config.collapsed ? config.collapsed : { recents: true }
  if (id === "recents") return c.recents !== false
  return c[id] === true
}

function normalizeHHMM(value, fallback) {
  var m = String(value || "").match(/^(\d{1,2}):(\d{2})$/)
  if (!m) return fallback
  var h = Number(m[1])
  var min = Number(m[2])
  if (h < 0 || h > 23 || min < 0 || min > 59) return fallback
  return (h < 10 ? "0" : "") + h + ":" + (min < 10 ? "0" : "") + min
}

function scheduleThemeKey(value) {
  var s = String(value || "")
  if (s === "__random_favorite__") return s
  return isValidSlug(s) ? s : ""
}

function minutesOf(hhmm) {
  var p = String(hhmm || "00:00").split(":")
  return Number(p[0]) * 60 + Number(p[1])
}

function fuzzyMatch(query, name, slug) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return true
  var compact = q.replace(/\s+/g, "")
  var hay = (String(name || "") + " " + String(slug || "")).toLowerCase()
  if (hay.indexOf(q) >= 0) return true
  var j = 0
  for (var i = 0; i < hay.length && j < compact.length; i++) {
    if (hay.charAt(i) === compact.charAt(j)) j++
  }
  return j === compact.length
}

function parseTimeInput(raw) {
  var s = String(raw || "").trim().toLowerCase().replace(/\s+/g, "")
  if (!s) return ""
  var am = false
  var pm = false
  if (s.slice(-2) === "am") { am = true; s = s.slice(0, -2) }
  else if (s.slice(-2) === "pm") { pm = true; s = s.slice(0, -2) }
  s = s.replace(".", ":")
  var h = 0
  var min = 0
  var m = s.match(/^(\d{1,2}):(\d{2})$/)
  if (m) {
    h = Number(m[1])
    min = Number(m[2])
  } else if (/^\d{3,4}$/.test(s)) {
    if (s.length === 3) { h = Number(s[0]); min = Number(s.slice(1)) }
    else { h = Number(s.slice(0, 2)); min = Number(s.slice(2)) }
  } else if (/^\d{1,2}$/.test(s)) {
    h = Number(s)
    min = 0
  } else return ""
  if (min < 0 || min > 59) return ""
  if (am || pm) {
    if (h < 1 || h > 12) return ""
    if (h === 12) h = 0
    if (pm) h += 12
  } else if (h < 0 || h > 23) return ""
  return (h < 10 ? "0" : "") + h + ":" + (min < 10 ? "0" : "") + min
}

function formatHourMinute(hhmm, clock12) {
  var t = normalizeHHMM(hhmm, "")
  if (!t) return ""
  if (!clock12) return t
  var p = t.split(":")
  var h = Number(p[0])
  var h12 = h % 12
  if (h12 === 0) h12 = 12
  return h12 + ":" + p[1]
}

function hourIsPm(hhmm) {
  var t = normalizeHHMM(hhmm, "")
  if (!t) return false
  return Number(t.split(":")[0]) >= 12
}

function applyMeridiem(hhmm, pm) {
  var t = normalizeHHMM(hhmm, "12:00")
  var p = t.split(":")
  var h = Number(p[0]) % 12
  if (pm) h += 12
  return (h < 10 ? "0" : "") + h + ":" + p[1]
}

function parseClockTime(raw, clock12, pm) {
  var s = String(raw || "").replace(/\s*(am|pm)\s*/ig, "").trim()
  if (!clock12) return parseTimeInput(s)
  return parseTimeInput(s + (pm ? "pm" : "am"))
}

function formatTimeDisplay(hhmm, clock12) {
  var t = formatHourMinute(hhmm, clock12)
  if (!t) return ""
  if (!clock12) return t
  return t + (hourIsPm(hhmm) ? " PM" : " AM")
}

function pickerSections(config, themes) {
  var cfg = normalizeConfig(config)
  var out = []
  function add(id, name, slugs) {
    var kept = []
    for (var i = 0; i < slugs.length; i++) {
      if (themeBySlug(themes, slugs[i])) kept.push(slugs[i])
    }
    out.push({ id: id, name: name, themes: kept })
  }
  var def = cfg.picker.defaultFolder
  var seen = {}
  function maybe(id, name, slugs, include) {
    if (!include) return
    if (seen[id]) return
    seen[id] = true
    add(id, name, slugs)
  }
  function slugsFor(id) {
    if (id === "favorites") return cfg.favorites.slice()
    if (id === "recents") return cfg.recents.slice()
    if (id === "user") {
      var u = []
      for (var i = 0; i < themes.length; i++) if (themes[i].source === "user") u.push(themes[i].slug)
      return u
    }
    if (id === "stock") {
      var s = []
      for (var j = 0; j < themes.length; j++) if (themes[j].source === "stock") s.push(themes[j].slug)
      return s
    }
    for (var f = 0; f < cfg.folders.length; f++)
      if (cfg.folders[f].id === id) return cfg.folders[f].themes.slice()
    return []
  }
  function nameFor(id) {
    if (id === "favorites") return "Favorites"
    if (id === "recents") return "Recents"
    if (id === "user") return "User"
    if (id === "stock") return "Stock"
    for (var f = 0; f < cfg.folders.length; f++)
      if (cfg.folders[f].id === id) return cfg.folders[f].name
    return id
  }
  function includeFlag(id) {
    if (id === "favorites") return cfg.picker.includeFavorites
    if (id === "recents") return cfg.picker.includeRecents
    if (id === "user") return cfg.picker.includeUser
    if (id === "stock") return cfg.picker.includeStock
    for (var f = 0; f < cfg.folders.length; f++)
      if (cfg.folders[f].id === id) return cfg.folders[f].inPicker === true
    return false
  }
  if (def) maybe(def, nameFor(def), slugsFor(def), true)
  for (var k = 0; k < cfg.sectionOrder.length; k++) {
    var sid = cfg.sectionOrder[k]
    maybe(sid, nameFor(sid), slugsFor(sid), includeFlag(sid))
  }
  return out
}

function bumpHHMM(value, deltaMinutes) {
  var mins = (minutesOf(value) + Number(deltaMinutes) + 24 * 60) % (24 * 60)
  var h = Math.floor(mins / 60)
  var min = mins % 60
  min = Math.round(min / 15) * 15
  if (min === 60) { min = 0; h = (h + 1) % 24 }
  return (h < 10 ? "0" : "") + h + ":" + (min < 10 ? "0" : "") + min
}

function normalizeConfig(raw) {
  var c = raw && typeof raw === "object" ? raw : {}
  var cfg = defaultConfig()
  cfg.favorites = asStringArray(c.favorites)
  cfg.hidden = asStringArray(c.hidden)
  cfg.recents = asStringArray(c.recents).slice(0, 8)
  cfg.folders = normalizeFolders(c.folders)
  cfg.collapsed = normalizeCollapsed(c.collapsed)
  cfg.clock12 = c.clock12 === true
  cfg.picker = normalizePicker(c.picker)
  cfg.sectionOrder = normalizeSectionOrder(c.sectionOrder, cfg.folders)
  cfg.schedule = normalizeSchedule(c.schedule)
  cfg.wallpaperCycle = normalizeWallpaperCycle(c.wallpaperCycle)
  cfg.themeCycle = normalizeThemeCycle(c.themeCycle)
  cfg.defaultWallpapers = normalizeDefaultWallpapers(c.defaultWallpapers)
  cfg.wallpaperCycle.enabled = cfg.schedule.mode === "wallpapers"
  return cfg
}

function normalizeDefaultWallpapers(raw) {
  var src = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
  var out = {}
  for (var k in src) {
    if (!isValidSlug(k)) continue
    var p = String(src[k] || "")
    if (!p || p.indexOf("..") >= 0) continue
    out[k] = p
  }
  return out
}

function defaultWallpaper(config, theme) {
  if (!theme) return ""
  var slug = typeof theme === "string" ? theme : String(theme.slug || "")
  var map = (config && config.defaultWallpapers) || {}
  var path = String(map[slug] || "")
  if (!path || path.indexOf("..") >= 0) return ""
  var bgs = theme && theme.backgrounds ? theme.backgrounds : []
  if (typeof theme === "string") return path
  for (var i = 0; i < bgs.length; i++) if (bgs[i] === path) return path
  return ""
}

function applyDefaultPreviews(themes, config) {
  var list = Array.isArray(themes) ? themes : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var src = list[i]
    var t = {}
    for (var k in src) t[k] = src[k]
    var path = defaultWallpaper(config, t)
    if (path) {
      t.preview = path
      t.thumbnail = path
    }
    out.push(t)
  }
  return out
}

function normalizePicker(raw) {
  var p = raw && typeof raw === "object" ? raw : {}
  var def = String(p.defaultFolder || "favorites")
  if (!def) def = "favorites"
  return {
    asked: p.asked === true,
    replaceDefault: p.replaceDefault !== false,
    defaultFolder: def,
    includeFavorites: p.includeFavorites !== false,
    includeUser: p.includeUser === true,
    includeStock: p.includeStock === true,
    includeRecents: p.includeRecents === true,
    lastFolder: String(p.lastFolder || ""),
    lastSlug: String(p.lastSlug || ""),
    lastFocusRow: p.lastFocusRow === "folders" ? "folders" : "themes"
  }
}

function defaultSectionOrder(folders) {
  var order = ["favorites", "recents"]
  var list = Array.isArray(folders) ? folders : []
  for (var i = 0; i < list.length; i++) order.push(list[i].id)
  order.push("user", "stock")
  return order
}

function normalizeSectionOrder(raw, folders) {
  var allowed = { favorites: true, recents: true, user: true, stock: true }
  var list = Array.isArray(folders) ? folders : []
  for (var i = 0; i < list.length; i++) allowed[list[i].id] = true
  var out = []
  var seen = {}
  var src = Array.isArray(raw) ? raw : []
  for (var j = 0; j < src.length; j++) {
    var id = String(src[j] || "").trim()
    if (!allowed[id] || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  var defaults = defaultSectionOrder(list)
  for (var k = 0; k < defaults.length; k++) {
    if (seen[defaults[k]]) continue
    seen[defaults[k]] = true
    out.push(defaults[k])
  }
  return out
}

function clampMinutes(value, fallback) {
  var minutes = Math.round(Number(value))
  if (!isFinite(minutes) || minutes < 1) minutes = fallback
  if (minutes > 1440) minutes = 1440
  return minutes
}

function clampSeconds(value) {
  var seconds = Math.round(Number(value))
  if (!isFinite(seconds) || seconds < 10) return 0
  if (seconds > 1440 * 60) seconds = 1440 * 60
  return seconds
}

function cycleIntervalMs(minutes, seconds, fallbackMinutes) {
  var s = clampSeconds(seconds)
  if (s >= 10) return s * 1000
  return clampMinutes(minutes, fallbackMinutes) * 60000
}

function normalizeCycleFolderId(value) {
  var folderId = String(value || "").trim()
  if (folderId && (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(folderId) || folderId.indexOf("..") >= 0))
    return ""
  return folderId
}

function normalizeWallpaperCycle(raw) {
  var w = raw && typeof raw === "object" ? raw : {}
  var lastPath = String(w.lastPath || "")
  if (lastPath.indexOf("..") >= 0) lastPath = ""
  var lastAt = Number(w.lastAt)
  if (!isFinite(lastAt) || lastAt < 0) lastAt = 0
  return {
    enabled: w.enabled === true,
    folderId: normalizeCycleFolderId(w.folderId),
    minutes: clampMinutes(w.minutes, 5),
    seconds: clampSeconds(w.seconds),
    lastPath: lastPath,
    lastAt: lastAt
  }
}

function normalizeThemeCycle(raw) {
  var t = raw && typeof raw === "object" ? raw : {}
  var lastPath = String(t.lastPath || "")
  if (lastPath.indexOf("..") >= 0) lastPath = ""
  var lastAt = Number(t.lastAt)
  if (!isFinite(lastAt) || lastAt < 0) lastAt = 0
  var wallpaperLastAt = Number(t.wallpaperLastAt)
  if (!isFinite(wallpaperLastAt) || wallpaperLastAt < 0) wallpaperLastAt = 0
  return {
    folderId: normalizeCycleFolderId(t.folderId),
    minutes: clampMinutes(t.minutes, 30),
    seconds: clampSeconds(t.seconds),
    lastSlug: scheduleThemeKey(t.lastSlug),
    lastAt: lastAt,
    wallpaperEnabled: t.wallpaperEnabled === true,
    wallpaperMinutes: clampMinutes(t.wallpaperMinutes, 5),
    wallpaperSeconds: clampSeconds(t.wallpaperSeconds),
    lastPath: lastPath,
    wallpaperLastAt: wallpaperLastAt
  }
}

function isScheduleActive(config) {
  var mode = (normalizeConfig(config).schedule || {}).mode
  return mode === "rules" || mode === "sun" || mode === "themes" || mode === "wallpapers"
}

function scheduleActiveLabel(config) {
  var mode = (normalizeConfig(config).schedule || {}).mode
  if (mode === "rules") return "Timed Themes"
  if (mode === "sun") return "Sunrise / sunset"
  if (mode === "themes") return "Theme cycle"
  if (mode === "wallpapers") return "Wallpaper cycle"
  return ""
}

function isReorderableSection(id) {
  var s = String(id || "")
  return s === "favorites" || s === "recents" || s === "user" || s === "stock" || !isReservedSection(s)
}

function moveIdBefore(ids, fromId, toId) {
  var out = Array.isArray(ids) ? ids.slice() : []
  var from = out.indexOf(fromId)
  var to = out.indexOf(toId)
  if (from < 0 || to < 0 || from === to) return Array.isArray(ids) ? ids.slice() : []
  out.splice(from, 1)
  to = out.indexOf(toId)
  if (to < 0) return Array.isArray(ids) ? ids.slice() : []
  out.splice(to, 0, fromId)
  return out
}

function sectionDisplayName(config, id) {
  if (id === "favorites") return "Favorites"
  if (id === "recents") return "Recents"
  if (id === "user") return "User"
  if (id === "stock") return "Stock"
  var folders = (config && config.folders) || []
  for (var i = 0; i < folders.length; i++)
    if (folders[i].id === id) return folders[i].name
  return id
}

function cycleSlugs(config, themes, folderId) {
  var cfg = normalizeConfig(config)
  var raw = slugsInSection(cfg, themes, folderId)
  var out = []
  var seen = {}
  for (var i = 0; i < raw.length; i++) {
    var s = raw[i]
    if (!s || seen[s]) continue
    if (cfg.hidden.indexOf(s) >= 0) continue
    if (!themeBySlug(themes, s)) continue
    seen[s] = true
    out.push(s)
  }
  return out
}

function syncThemeCycleState(config, themes, currentSlug) {
  var cfg = normalizeConfig(config)
  var t = cfg.themeCycle
  var folderStillThere = false
  if (t.folderId === "favorites" || t.folderId === "recents" || t.folderId === "user" || t.folderId === "stock")
    folderStillThere = true
  else {
    for (var i = 0; i < cfg.folders.length; i++)
      if (cfg.folders[i].id === t.folderId) folderStillThere = true
  }
  if (!folderStillThere) t.folderId = ""
  var slugs = t.folderId ? cycleSlugs(cfg, themes, t.folderId) : []
  if (t.lastSlug && slugs.indexOf(t.lastSlug) < 0)
    t.lastSlug = (currentSlug && slugs.indexOf(currentSlug) >= 0) ? currentSlug : (slugs[0] || "")
  cfg.themeCycle = t
  return cfg
}

function slugsInSection(config, themes, id) {
  var cfg = normalizeConfig(config)
  if (id === "favorites") return cfg.favorites.slice()
  if (id === "recents") return cfg.recents.slice()
  if (id === "user") {
    var u = []
    for (var i = 0; i < themes.length; i++) if (themes[i].source === "user") u.push(themes[i].slug)
    return u
  }
  if (id === "stock") {
    var s = []
    for (var j = 0; j < themes.length; j++) if (themes[j].source === "stock") s.push(themes[j].slug)
    return s
  }
  for (var f = 0; f < cfg.folders.length; f++)
    if (cfg.folders[f].id === id) return cfg.folders[f].themes.slice()
  return []
}

function wallpaperCyclePaths(config, themes, onlySlug) {
  var cfg = normalizeConfig(config)
  var slugs = slugsInSection(cfg, themes, cfg.wallpaperCycle.folderId)
  var paths = []
  var seen = {}
  for (var i = 0; i < slugs.length; i++) {
    if (onlySlug && slugs[i] !== onlySlug) continue
    var t = themeBySlug(themes, slugs[i])
    var bgs = t && t.backgrounds ? t.backgrounds : []
    for (var j = 0; j < bgs.length; j++) {
      var p = String(bgs[j] || "")
      if (!p || p.indexOf("..") >= 0 || seen[p]) continue
      seen[p] = true
      paths.push(p)
    }
  }
  return paths
}

function nextWallpaper(paths, lastPath) {
  if (!paths || !paths.length) return ""
  var i = paths.indexOf(lastPath)
  return paths[(i + 1) % paths.length]
}

function themeWallpaperPaths(themes, slug) {
  var t = themeBySlug(themes, slug)
  var bgs = t && t.backgrounds ? t.backgrounds : []
  var paths = []
  var seen = {}
  for (var i = 0; i < bgs.length; i++) {
    var p = String(bgs[i] || "")
    if (!p || p.indexOf("..") >= 0 || seen[p]) continue
    seen[p] = true
    paths.push(p)
  }
  return paths
}

function cycleFolderChoices(config) {
  var cfg = normalizeConfig(config)
  var out = []
  for (var i = 0; i < cfg.sectionOrder.length; i++) {
    var id = cfg.sectionOrder[i]
    out.push({ id: id, name: sectionDisplayName(cfg, id) })
  }
  return out
}

function knownSlugs(themes) {
  var set = {}
  for (var i = 0; i < themes.length; i++) set[themes[i].slug] = true
  return set
}

function pruneConfig(config, themes) {
  var cfg = normalizeConfig(config)
  if (!themes || !themes.length) return cfg
  var known = knownSlugs(themes)
  function keep(list) {
    var out = []
    for (var i = 0; i < list.length; i++) if (known[list[i]]) out.push(list[i])
    return out
  }
  cfg.favorites = keep(cfg.favorites)
  cfg.hidden = keep(cfg.hidden)
  cfg.recents = keep(cfg.recents)
  for (var f = 0; f < cfg.folders.length; f++)
    cfg.folders[f].themes = keep(cfg.folders[f].themes)
  if (cfg.schedule.day && !known[cfg.schedule.day] && cfg.schedule.day !== "__random_favorite__")
    cfg.schedule.day = ""
  if (cfg.schedule.night && !known[cfg.schedule.night] && cfg.schedule.night !== "__random_favorite__")
    cfg.schedule.night = ""
  for (var r = 0; r < cfg.schedule.rules.length; r++) {
    var th = cfg.schedule.rules[r].theme
    if (th && th !== "__random_favorite__" && !known[th]) cfg.schedule.rules[r].theme = ""
  }
  if (cfg.schedule.sun.day && cfg.schedule.sun.day !== "__random_favorite__" && !known[cfg.schedule.sun.day])
    cfg.schedule.sun.day = ""
  if (cfg.schedule.sun.night && cfg.schedule.sun.night !== "__random_favorite__" && !known[cfg.schedule.sun.night])
    cfg.schedule.sun.night = ""
  if (cfg.picker.lastSlug && !known[cfg.picker.lastSlug]) cfg.picker.lastSlug = ""
  var defaults = {}
  for (var slug in cfg.defaultWallpapers) {
    if (!known[slug]) continue
    var t = themeBySlug(themes, slug)
    var path = cfg.defaultWallpapers[slug]
    var bgs = t && t.backgrounds ? t.backgrounds : []
    var ok = false
    for (var b = 0; b < bgs.length; b++) if (bgs[b] === path) ok = true
    if (ok) defaults[slug] = path
  }
  cfg.defaultWallpapers = defaults
  return cfg
}

function folderOfSlug(config, slug) {
  for (var i = 0; i < config.folders.length; i++) {
    var themes = config.folders[i].themes
    for (var j = 0; j < themes.length; j++) {
      if (themes[j] === slug) return config.folders[i].id
    }
  }
  return ""
}

function themeBySlug(themes, slug) {
  for (var i = 0; i < themes.length; i++) {
    if (themes[i].slug === slug) return themes[i]
  }
  return null
}

function matchesFilter(theme, config, filter, query) {
  if (!theme) return false
  var q = String(query || "").trim().toLowerCase()
  if (q && String(theme.name).toLowerCase().indexOf(q) < 0 && String(theme.slug).toLowerCase().indexOf(q) < 0)
    return false
  var hidden = config.hidden.indexOf(theme.slug) >= 0
  if (filter === "hidden") return hidden
  if (hidden) return false
  if (filter === "user") return theme.source === "user"
  if (filter === "stock") return theme.source === "stock"
  if (filter === "light") return theme.mode === "light"
  if (filter === "dark") return theme.mode === "dark"
  if (filter === "favorites") return config.favorites.indexOf(theme.slug) >= 0
  return true
}

function flatten(themes, config, filter, query) {
  var rows = []
  var shown = {}
  var cfg = normalizeConfig(config)

  function pushTheme(slug, section) {
    var t = themeBySlug(themes, slug)
    if (!t || shown[section + ":" + slug]) return
    if (!matchesFilter(t, cfg, filter, query)) return
    shown[section + ":" + slug] = true
    var row = {}
    for (var key in t) row[key] = t[key]
    row.section = section
    row.rowType = "theme"
    rows.push(row)
  }

  function pushHeader(id, title, draggable, count) {
    rows.push({
      rowType: "header",
      id: id,
      title: title,
      section: id,
      collapsed: isCollapsed(cfg, id),
      draggable: draggable === true,
      themeCount: Number(count) || 0
    })
  }

  if (filter === "hidden") {
    var hiddenHits = []
    for (var h = 0; h < themes.length; h++) {
      if (matchesFilter(themes[h], cfg, filter, query)) hiddenHits.push(themes[h].slug)
    }
    pushHeader("hidden", "Hidden", false, hiddenHits.length)
    if (!isCollapsed(cfg, "hidden")) {
      for (var hi = 0; hi < hiddenHits.length; hi++) pushTheme(hiddenHits[hi], "hidden")
    }
    return rows
  }

  var assigned = {}
  for (var a = 0; a < cfg.folders.length; a++) {
    for (var b = 0; b < cfg.folders[a].themes.length; b++)
      assigned[cfg.folders[a].themes[b]] = true
  }

  function hitsFor(id) {
    var slugs = slugsInSection(cfg, themes, id)
    var hits = []
    for (var i = 0; i < slugs.length; i++) {
      if ((id === "user" || id === "stock") && assigned[slugs[i]]) continue
      var t = themeBySlug(themes, slugs[i])
      if (t && matchesFilter(t, cfg, filter, query)) hits.push(slugs[i])
    }
    return hits
  }

  for (var so = 0; so < cfg.sectionOrder.length; so++) {
    var id = cfg.sectionOrder[so]
    var hits = hitsFor(id)
    if (query && !hits.length && id !== "favorites" && id !== "recents") continue
    pushHeader(id, sectionDisplayName(cfg, id), isReorderableSection(id), hits.length)
    if (!isCollapsed(cfg, id)) {
      for (var x = 0; x < hits.length; x++) pushTheme(hits[x], id)
    }
  }

  return rows
}

function toggleInList(list, slug) {
  var out = list.slice()
  var i = out.indexOf(slug)
  if (i >= 0) out.splice(i, 1)
  else out.unshift(slug)
  return out
}

function moveInList(list, slug, delta) {
  var out = list.slice()
  var i = out.indexOf(slug)
  if (i < 0) return out
  var j = i + delta
  if (j < 0 || j >= out.length) return out
  out.splice(i, 1)
  out.splice(j, 0, slug)
  return out
}

function pushRecent(list, slug) {
  var out = [slug]
  for (var i = 0; i < list.length; i++) {
    if (list[i] !== slug) out.push(list[i])
  }
  return out.slice(0, 8)
}

function sanitizeFolderName(name) {
  var s = String(name || "").replace(/\s+/g, " ").trim().slice(0, 40)
  return s || "Folder"
}

function newFolderId(folders) {
  var n = 1
  var ids = {}
  for (var i = 0; i < folders.length; i++) ids[folders[i].id] = true
  while (ids["folder-" + n] || isReservedSection("folder-" + n)) n++
  return "folder-" + n
}

function activeRule(rules, nowMinutes) {
  var list = []
  var raw = Array.isArray(rules) ? rules : []
  for (var i = 0; i < raw.length; i++) {
    if (raw[i].enabled === false) continue
    if (!raw[i].theme) continue
    list.push(raw[i])
  }
  if (!list.length) return null
  list.sort(function(a, b) { return minutesOf(a.time) - minutesOf(b.time) })
  var mins = nowMinutes
  if (mins === undefined || mins === null) {
    var now = new Date()
    mins = now.getHours() * 60 + now.getMinutes()
  }
  var chosen = list[list.length - 1]
  for (var j = 0; j < list.length; j++) {
    if (minutesOf(list[j].time) <= mins) chosen = list[j]
  }
  return chosen
}

function currentPeriod(config, solarPeriod, nowMinutes) {
  var cfg = normalizeConfig(config)
  if (cfg.schedule.sun && cfg.schedule.sun.enabled) {
    if (solarPeriod === "day" || solarPeriod === "night") return solarPeriod
    return ""
  }
  if (!cfg.schedule.enabled) return ""
  var rule = activeRule(cfg.schedule.rules, nowMinutes)
  return rule ? rule.id : ""
}

function themeSlugForBackground(themes, path) {
  if (!path) return ""
  for (var i = 0; i < themes.length; i++) {
    var bgs = themes[i].backgrounds || []
    for (var j = 0; j < bgs.length; j++) {
      if (bgs[j] === path) return themes[i].slug
    }
  }
  return ""
}

function moveFolderIds(folders, fromId, toId) {
  var ids = []
  for (var i = 0; i < folders.length; i++) ids.push(folders[i].id)
  var from = ids.indexOf(fromId)
  var to = ids.indexOf(toId)
  if (from < 0 || to < 0 || from === to) return folders
  ids.splice(from, 1)
  to = ids.indexOf(toId)
  ids.splice(to, 0, fromId)
  var map = {}
  for (var j = 0; j < folders.length; j++) map[folders[j].id] = folders[j]
  var out = []
  for (var k = 0; k < ids.length; k++) if (map[ids[k]]) out.push(map[ids[k]])
  return out
}

function headerIds(rows) {
  var ids = []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].rowType === "header") ids.push(rows[i].id)
  }
  return ids
}

function clockPeriod(nowMinutes, dayAt, nightAt) {
  var day = minutesOf(dayAt)
  var night = minutesOf(nightAt)
  if (day === night) return "day"
  if (day < night) {
    if (nowMinutes >= day && nowMinutes < night) return "day"
    return "night"
  }
  if (nowMinutes >= day || nowMinutes < night) return "day"
  return "night"
}

function pickScheduledSlug(config, themes, period, currentSlug) {
  var cfg = normalizeConfig(config)
  var key = ""
  if (cfg.schedule.sun && cfg.schedule.sun.enabled) {
    key = period === "night" ? cfg.schedule.sun.night : cfg.schedule.sun.day
  } else {
    var rule = null
    for (var r = 0; r < cfg.schedule.rules.length; r++) {
      if (cfg.schedule.rules[r].id === period) rule = cfg.schedule.rules[r]
    }
    if (!rule) rule = activeRule(cfg.schedule.rules)
    key = rule ? rule.theme : ""
  }
  if (key === "__random_favorite__") {
    var pool = []
    for (var i = 0; i < config.favorites.length; i++) {
      if (config.favorites[i] !== currentSlug) pool.push(config.favorites[i])
    }
    if (!pool.length) pool = config.favorites.slice()
    if (!pool.length) return ""
    return pool[Math.floor(Math.random() * pool.length)]
  }
  if (themeBySlug(themes, key)) return key
  return ""
}

function activeWallpaperSpec(config, solarPeriod, nowMinutes) {
  var cfg = normalizeConfig(config)
  var mode = cfg.schedule.mode
  if (mode === "wallpapers") {
    return {
      on: true,
      minutes: cfg.wallpaperCycle.minutes,
      seconds: cfg.wallpaperCycle.seconds,
      lastAt: cfg.wallpaperCycle.lastAt,
      store: "wallpaperCycle",
      key: "wallpaperCycle",
      theme: ""
    }
  }
  if (mode === "themes" && cfg.themeCycle.wallpaperEnabled) {
    return {
      on: true,
      minutes: cfg.themeCycle.wallpaperMinutes,
      seconds: cfg.themeCycle.wallpaperSeconds,
      lastAt: cfg.themeCycle.wallpaperLastAt,
      store: "themeCycle",
      key: "themeCycle",
      theme: ""
    }
  }
  if (mode === "rules") {
    var rule = activeRule(cfg.schedule.rules, nowMinutes)
    if (rule && rule.enabled && rule.wallpaperEnabled) {
      return {
        on: true,
        minutes: rule.wallpaperMinutes,
        seconds: 0,
        lastAt: rule.wallpaperLastAt,
        store: "rule",
        ruleId: rule.id,
        key: "rule:" + rule.id,
        theme: rule.theme
      }
    }
  }
  if (mode === "sun") {
    if (solarPeriod === "day" && cfg.schedule.sun.dayWallpaperEnabled) {
      return {
        on: true,
        minutes: cfg.schedule.sun.dayWallpaperMinutes,
        seconds: 0,
        lastAt: cfg.schedule.sun.dayWallpaperLastAt,
        store: "sun-day",
        key: "sun-day",
        theme: cfg.schedule.sun.day
      }
    }
    if (solarPeriod === "night" && cfg.schedule.sun.nightWallpaperEnabled) {
      return {
        on: true,
        minutes: cfg.schedule.sun.nightWallpaperMinutes,
        seconds: 0,
        lastAt: cfg.schedule.sun.nightWallpaperLastAt,
        store: "sun-night",
        key: "sun-night",
        theme: cfg.schedule.sun.night
      }
    }
  }
  return { on: false, key: "", store: "", minutes: 5, seconds: 0, lastAt: 0, theme: "" }
}

function stampWallpaperLastAt(config, spec, now) {
  var cfg = normalizeConfig(config)
  if (!spec || !spec.store) return cfg
  if (spec.store === "wallpaperCycle") cfg.wallpaperCycle.lastAt = now
  else if (spec.store === "themeCycle") cfg.themeCycle.wallpaperLastAt = now
  else if (spec.store === "rule") {
    for (var i = 0; i < cfg.schedule.rules.length; i++) {
      if (cfg.schedule.rules[i].id === spec.ruleId) {
        cfg.schedule.rules[i].wallpaperLastAt = now
        break
      }
    }
  } else if (spec.store === "sun-day") cfg.schedule.sun.dayWallpaperLastAt = now
  else if (spec.store === "sun-night") cfg.schedule.sun.nightWallpaperLastAt = now
  return cfg
}
