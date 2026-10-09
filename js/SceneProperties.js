// Scene properties straight from project.json (the engine's --list-properties loses their order,
// combo labels and "condition"s), and the scene's layers from the patched engine's --list-layers.

// "ui_browse_properties_scheme_color" -> "Scheme color"; plain labels are kept as they are
function prettyLabel(text) {
    var s = String(text || "")
    var m = s.match(/^ui_(?:browse_properties|editor_properties|editor_effect|editor)_(.+?)(?:_title)?$/)
    if (!m) return s
    var words = m[1].replace(/_/g, " ")
    return words.charAt(0).toUpperCase() + words.substring(1)
}

// WE colors are "r g b" (0..1, sometimes 0..255) strings; the plugin stores [r, g, b(, a)] in 0..1
function parseColor(value) {
    if (Array.isArray(value)) return value.map(Number)
    var parts = String(value || "").trim().split(/[\s,]+/).map(Number).filter(function(n) { return !isNaN(n) })
    if (parts.length < 3) return [1, 1, 1]
    if (parts[0] > 1 || parts[1] > 1 || parts[2] > 1) parts = parts.map(function(n, i) { return i < 3 ? n / 255 : n })
    return parts
}

function normalizeValue(type, value) {
    if (type === "bool") return value === true || value === 1 || value === "1" || value === "true"
    if (type === "slider") return Number(value) || 0
    if (type === "color") return parseColor(value)
    if (type === "combo" || type === "textinput") return value === undefined || value === null ? "" : String(value)
    return value
}

var SUPPORTED_TYPES = { bool: true, slider: true, combo: true, color: true, textinput: true, text: true }

// [{ name, type, label, value, options: [{ label, value }], min, max, step, precision, condition }],
// in the order Wallpaper Engine shows them. Types this UI can't edit (files, folders...) are left out.
function parseProjectProperties(projectText) {
    var project
    try {
        project = JSON.parse(projectText)
    } catch (e) {
        return []
    }
    var props = (project && project.general && project.general.properties) || {}
    var list = []
    for (var name in props) {
        var p = props[name] || {}
        var type = String(p.type || "").toLowerCase()
        if (!SUPPORTED_TYPES[type]) continue
        // the scheme color only tints Wallpaper Engine's own UI
        if (name === "schemecolor") continue
        var entry = {
            name: name,
            type: type,
            label: prettyLabel(p.text || name),
            value: normalizeValue(type, p.value),
            condition: p.condition ? String(p.condition) : "",
            order: p.order !== undefined ? Number(p.order) : (p.index !== undefined ? Number(p.index) : 1e9)
        }
        if (type === "combo") {
            entry.options = (p.options || []).map(function(o) {
                return { label: prettyLabel(o.label !== undefined ? o.label : o.value), value: String(o.value) }
            })
        } else if (type === "slider") {
            entry.min = p.min !== undefined ? Number(p.min) : 0
            entry.max = p.max !== undefined ? Number(p.max) : 100
            entry.step = p.step !== undefined ? Number(p.step) : (p.fraction ? 0.01 : 1)
            entry.precision = p.precision !== undefined ? Number(p.precision) : (p.fraction ? 2 : 0)
        }
        list.push(entry)
    }
    list.sort(function(a, b) { return a.order - b.order || (a.name < b.name ? -1 : 1) })
    return list
}

// --- conditions: a small evaluator for the JS expressions WE stores, e.g.
// "language.value == 1", "clockstyle.value != 2 && showclock.value". Never runs the text as code.

function tokenize(src) {
    var tokens = []
    var re = /^\s*(?:(\d+(?:\.\d+)?)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)|(===|!==|==|!=|<=|>=|&&|\|\||[<>!()]))/
    var rest = String(src)
    while (!/^\s*$/.test(rest)) {
        var m = re.exec(rest)
        if (!m) throw new Error("bad condition near " + rest)
        if (m[1] !== undefined) tokens.push({ t: "num", v: Number(m[1]) })
        else if (m[2] !== undefined) tokens.push({ t: "str", v: m[2].substring(1, m[2].length - 1) })
        else if (m[3] !== undefined) tokens.push({ t: "id", v: m[3] })
        else tokens.push({ t: "op", v: m[4] })
        rest = rest.substring(m[0].length)
    }
    return tokens
}

function looseEquals(a, b) {
    if (typeof a === "boolean") a = a ? 1 : 0
    if (typeof b === "boolean") b = b ? 1 : 0
    var na = Number(a), nb = Number(b)
    if (a !== "" && b !== "" && !isNaN(na) && !isNaN(nb)) return na === nb
    return String(a) === String(b)
}

function evaluateCondition(condition, values) {
    if (!condition) return true
    var tokens
    try {
        tokens = tokenize(condition)
    } catch (e) {
        return true
    }
    var i = 0
    function peek() { return tokens[i] }
    function take(op) {
        if (tokens[i] && tokens[i].t === "op" && tokens[i].v === op) { i++; return true }
        return false
    }
    function primary() {
        var tok = tokens[i++]
        if (!tok) throw new Error("unexpected end")
        if (tok.t === "num" || tok.t === "str") return tok.v
        if (tok.t === "op" && tok.v === "(") {
            var v = orExpr()
            if (!take(")")) throw new Error("missing )")
            return v
        }
        if (tok.t === "op" && tok.v === "!") return !truthy(primary())
        if (tok.t === "id") {
            if (tok.v === "true") return true
            if (tok.v === "false") return false
            // "name.value" (or a bare "name") reads the property's current value
            var name = tok.v.replace(/\.value$/, "")
            return values[name]
        }
        throw new Error("unexpected " + tok.v)
    }
    function truthy(v) {
        if (typeof v === "string") return v !== "" && v !== "0" && v !== "false"
        return !!v
    }
    function compare() {
        var left = primary()
        var tok = peek()
        while (tok && tok.t === "op" && ["==", "===", "!=", "!==", "<", ">", "<=", ">="].indexOf(tok.v) !== -1) {
            i++
            var right = primary()
            if (tok.v === "==" || tok.v === "===") left = looseEquals(left, right)
            else if (tok.v === "!=" || tok.v === "!==") left = !looseEquals(left, right)
            else if (tok.v === "<") left = Number(left) < Number(right)
            else if (tok.v === ">") left = Number(left) > Number(right)
            else if (tok.v === "<=") left = Number(left) <= Number(right)
            else left = Number(left) >= Number(right)
            tok = peek()
        }
        return left
    }
    function andExpr() {
        var v = compare()
        while (take("&&")) {
            var r = compare()
            v = truthy(v) && truthy(r)
        }
        return v
    }
    function orExpr() {
        var v = andExpr()
        while (take("||")) {
            var r = andExpr()
            v = truthy(v) || truthy(r)
        }
        return v
    }
    try {
        var result = orExpr()
        if (i !== tokens.length) return true
        return truthy(result)
    } catch (e) {
        // a condition this evaluator doesn't understand: show the property rather than hide it
        return true
    }
}

// the value each property has now: saved/edited value, else the scene's default
function effectiveValues(properties, currentValues) {
    var values = {}
    for (var i = 0; i < properties.length; i++) {
        var p = properties[i]
        values[p.name] = currentValues[p.name] !== undefined ? currentValues[p.name] : p.value
    }
    return values
}

function visibleProperties(properties, currentValues) {
    var values = effectiveValues(properties, currentValues)
    return properties.filter(function(p) { return evaluateCondition(p.condition, values) })
}

// "--set-property" value: colors as "r,g,b(,a)" (the engine accepts commas), the rest as text
function propertyArgValue(value) {
    if (Array.isArray(value)) return value.join(",")
    return String(value)
}

// two property values are the same (colors compare by component)
function sameValue(a, b) {
    if (Array.isArray(a) || Array.isArray(b)) {
        var x = parseColor(a), y = parseColor(b)
        for (var i = 0; i < 3; i++) {
            if (Math.abs((x[i] || 0) - (y[i] || 0)) > 0.002) return false
        }
        return true
    }
    if (typeof a === "boolean" || typeof b === "boolean") return normalizeValue("bool", a) === normalizeValue("bool", b)
    return String(a) === String(b)
}

function comboLabel(prop, value) {
    var options = prop.options || []
    for (var i = 0; i < options.length; i++) {
        if (looseEquals(options[i].value, value)) return options[i].label
    }
    return options.length > 0 ? options[0].label : ""
}

function comboValue(prop, label) {
    var options = prop.options || []
    for (var i = 0; i < options.length; i++) {
        if (options[i].label === label) return options[i].value
    }
    return label
}

// --- layers

function layerIcon(type) {
    switch (type) {
    case "image": return "image"
    case "text": return "text_fields"
    case "particle": return "auto_awesome"
    case "sound": return "music_note"
    }
    return "folder"
}

// The tree of layers the scene shows with the given properties, depth-first in the scene's order:
// [{ id, name, type, depth, parent, effects: [{ id, name }] }]. Layers and effects the scene itself
// hides (another language, an effect turned off by a property) are left out.
function parseLayers(output) {
    var lines = String(output || "").split("\n")
    var data = null
    for (var i = lines.length - 1; i >= 0; i--) {
        var line = lines[i].trim()
        if (line.charAt(0) !== "{") continue
        try {
            data = JSON.parse(line)
            break
        } catch (e) {
            continue
        }
    }
    if (!data || !Array.isArray(data.layers)) return []

    var byId = {}
    var children = {}
    var roots = []
    data.layers.forEach(function(l) { byId[l.id] = l })
    data.layers.forEach(function(l) {
        if (l.hidden) return
        if (l.parent !== null && l.parent !== undefined && byId[l.parent]) {
            if (!children[l.parent]) children[l.parent] = []
            children[l.parent].push(l)
        } else {
            roots.push(l)
        }
    })

    var result = []
    function visit(l, depth) {
        if (depth > 32) return
        result.push({
            id: l.id,
            name: l.name || ("Layer " + l.id),
            type: l.type,
            depth: depth,
            parent: l.parent === undefined ? null : l.parent,
            effects: (l.effects || []).filter(function(e) { return !e.hidden }).map(function(e) {
                return { id: e.id, name: prettyLabel(e.name) || ("Effect " + e.id) }
            })
        })
        ;(children[l.id] || []).forEach(function(c) { visit(c, depth + 1) })
    }
    roots.forEach(function(l) { visit(l, 0) })
    return result
}

// ids as the engine flag wants them ("1,2,3"), "" when there are none
function idList(ids) {
    return (Array.isArray(ids) ? ids : []).filter(function(id) { return id !== null && id !== undefined && !isNaN(Number(id)) })
        .map(function(id) { return String(Math.trunc(Number(id))) }).join(",")
}
