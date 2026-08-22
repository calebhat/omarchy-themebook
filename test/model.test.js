#!/usr/bin/env node
const fs = require("fs")
const path = require("path")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
eval(src + "\nmodule.exports = { defaultConfig, normalizeConfig, flatten, clockPeriod, bumpHHMM, pruneConfig, toggleInList, moveInList, isValidSlug, isReservedSection, currentPeriod, sanitizeFolderName }")

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
const rows = m.flatten(themes, pruned, "all", "")
if (rows[0].rowType !== "header" || rows[0].id !== "favorites") throw new Error("favorites first")

const hiddenCfg = m.normalizeConfig({ hidden: ["nord"], folders: [{ id: "dark", name: "Dark", themes: ["nord"] }] })
const hiddenRows = m.flatten(themes, hiddenCfg, "hidden", "")
if (!hiddenRows.some(r => r.rowType === "theme" && r.slug === "nord")) throw new Error("hidden-in-folder must appear")

if (m.currentPeriod({ schedule: { mode: "off" } }, "day", 8 * 60) !== "") throw new Error("off period")
if (m.currentPeriod({ schedule: { mode: "clock", dayAt: "07:00", nightAt: "19:00" } }, "night", 8 * 60) !== "day") throw new Error("clock ignores solar")
if (m.currentPeriod({ schedule: { mode: "sun" } }, "night", 8 * 60) !== "night") throw new Error("sun period")
console.log("model ok")
