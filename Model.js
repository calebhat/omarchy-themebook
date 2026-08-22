.pragma library

function defaultConfig() {
  return {
    favorites: [],
    hidden: [],
    recents: [],
    folders: [],
    schedule: {
      mode: "off",
      day: "",
      night: "",
      dayAt: "07:00",
      nightAt: "19:30"
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
    out.push({ id: id, name: name, themes: asStringArray(f.themes) })
  }
  return out
}

function normalizeSchedule(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  var mode = String(s.mode || "off")
  if (mode !== "clock" && mode !== "sun") mode = "off"
  return {
    mode: mode,
    day: scheduleThemeKey(s.day),
    night: scheduleThemeKey(s.night),
    dayAt: normalizeHHMM(s.dayAt, "07:00"),
    nightAt: normalizeHHMM(s.nightAt, "19:30")
  }
}

function normalizeHHMM(value, fallback) {
  var m = String(value || "").match(/^(\d{1,2}):(\d{2})$/)
  if (!m) return fallback
  var h = Number(m[1])
  var min = Number(m[2])
  if (h < 0 || h > 23 || min < 0 || min > 59) return fallback
  if (min % 15 !== 0) min = Math.round(min / 15) * 15
  if (min === 60) { min = 0; h = (h + 1) % 24 }
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
  cfg.schedule = normalizeSchedule(c.schedule)
  return cfg
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

  function pushHeader(id, title) {
    rows.push({ rowType: "header", id: id, title: title, section: id })
  }

  if (filter !== "hidden") {
    if (cfg.recents.length && (filter === "all" || !filter)) {
      var recents = []
      for (var r = 0; r < cfg.recents.length; r++) {
        var rt = themeBySlug(themes, cfg.recents[r])
        if (rt && matchesFilter(rt, cfg, filter, query)) recents.push(cfg.recents[r])
      }
      if (recents.length) {
        pushHeader("recents", "Recents")
        for (var ri = 0; ri < recents.length; ri++) pushTheme(recents[ri], "recents")
      }
    }

    var favs = []
    for (var fi = 0; fi < cfg.favorites.length; fi++) {
      var ft = themeBySlug(themes, cfg.favorites[fi])
      if (ft && matchesFilter(ft, cfg, filter, query)) favs.push(cfg.favorites[fi])
    }
    pushHeader("favorites", "Favorites")
    for (var fj = 0; fj < favs.length; fj++) pushTheme(favs[fj], "favorites")

    for (var fo = 0; fo < cfg.folders.length; fo++) {
      var folder = cfg.folders[fo]
      var folderHits = []
      for (var k = 0; k < folder.themes.length; k++) {
        var kt = themeBySlug(themes, folder.themes[k])
        if (kt && matchesFilter(kt, cfg, filter, query)) folderHits.push(folder.themes[k])
      }
      if (folderHits.length || !query) {
        pushHeader(folder.id, folder.name)
        for (var kh = 0; kh < folderHits.length; kh++) pushTheme(folderHits[kh], folder.id)
      }
    }
  }

  var assigned = {}
  if (filter !== "hidden") {
    for (var a = 0; a < cfg.folders.length; a++) {
      for (var b = 0; b < cfg.folders[a].themes.length; b++)
        assigned[cfg.folders[a].themes[b]] = true
    }
  }

  var userLeft = []
  var stockLeft = []
  for (var t = 0; t < themes.length; t++) {
    var theme = themes[t]
    if (assigned[theme.slug]) continue
    if (!matchesFilter(theme, cfg, filter, query)) continue
    if (filter === "hidden") {
      userLeft.push(theme.slug)
      continue
    }
    if (theme.source === "user") userLeft.push(theme.slug)
    else stockLeft.push(theme.slug)
  }

  if (userLeft.length) {
    pushHeader(filter === "hidden" ? "hidden" : "user", filter === "hidden" ? "Hidden" : "User")
    for (var u = 0; u < userLeft.length; u++) pushTheme(userLeft[u], filter === "hidden" ? "hidden" : "user")
  }
  if (stockLeft.length) {
    pushHeader("stock", "Stock")
    for (var s = 0; s < stockLeft.length; s++) pushTheme(stockLeft[s], "stock")
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

function currentPeriod(config, solarPeriod, nowMinutes) {
  var cfg = normalizeConfig(config)
  if (cfg.schedule.mode === "off") return ""
  if (cfg.schedule.mode === "sun") {
    if (solarPeriod === "day" || solarPeriod === "night") return solarPeriod
    return ""
  }
  var mins = nowMinutes
  if (mins === undefined || mins === null) {
    var now = new Date()
    mins = now.getHours() * 60 + now.getMinutes()
  }
  return clockPeriod(mins, cfg.schedule.dayAt, cfg.schedule.nightAt)
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
  var key = period === "night" ? config.schedule.night : config.schedule.day
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
