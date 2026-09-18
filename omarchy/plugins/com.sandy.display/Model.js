function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

// Reduced aspect-ratio label for WxH. Common marketing names first
// (64:27 and 43:18 panels are both sold as 21:9); anything else falls
// back to the reduced ratio itself.
function aspectFor(width, height) {
  var w = Number(width), h = Number(height)
  if (!isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return ""
  function gcd(a, b) { while (b) { var t = a % b; a = b; b = t } return a }
  var g = gcd(Math.round(w), Math.round(h))
  var rw = Math.round(w) / g, rh = Math.round(h) / g
  if (rw === 16 && rh === 9) return "16:9"
  if ((rw === 16 && rh === 10) || (rw === 8 && rh === 5)) return "16:10"
  if ((rw === 64 && rh === 27) || (rw === 43 && rh === 18) || (rw === 21 && rh === 9)) return "21:9"
  if (rw === 32 && rh === 9) return "32:9"
  if (rw === 4 && rh === 3) return "4:3"
  if (rw === 5 && rh === 4) return "5:4"
  if (rw === 3 && rh === 2) return "3:2"
  if (rw === 1 && rh === 1) return "1:1"
  return rw + ":" + rh
}

// Unique resolutions for one output, largest first:
// [{ res: "1920x1080", aspect: "16:9", label: "1920x1080 (16:9)" }].
// Never throws; malformed input yields [].
function parseResolutions(monitorsJson, outputName) {
  var monitors = []
  try {
    monitors = monitorsJson ? JSON.parse(String(monitorsJson)) : []
  } catch (e) {
    return []
  }
  if (!Array.isArray(monitors)) return []

  var target = null
  for (var i = 0; i < monitors.length; i++) {
    if (monitors[i] && monitors[i].name === outputName) { target = monitors[i]; break }
  }
  if (!target || !Array.isArray(target.availableModes)) return []

  var seen = {}
  for (var k = 0; k < target.availableModes.length; k++) {
    var m = /^([0-9]+)x([0-9]+)@[0-9.]+Hz$/.exec(String(target.availableModes[k] || ""))
    if (m) seen[m[1] + "x" + m[2]] = [Number(m[1]), Number(m[2])]
  }

  return Object.keys(seen).map(function(res) {
    return { res: res, aspect: aspectFor(seen[res][0], seen[res][1]),
             label: res + " (" + aspectFor(seen[res][0], seen[res][1]) + ")" }
  }).sort(function(a, b) {
    var aw = Number(a.res.split("x")[0]), bw = Number(b.res.split("x")[0])
    if (bw !== aw) return bw - aw
    return Number(b.res.split("x")[1]) - Number(a.res.split("x")[1])
  })
}

// Parse `hyprctl monitors all -j` into refresh-rate options for one output
// at the GIVEN resolution: [{ hz, label, mode }], e.g. [{hz:60,label:"60Hz",...}].
// Never throws: malformed input yields []. Dedupes by rounded Hz so
// near-duplicate EDID entries (60.00 vs 59.94, 143.85 vs 144) collapse,
// then sorts ascending so 60..75..120..144..165..240+ gaming steps read clean.
//
// A 60Hz safe baseline is always guaranteed: if the given resolution has no
// 60Hz mode (e.g. 1152x864 exposing only 75Hz), the largest resolution that
// does is appended (clicking it applies that resolution at 60Hz — the
// helper resolves cross-resolution, and the panel adopts the new mode).
function parseRefreshRates(monitorsJson, outputName, width, height) {
  var monitors = []
  try {
    monitors = monitorsJson ? JSON.parse(String(monitorsJson)) : []
  } catch (e) {
    return []
  }
  if (!Array.isArray(monitors)) return []

  var target = null
  for (var i = 0; i < monitors.length; i++) {
    if (monitors[i] && monitors[i].name === outputName) { target = monitors[i]; break }
  }
  if (!target || !Array.isArray(target.availableModes)) return []

  var w = Number(width), h = Number(height)
  if (!isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return []

  var byHz = {}
  for (var k = 0; k < target.availableModes.length; k++) {
    var m = /^([0-9]+)x([0-9]+)@([0-9.]+)Hz$/.exec(String(target.availableModes[k] || ""))
    if (!m) continue
    if (Number(m[1]) !== w || Number(m[2]) !== h) continue
    var rr = parseFloat(m[3])
    if (!isFinite(rr) || rr <= 0) continue
    var hz = Math.round(rr)
    // Keep the entry closest to the integer Hz on near-duplicates.
    if (!byHz[hz] || Math.abs(rr - hz) < Math.abs(byHz[hz].rr - hz))
      byHz[hz] = { hz: hz, rr: rr, label: hz + "Hz", mode: m[1] + "x" + m[2] + "@" + m[3] }
  }

  // Guaranteed 60Hz baseline: largest resolution exposing a 60Hz mode,
  // appended when the selected resolution has none (clicking applies that
  // resolution at 60Hz via the helper's cross-resolution fallback).
  if (!byHz[60]) {
    var best60 = null
    for (var j = 0; j < target.availableModes.length; j++) {
      var g = /^([0-9]+)x([0-9]+)@([0-9.]+)Hz$/.exec(String(target.availableModes[j] || ""))
      if (!g) continue
      var grr = parseFloat(g[3])
      if (!isFinite(grr) || Math.round(grr) !== 60) continue
      var area = Number(g[1]) * Number(g[2])
      if (!best60 || area > best60.area
          || (area === best60.area && Math.abs(grr - 60) < Math.abs(best60.rr - 60)))
        best60 = { hz: 60, rr: grr, label: "60Hz",
                   mode: g[1] + "x" + g[2] + "@" + g[3], area: area }
    }
    if (best60) { delete best60.area; byHz[60] = best60 }
  }

  return Object.keys(byHz).map(function(k) { return byHz[k] })
    .sort(function(a, b) { return a.hz - b.hz })
}

// Detect the current layout/presentation mode from `hyprctl monitors all -j`:
// extend-right | extend-left | extend-above | extend-below | mirror |
// internal-only | external-only, or "" when undeterminable (single display,
// both sides disabled, ambiguous overlap). Mirrors the detection in
// bin/omarchy-display-mode.
function detectLayout(monitorsJson) {
  var monitors = []
  try {
    monitors = monitorsJson ? JSON.parse(String(monitorsJson)) : []
  } catch (e) {
    return ""
  }
  if (!Array.isArray(monitors)) return ""

  var internal = null, external = null
  for (var i = 0; i < monitors.length; i++) {
    var m = monitors[i]
    if (!m || !m.name) continue
    if (/^(eDP|LVDS|DSI)-/.test(m.name)) { if (!internal) internal = m }
    else if (!external) external = m
  }
  if (!internal || !external) return ""

  var intDis = internal.disabled === true
  var extDis = external.disabled === true
  if (extDis && !intDis) return "internal-only"
  if (intDis && !extDis) return "external-only"
  if (intDis && extDis) return ""

  function mirrored(n) {
    var v = n.mirrorOf
    return v !== undefined && v !== null && v !== "none" && String(v) !== ""
  }
  if (mirrored(external) || mirrored(internal)) return "mirror"

  var dx = Number(external.x) - Number(internal.x)
  var dy = Number(external.y) - Number(internal.y)
  if (dx > 0) return "extend-right"
  if (dx < 0) return "extend-left"
  if (dy < 0) return "extend-above"
  if (dy > 0) return "extend-below"
  return ""
}

// Index into a parseRefreshRates() list matching the live refresh rate
// (float, e.g. 60.317). -1 when nothing matches.
function matchingRefreshIndex(rates, currentRefresh) {
  var cur = Number(currentRefresh)
  if (!Array.isArray(rates) || !isFinite(cur)) return -1
  var best = -1, bestDist = Infinity
  for (var i = 0; i < rates.length; i++) {
    var d = Math.abs(Number(rates[i].hz) - cur)
    if (d < bestDist) { bestDist = d; best = i }
  }
  return bestDist <= 1 ? best : -1
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays,
    parseRefreshRates: parseRefreshRates,
    matchingRefreshIndex: matchingRefreshIndex,
    aspectFor: aspectFor,
    parseResolutions: parseResolutions,
    detectLayout: detectLayout
  }
}
