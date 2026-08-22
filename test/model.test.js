#!/usr/bin/env node
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
eval(src + "\nmodule.exports = { defaultConfig, normalizeConfig, flatten, clockPeriod, bumpHHMM, pruneConfig, toggleInList, moveInList, isValidSlug, isReservedSection, currentPeriod, sanitizeFolderName, isCollapsed, activeRule, themeSlugForBackground, moveFolderIds, parseTimeInput, formatTimeDisplay, formatHourMinute, hourIsPm, applyMeridiem, parseClockTime, pickerSections, fuzzyMatch, minutesOf, moveIdBefore, wallpaperCyclePaths, nextWallpaper, cycleFolderChoices, isReorderableSection, themeWallpaperPaths, cycleIntervalMs, cycleSlugs, syncThemeCycleState, activeWallpaperSpec, isScheduleActive, scheduleActiveLabel, defaultWallpaper, applyDefaultPreviews, boundCatalog }")

const m = module.exports
const cfg = m.normalizeConfig({
  favorites: ["sakura-mochi", "sakura-mochi", "", "../etc"],
  folders: [
    { id: "dark", name: "Dark", themes: ["nord", "missing"] },
    { id: "favorites", name: "Nope", themes: ["nord"] }
  ],
  schedule: { mode: "clock", day: "../x", night: "__random_favorite__" }
})
if (cfg.favorites.join() !== "sakura-mochi") throw new Error("dedupe favorites")
if (cfg.folders.length !== 1 || cfg.folders[0].id !== "dark") throw new Error("reserved folder id")
if (cfg.schedule.day !== "") throw new Error("bad schedule day")
if (cfg.schedule.night !== "__random_favorite__") throw new Error("keep random night")
if (cfg.collapsed.recents !== true) throw new Error("recents collapsed by default")
if (m.clockPeriod(8 * 60, "07:00", "19:00") !== "day") throw new Error("day period")
if (m.clockPeriod(20 * 60, "07:00", "19:00") !== "night") throw new Error("night period")
if (m.bumpHHMM("07:00", 15) !== "07:15") throw new Error("bump")
if (m.isValidSlug("../etc")) throw new Error("reject traversal slug")
if (m.isValidSlug("tokyo-night") !== true) throw new Error("accept slug")
if (!m.isReservedSection("user")) throw new Error("reserved user")
const clipped = m.sanitizeFolderName("  lots   of space  and a very long name that should clip")
if (clipped.length > 40 || clipped.indexOf("  ") >= 0 || clipped.indexOf("lots of space") !== 0)
  throw new Error("folder name " + JSON.stringify(clipped))

const themes = [
  { slug: "sakura-mochi", name: "Sakura Mochi", source: "user", mode: "dark" },
  { slug: "nord", name: "Nord", source: "stock", mode: "dark" },
  { slug: "white", name: "White", source: "stock", mode: "light" }
]
const emptyPrune = m.pruneConfig(cfg, [])
if (emptyPrune.favorites.join() !== "sakura-mochi") throw new Error("empty catalog must not wipe favorites")
const pruned = m.pruneConfig(cfg, themes)
if (pruned.folders[0].themes.join() !== "nord") throw new Error("prune missing")
const darkHeader = m.flatten(themes, pruned, "all", "").find(r => r.id === "dark")
if (!darkHeader || darkHeader.themeCount !== 1) throw new Error("folder count")
const rows = m.flatten(themes, pruned, "all", "")
if (rows[0].rowType !== "header" || rows[0].id !== "favorites") throw new Error("favorites first")
if (rows[0].themeCount !== 1) throw new Error("favorites count " + rows[0].themeCount)
const withRecents = m.normalizeConfig(Object.assign({}, pruned, { recents: ["nord"] }))
const recRows = m.flatten(themes, withRecents, "all", "")
if (recRows[0].id !== "favorites") throw new Error("favorites still first with recents")
const recHeader = recRows.find(r => r.id === "recents")
if (!recHeader || recHeader.collapsed !== true) throw new Error("recents collapsed")
if (recHeader.themeCount !== 1) throw new Error("recents count")
if (recHeader.draggable !== true) throw new Error("recents draggable")
const recIds = recRows.filter(r => r.rowType === "header").map(r => r.id)
if (recIds[0] !== "favorites" || recIds[1] !== "recents") throw new Error("recents after favorites " + recIds.join())
if (recRows.some(r => r.rowType === "theme" && r.section === "recents")) throw new Error("collapsed recents hide themes")
const emptyRec = m.flatten(themes, m.normalizeConfig({}), "all", "")
if (!emptyRec.some(r => r.id === "recents")) throw new Error("recents header when empty")
if (!emptyRec.find(r => r.id === "favorites").draggable) throw new Error("favorites draggable")
if (!emptyRec.find(r => r.id === "user").draggable) throw new Error("user draggable")
if (!emptyRec.find(r => r.id === "stock").draggable) throw new Error("stock draggable")
const reordered = m.normalizeConfig({ sectionOrder: ["stock", "user", "recents", "favorites"] })
const reorderedIds = m.flatten(themes, reordered, "all", "").filter(r => r.rowType === "header").map(r => r.id)
if (reorderedIds.slice(0, 4).join() !== "stock,user,recents,favorites") throw new Error("persist section order " + reorderedIds.join())
if (m.moveIdBefore(["favorites", "recents", "user"], "user", "favorites").join() !== "user,favorites,recents") throw new Error("moveIdBefore")
const cyclePaths = m.wallpaperCyclePaths(
  { wallpaperCycle: { folderId: "favorites" }, favorites: ["nord"] },
  [{ slug: "nord", backgrounds: ["/a.png", "/b.png"] }]
)
if (cyclePaths.join() !== "/a.png,/b.png") throw new Error("cycle paths")
if (m.nextWallpaper(cyclePaths, "/a.png") !== "/b.png") throw new Error("next wallpaper")
if (m.nextWallpaper(cyclePaths, "/b.png") !== "/a.png") throw new Error("cycle wrap")
if (!m.cycleFolderChoices({}).some(f => f.id === "recents" && f.name === "Recents")) throw new Error("cycle recents choice")
const oldCycle = m.normalizeConfig({ schedule: { mode: "cycle" }, wallpaperCycle: { enabled: false, folderId: "favorites", minutes: 10 } })
if (oldCycle.schedule.mode !== "wallpapers") throw new Error("migrate cycle to wallpapers " + oldCycle.schedule.mode)
if (oldCycle.wallpaperCycle.enabled !== true) throw new Error("wallpaper mode enables wallpaper")
const themeMode = m.normalizeConfig({ schedule: { mode: "themes" }, themeCycle: { folderId: "favorites", minutes: 15, wallpaperEnabled: true } })
if (themeMode.schedule.mode !== "themes") throw new Error("keep theme cycle")
if (themeMode.themeCycle.minutes !== 15) throw new Error("theme minutes")
if (!themeMode.themeCycle.wallpaperEnabled) throw new Error("nested wallpaper flag")
const wpOnly = m.themeWallpaperPaths([{ slug: "nord", backgrounds: ["/a.png", "/b.png"] }], "nord")
if (wpOnly.join() !== "/a.png,/b.png") throw new Error("theme wallpaper paths")
const rulesMode = m.normalizeConfig({ schedule: { mode: "rules", enabled: true }, wallpaperCycle: { enabled: true } })
if (rulesMode.wallpaperCycle.enabled) throw new Error("timed mode disables wallpaper cycle")
if (m.cycleIntervalMs(5, 10, 5) !== 10000) throw new Error("seconds override")
if (m.cycleIntervalMs(2, 0, 30) !== 120000) throw new Error("minutes when no seconds")
const cycleThemes = [{ slug: "nord" }, { slug: "gruv" }, { slug: "rose" }]
const added = m.cycleSlugs({ favorites: ["nord", "gruv", "rose"], hidden: [] }, cycleThemes, "favorites")
if (added.join() !== "nord,gruv,rose") throw new Error("cycle includes new favorites")
const synced = m.syncThemeCycleState(
  { schedule: { mode: "themes" }, themeCycle: { folderId: "favorites", lastSlug: "gone" }, favorites: ["gruv", "rose"] },
  cycleThemes,
  "gruv"
)
if (synced.themeCycle.lastSlug !== "gruv") throw new Error("drop lastSlug not in folder")
const goneFolder = m.syncThemeCycleState(
  { schedule: { mode: "themes" }, themeCycle: { folderId: "folder-9", lastSlug: "nord" }, folders: [] },
  cycleThemes,
  "nord"
)
if (goneFolder.themeCycle.folderId !== "") throw new Error("clear deleted cycle folder")
const timedWp = m.normalizeConfig({
  schedule: { mode: "rules", enabled: true, rules: [{ id: "rule-1", time: "00:00", theme: "nord", enabled: true, wallpaperEnabled: true, wallpaperMinutes: 7 }] }
})
const spec = m.activeWallpaperSpec(timedWp, "day", 0)
if (!spec.on || spec.store !== "rule" || spec.minutes !== 7 || spec.theme !== "nord") throw new Error("timed theme wallpaper spec " + JSON.stringify(spec))
const sunWp = m.normalizeConfig({
  schedule: { mode: "sun", sun: { enabled: true, day: "nord", night: "gruv", dayWallpaperEnabled: true, dayWallpaperMinutes: 3 } }
})
const sunSpec = m.activeWallpaperSpec(sunWp, "day", 0)
if (!sunSpec.on || sunSpec.store !== "sun-day" || sunSpec.minutes !== 3) throw new Error("sun wallpaper spec")
if (m.activeWallpaperSpec(sunWp, "night", 0).on) throw new Error("night wallpaper off")
if (!m.isScheduleActive({ schedule: { mode: "rules", enabled: true } })) throw new Error("rules active")
if (m.isScheduleActive({ schedule: { mode: "off" } })) throw new Error("off not active")
if (m.scheduleActiveLabel({ schedule: { mode: "rules", enabled: true } }) !== "Timed Themes") throw new Error("active label")
const keptMin = m.normalizeConfig({
  schedule: { mode: "rules", enabled: true, rules: [{ id: "rule-1", time: "07:00", theme: "nord", wallpaperEnabled: false, wallpaperMinutes: 11 }] }
})
if (keptMin.schedule.rules[0].wallpaperMinutes !== 11) throw new Error("keep wallpaper minutes while off")
const themed = { slug: "nord", preview: "/stock.png", backgrounds: ["/a.png", "/b.png"] }
const cfgDef = m.normalizeConfig({ defaultWallpapers: { nord: "/b.png" } })
if (m.defaultWallpaper(cfgDef, themed) !== "/b.png") throw new Error("default wallpaper")
if (m.applyDefaultPreviews([themed], cfgDef)[0].preview !== "/b.png") throw new Error("preview uses default")
const prunedDef = m.pruneConfig({ defaultWallpapers: { nord: "/missing.png", gone: "/a.png" } }, [themed])
if (prunedDef.defaultWallpapers.nord || prunedDef.defaultWallpapers.gone) throw new Error("prune bad defaults")
const many = []
for (let i = 0; i < 300; i++) {
  const bgs = []
  for (let j = 0; j < 60; j++) bgs.push("/bg" + j + ".png")
  many.push({ slug: "t" + i, name: "n".repeat(200), backgrounds: bgs })
}
const capped = m.boundCatalog(many)
if (capped.length !== 256) throw new Error("bound catalog length " + capped.length)
if (capped[0].name.length > 80) throw new Error("bound name")
if (capped[0].backgrounds.length !== 48) throw new Error("bound bgs " + capped[0].backgrounds.length)
if (m.activeWallpaperSpec(keptMin, "day", 8 * 60).on) throw new Error("wallpaper off while rule wallpaper disabled")
const expanded = m.normalizeConfig(Object.assign({}, withRecents, { collapsed: { recents: false } }))
const expRows = m.flatten(themes, expanded, "all", "")
if (!expRows.some(r => r.rowType === "theme" && r.section === "recents" && r.slug === "nord")) throw new Error("expand recents")

const hiddenCfg = m.normalizeConfig({ hidden: ["nord"], folders: [{ id: "dark", name: "Dark", themes: ["nord"] }] })
const hiddenRows = m.flatten(themes, hiddenCfg, "hidden", "")
if (!hiddenRows.some(r => r.rowType === "theme" && r.slug === "nord")) throw new Error("hidden-in-folder must appear")

if (m.currentPeriod({ schedule: { mode: "off" } }, "day", 8 * 60) !== "") throw new Error("off period")
const clockCfg = { schedule: { mode: "clock", dayAt: "07:00", nightAt: "19:00", day: "white", night: "nord" } }
if (m.currentPeriod(clockCfg, "night", 8 * 60) !== "rule-day") throw new Error("clock active rule " + m.currentPeriod(clockCfg, "night", 8 * 60))
if (m.currentPeriod({ schedule: { mode: "sun", day: "white", night: "nord" } }, "night", 8 * 60) !== "night") throw new Error("sun period")
const multi = m.normalizeConfig({
  schedule: {
    enabled: true,
    rules: [
      { id: "a", time: "06:00", theme: "white" },
      { id: "b", time: "12:00", theme: "nord" },
      { id: "c", time: "22:00", theme: "sakura-mochi" }
    ]
  }
})
if (m.activeRule(multi.schedule.rules, 13 * 60).id !== "b") throw new Error("midday rule")
if (m.activeRule(multi.schedule.rules, 23 * 60).id !== "c") throw new Error("late rule")
if (m.activeRule(multi.schedule.rules, 1 * 60).id !== "c") throw new Error("overnight wraps to last")
const moved = m.moveFolderIds(
  [{ id: "one", name: "One", themes: [] }, { id: "two", name: "Two", themes: [] }, { id: "three", name: "Three", themes: [] }],
  "three",
  "one"
)
if (moved.map(f => f.id).join() !== "three,one,two") throw new Error("drag reorder " + moved.map(f => f.id).join())
if (m.themeSlugForBackground([{ slug: "nord", backgrounds: ["/tmp/a.png"] }], "/tmp/a.png") !== "nord") throw new Error("bg theme")
if (m.parseTimeInput("7pm") !== "19:00") throw new Error("parse 7pm")
if (m.parseTimeInput("7:15 AM") !== "07:15") throw new Error("parse 7:15 am")
if (m.parseTimeInput("19:30") !== "19:30") throw new Error("parse 24h")
if (m.parseTimeInput("25:00") !== "") throw new Error("reject bad hour")
if (m.formatTimeDisplay("19:00", true) !== "7:00 PM") throw new Error("format 12h " + m.formatTimeDisplay("19:00", true))
if (m.formatTimeDisplay("19:00", false) !== "19:00") throw new Error("format 24h")
if (m.formatHourMinute("19:00", true) !== "7:00") throw new Error("hour minute")
if (!m.hourIsPm("19:00") || m.hourIsPm("07:00")) throw new Error("hourIsPm")
if (m.applyMeridiem("07:00", true) !== "19:00") throw new Error("apply pm")
if (m.applyMeridiem("19:00", false) !== "07:00") throw new Error("apply am")
if (m.parseClockTime("7:15", true, true) !== "19:15") throw new Error("parse clock pm")
if (m.parseClockTime("19:15", false, false) !== "19:15") throw new Error("parse clock 24")
if (m.minutesOf("07:00") >= m.minutesOf("19:30")) throw new Error("minutesOf order")
const pickRec = m.pickerSections({ recents: ["nord"], picker: { includeRecents: true, includeFavorites: false } }, themes)
if (!pickRec.some(s => s.id === "recents" && s.themes.indexOf("nord") >= 0)) throw new Error("recents picker section")
if (!m.fuzzyMatch("skm", "Sakura Mochi", "sakura-mochi")) throw new Error("fuzzy skm")
if (!m.fuzzyMatch("tokyo", "Tokyo Night", "tokyo-night")) throw new Error("fuzzy tokyo")
if (m.fuzzyMatch("zzzz", "Nord", "nord")) throw new Error("fuzzy miss")
console.log("model ok")
