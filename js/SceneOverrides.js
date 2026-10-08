// Render settings a scene can override on top of its output's settings. Stored per scene as
// sceneSettings[sceneId].overrides; only the keys present there override, the rest are inherited.
var DEFS = [
    { key: "fps", label: "FPS", type: "slider", min: 10, max: 144, def: 30 },
    { key: "scaling", label: "Scaling", type: "combo", options: ["default", "stretch", "fit", "fill"], def: "default" },
    { key: "silent", label: "Silent Mode", type: "bool", def: true },
    { key: "volume", label: "Volume", type: "slider", min: 0, max: 100, def: 50 },
    { key: "disableParticles", label: "Disable Particles", type: "bool", def: false },
    { key: "downscaleToOutput", label: "Downscale to Screen", type: "bool", def: false },
    { key: "disableParallax", label: "Disable Parallax", type: "bool", def: false },
    { key: "noFullscreenPause", label: "No Fullscreen Pause", type: "bool", def: false },
    { key: "fullscreenPauseOnlyActive", label: "Pause Only Active", type: "bool", def: false },
    { key: "noAutoMute", label: "No Auto Mute", type: "bool", def: false },
    { key: "noAudioProcessing", label: "No Audio Processing", type: "bool", def: false },
    { key: "disableMouse", label: "Disable Mouse", type: "bool", def: false }
]

function def(key) {
    for (var i = 0; i < DEFS.length; i++) {
        if (DEFS[i].key === key) return DEFS[i]
    }
    return null
}

// drop unknown keys and undefined values so stale or malformed data never reaches the command line
function sanitize(overrides) {
    var out = {}
    if (!overrides || typeof overrides !== "object") return out
    for (var i = 0; i < DEFS.length; i++) {
        var k = DEFS[i].key
        if (overrides[k] !== undefined && overrides[k] !== null) out[k] = overrides[k]
    }
    return out
}

// output settings with the scene's overrides applied on top
function merge(outputSettings, overrides) {
    return Object.assign({}, outputSettings || {}, sanitize(overrides))
}

function formatValue(d, value) {
    if (d.type === "bool") return value ? "on" : "off"
    if (d.type === "slider") return String(Math.round(value))
    return String(value)
}

// "FPS 20, Scaling fill" style summary for the settings page
function summary(overrides) {
    var o = sanitize(overrides)
    var parts = []
    for (var i = 0; i < DEFS.length; i++) {
        var d = DEFS[i]
        if (o[d.key] !== undefined) parts.push(d.label + " " + formatValue(d, o[d.key]))
    }
    return parts.join(", ")
}
