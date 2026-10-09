import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modals.Common
import qs.Services
import "../js/PropertiesParser.js" as PropertiesParser
import "../js/SceneProperties.js" as SceneProps
import "../js/Utils.js" as Utils

DankModal {
    id: root

    property string sceneId: ""
    property string backgroundsDir: ""
    // every property of the scene, and the ones that apply to the current choices
    property var allProperties: []
    readonly property var shownProperties: SceneProps.visibleProperties(allProperties, currentValues)
    property bool propertiesLoading: false
    property var currentValues: ({})
    readonly property string wallpaperType: pluginSettings && sceneId ? pluginSettings.wallpaperTypeOf(sceneId) : ""
    // layers the scene shows with the current properties, and what the user turned off
    property var layers: []
    property bool layersLoading: false
    property bool layersSupported: false
    property var hiddenLayers: []
    property var disabledEffects: []
    // turning a layer off turns off its copies too (other languages, other layouts)
    property bool linkLayers: true
    property var layerLinks: ({ layers: {}, effects: {} })
    // pending per-scene render overrides (fps, scaling, audio, ...), saved on Apply
    property var overrideValues: ({})
    property var pluginSettings: null

    signal propertiesSaved(var properties)

    modalWidth: Math.min(screenWidth - 100, 700)
    modalHeight: Math.min(screenHeight - 100, 760)
    width: modalWidth
    height: modalHeight
    positioning: "center"
    allowStacking: true

    onOpened: reload()

    onDialogClosed: {
        Qt.callLater(() => {
            allProperties = []
            currentValues = {}
            overrideValues = {}
            layers = []
            layerLinks = { layers: {}, effects: {} }
            hiddenLayers = []
            disabledEffects = []
            linkLayers = true
        })
    }

    onSceneIdChanged: {
        if (shouldBeVisible) reload()
    }

    // the layer list depends on the properties (language, layout...), so follow them
    onCurrentValuesChanged: {
        if (shouldBeVisible && layersSupported) layersDebounce.restart()
    }

    content: Item {
        anchors.fill: parent

        Rectangle {
            id: header
            width: parent.width
            height: 60
            color: Theme.surfaceContainer

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingM

                DankIcon {
                    name: "tune"
                    size: Theme.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    StyledText {
                        text: "Scene Settings"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }

                    StyledText {
                        text: {
                            return "Scene ID: " + sceneId + (wallpaperType ? " · " + wallpaperType : "")
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        opacity: 0.7
                    }
                }
            }

            DankButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                text: "Close"
                onClicked: root.close()
            }
        }

        Rectangle {
            id: contentContainer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: header.bottom
            anchors.bottom: footer.top
            width: parent.width
            color: "transparent"

            Flickable {
                id: propertiesFlickable
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                contentHeight: propertiesColumn.implicitHeight
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Column {
                    id: propertiesColumn
                    width: parent.width
                    spacing: Theme.spacingL

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Scene Properties"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                        }

                        StyledText {
                            text: {
                                if (propertiesLoading) return "Loading properties..."
                                if (allProperties.length === 0) return "No configurable properties found for this scene"
                                return "The scene's own options, in the order Wallpaper Engine shows them. Options that only apply to another choice (another language, another layout) are hidden until you pick it."
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            opacity: 0.7
                            width: parent.width
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            width: parent.width
                            visible: shownProperties.length > 0
                            height: visible ? propertiesList.implicitHeight + Theme.spacingM * 2 : 0
                            color: Theme.surface
                            radius: Theme.cornerRadius
                            border.width: 1
                            border.color: Theme.outline

                            Column {
                                id: propertiesList
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                Repeater {
                                    model: shownProperties

                                    delegate: Item {
                                        id: propertyRow

                                        property var prop: modelData
                                        property var value: currentValues[prop.name] !== undefined ? currentValues[prop.name] : prop.value
                                        property bool changed: currentValues[prop.name] !== undefined && !SceneProps.sameValue(currentValues[prop.name], prop.value)

                                        width: propertiesList.width
                                        height: prop.type === "text" ? sectionLabel.implicitHeight + Theme.spacingS : 44

                                        // "text" properties are the author's section titles
                                        StyledText {
                                            id: sectionLabel
                                            visible: propertyRow.prop.type === "text"
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            text: propertyRow.prop.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                            color: Theme.primary
                                            wrapMode: Text.Wrap
                                        }

                                        StyledText {
                                            id: propertyLabel
                                            visible: propertyRow.prop.type !== "text"
                                            width: Math.min(220, parent.width * 0.4)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: propertyRow.prop.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: propertyRow.changed ? Font.Bold : Font.Normal
                                            color: propertyRow.changed ? Theme.primary : Theme.surfaceText
                                            elide: Text.ElideRight
                                        }

                                        Loader {
                                            visible: propertyRow.prop.type !== "text"
                                            anchors.left: propertyLabel.right
                                            anchors.leftMargin: Theme.spacingM
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            // distinct names: DankSlider and Binding have their own "value"
                                            property var propData: propertyRow.prop
                                            property var propValue: propertyRow.value
                                            sourceComponent: {
                                                switch (propData.type) {
                                                case "slider": return sliderComponent
                                                case "color": return colorComponent
                                                case "bool": return boolComponent
                                                case "combo": return comboComponent
                                                case "textinput": return textComponent
                                                }
                                                return null
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: wallpaperType === "scene"

                        StyledText {
                            text: "Layers & Effects"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                        }

                        StyledText {
                            text: {
                                if (!layersSupported) return "Needs the updated linux-wallpaperengine (with --list-layers). Install it to turn layers and effects off here."
                                if (layersLoading && layers.length === 0) return "Loading layers..."
                                if (layers.length === 0) return "No layers found"
                                return "Turn off what you don't need. A hidden layer isn't loaded at all, so it costs nothing; the list follows the properties above."
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            opacity: 0.7
                            width: parent.width
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            width: parent.width
                            visible: layersSupported && layers.length > 0
                            height: visible ? linkRow.implicitHeight + Theme.spacingM * 2 : 0
                            color: Theme.surface
                            radius: Theme.cornerRadius
                            border.width: 1
                            border.color: Theme.outline

                            Item {
                                id: linkRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                implicitHeight: Math.max(linkText.implicitHeight, linkToggle.height)

                                Column {
                                    id: linkText
                                    anchors.left: parent.left
                                    anchors.right: linkToggle.left
                                    anchors.rightMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    StyledText {
                                        text: "Same layers together"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: "Turning a layer or effect off also turns off its copies with the same name, e.g. in the other languages or clock layouts of the scene."
                                        font.pixelSize: Theme.fontSizeSmall
                                        opacity: 0.7
                                        wrapMode: Text.Wrap
                                    }
                                }

                                DankToggle {
                                    id: linkToggle
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: linkLayers
                                    onToggled: (checked) => linkLayers = checked
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            visible: layersSupported && layers.length > 0
                            height: visible ? layersList.implicitHeight + Theme.spacingM * 2 : 0
                            color: Theme.surface
                            radius: Theme.cornerRadius
                            border.width: 1
                            border.color: Theme.outline

                            Column {
                                id: layersList
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: 2

                                Repeater {
                                    model: layers

                                    delegate: Column {
                                        id: layerRow

                                        property var layerData: modelData
                                        property bool shown: hiddenLayers.indexOf(layerData.id) === -1
                                        // inside a hidden group: hidden anyway, the toggle has no say
                                        property bool parentShown: !layerHiddenByAncestor(layerData)

                                        width: layersList.width
                                        opacity: parentShown ? 1 : 0.45

                                        Item {
                                            width: parent.width
                                            height: 40

                                            DankIcon {
                                                id: layerIcon
                                                x: layerRow.layerData.depth * Theme.spacingL
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: SceneProps.layerIcon(layerRow.layerData.type)
                                                size: Theme.iconSizeSmall
                                                opacity: 0.7
                                            }

                                            StyledText {
                                                anchors.left: layerIcon.right
                                                anchors.leftMargin: Theme.spacingS
                                                anchors.right: layerToggle.left
                                                anchors.rightMargin: Theme.spacingS
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: layerRow.layerData.name
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: layerRow.layerData.depth === 0 ? Font.Medium : Font.Normal
                                                elide: Text.ElideRight
                                            }

                                            DankToggle {
                                                id: layerToggle
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                enabled: layerRow.parentShown
                                                checked: layerRow.shown
                                                onToggled: (checked) => setLayerShown(layerRow.layerData.id, checked)
                                            }
                                        }

                                        Repeater {
                                            model: layerRow.layerData.effects

                                            delegate: Item {
                                                id: effectRow

                                                property var effect: modelData

                                                width: layerRow.width
                                                height: 34
                                                visible: layerRow.shown
                                                opacity: 0.85

                                                DankIcon {
                                                    id: effectIcon
                                                    x: (layerRow.layerData.depth + 1) * Theme.spacingL
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    name: "auto_fix_high"
                                                    size: Theme.iconSizeSmall - 4
                                                    opacity: 0.6
                                                }

                                                StyledText {
                                                    anchors.left: effectIcon.right
                                                    anchors.leftMargin: Theme.spacingS
                                                    anchors.right: effectToggle.left
                                                    anchors.rightMargin: Theme.spacingS
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: effectRow.effect.name
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    opacity: 0.85
                                                    elide: Text.ElideRight
                                                }

                                                DankToggle {
                                                    id: effectToggle
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    enabled: layerRow.parentShown
                                                    checked: disabledEffects.indexOf(effectRow.effect.id) === -1
                                                    onToggled: (checked) => setEffectEnabled(effectRow.effect.id, checked)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Render Settings for This Scene"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                        }

                        StyledText {
                            text: "Changing a setting here overrides the monitor's value for this scene only. Use the reset button to inherit it again."
                            font.pixelSize: Theme.fontSizeSmall
                            opacity: 0.7
                            width: parent.width
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            width: parent.width
                            height: overridesList.implicitHeight + Theme.spacingM * 2
                            color: Theme.surface
                            radius: Theme.cornerRadius
                            border.width: 1
                            border.color: Theme.outline

                            Column {
                                id: overridesList
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                Repeater {
                                    model: Utils.SCENE_OVERRIDE_DEFS

                                    delegate: Row {
                                        id: overrideRow

                                        property var def: modelData
                                        property bool overridden: overrideValues[def.key] !== undefined
                                        property var value: effectiveValue(def.key)

                                        width: overridesList.width
                                        height: 48
                                        spacing: Theme.spacingM
                                        // volume only matters when the scene plays audio
                                        visible: def.key !== "volume" || effectiveValue("silent") === false

                                        StyledText {
                                            width: 170
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: overrideRow.def.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: overrideRow.overridden ? Font.Bold : Font.Normal
                                            color: overrideRow.overridden ? Theme.primary : Theme.surfaceText
                                        }

                                        Loader {
                                            id: overrideControl
                                            width: parent.width - 170 - overrideState.width - Theme.spacingM * 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            // distinct names: DankSlider and Binding have their own "value"
                                            property var ovrDef: overrideRow.def
                                            property var ovrValue: overrideRow.value
                                            sourceComponent: {
                                                if (ovrDef.type === "slider") return overrideSliderComponent
                                                if (ovrDef.type === "combo") return overrideComboComponent
                                                return overrideBoolComponent
                                            }
                                        }

                                        Item {
                                            id: overrideState
                                            width: 110
                                            height: parent.height

                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                visible: !overrideRow.overridden
                                                text: "monitor"
                                                font.pixelSize: Theme.fontSizeSmall
                                                opacity: 0.5
                                            }

                                            DankActionButton {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                visible: overrideRow.overridden
                                                iconName: "restart_alt"
                                                tooltipText: "Inherit the monitor's value"
                                                onClicked: clearOverride(overrideRow.def.key)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: footer
            width: parent.width
            height: 60
            anchors.bottom: parent.bottom
            color: Theme.surfaceContainer

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingL
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingM

                DankButton {
                    text: "Reset to Defaults"
                    enabled: allProperties.length > 0 || Object.keys(overrideValues).length > 0
                             || hiddenLayers.length > 0 || disabledEffects.length > 0
                    onClicked: resetToDefaults()
                }

                DankButton {
                    text: "Cancel"
                    onClicked: root.close()
                }

                DankButton {
                    text: "Apply"
                    enabled: sceneId !== ""
                    onClicked: {
                        saveProperties()
                        propertiesSaved(currentValues)
                        root.close()
                    }
                }
            }
        }
    }

    // property controls: they show the property's value (edited, saved or the scene's default)
    // and store any change in currentValues. Binding (not a plain binding) where the control
    // assigns its own value while used, which would break a plain one and stop it following a reset.
    Component {
        id: sliderComponent

        Row {
            id: sliderRow

            // DankSlider is integer-only, so it moves in the property's steps
            readonly property real stepSize: propData.step > 0 ? propData.step : 1
            readonly property int decimals: Math.max(0, Math.min(4, propData.precision || 0))

            spacing: Theme.spacingM

            DankSlider {
                id: propertySlider
                width: parent.width - sliderValueText.width - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                minimum: Math.round(propData.min / sliderRow.stepSize)
                maximum: Math.round(propData.max / sliderRow.stepSize)
                showValue: false
                // the list scrolls; don't let the wheel change properties by accident
                wheelEnabled: false

                Binding {
                    target: propertySlider
                    property: "value"
                    value: Math.round(Number(propValue) / sliderRow.stepSize)
                }

                onSliderValueChanged: (newValue) => {
                    var v = Number((newValue * sliderRow.stepSize).toFixed(sliderRow.decimals + 2))
                    setPropertyValue(propData.name, v)
                }
            }

            StyledText {
                id: sliderValueText
                width: 48
                anchors.verticalCenter: parent.verticalCenter
                text: Number(propValue).toFixed(sliderRow.decimals)
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    Component {
        id: colorComponent

        Row {
            spacing: Theme.spacingM

            Rectangle {
                id: colorSwatch

                property var rgba: SceneProps.parseColor(propValue)
                property color swatchColor: Qt.rgba(rgba[0], rgba[1], rgba[2], 1)

                width: 72
                height: 30
                radius: Theme.cornerRadius
                color: swatchColor
                border.width: 2
                border.color: Theme.outlineStrong
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const picker = PopoutService.colorPickerModal
                        if (!picker) return
                        const name = propData.name
                        const alpha = colorSwatch.rgba.length > 3 ? colorSwatch.rgba[3] : undefined
                        picker.selectedColor = colorSwatch.swatchColor
                        picker.pickerTitle = propData.label
                        picker.onColorSelectedCallback = function(selected) {
                            var c = [selected.r, selected.g, selected.b].map(function(x) { return Number(x.toFixed(4)) })
                            if (alpha !== undefined) c.push(alpha)
                            setPropertyValue(name, c)
                        }
                        picker.show()
                    }
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: colorSwatch.swatchColor.toString().toUpperCase()
                font.pixelSize: Theme.fontSizeSmall
                opacity: 0.7
            }
        }
    }

    Component {
        id: boolComponent

        Item {
            height: propertyToggle.height

            DankToggle {
                id: propertyToggle
                anchors.right: parent.right
                checked: propValue === true
                onToggled: (checked) => setPropertyValue(propData.name, checked)
            }
        }
    }

    Component {
        id: comboComponent

        DankDropdown {
            id: propertyCombo
            options: (propData.options || []).map(function(o) { return o.label })
            compactMode: true

            Binding {
                target: propertyCombo
                property: "currentValue"
                value: SceneProps.comboLabel(propData, propValue)
            }

            onValueChanged: (label) => setPropertyValue(propData.name, SceneProps.comboValue(propData, label))
        }
    }

    Component {
        id: textComponent

        DankTextField {
            id: propertyText

            property bool editing: false

            height: 36
            onFocusStateChanged: (hasFocus) => editing = hasFocus

            Binding {
                target: propertyText
                property: "text"
                value: String(propValue)
                when: !propertyText.editing
            }

            onEditingFinished: setPropertyValue(propData.name, propertyText.text)
        }
    }

    // override controls: they show the effective value (override or inherited); any user change
    // stores an override. Binding (not a plain binding) because DankSlider assigns its own value
    // while dragging, which would break a plain one and stop it following a reset.
    Component {
        id: overrideSliderComponent

        Row {
            spacing: Theme.spacingM

            DankSlider {
                id: overrideSlider
                width: parent.width - overrideSliderValue.width - Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                minimum: ovrDef.min
                maximum: ovrDef.max
                showValue: false
                // the list scrolls; don't let the wheel create overrides by accident
                wheelEnabled: false

                Binding {
                    target: overrideSlider
                    property: "value"
                    value: Math.round(ovrValue)
                }

                onSliderValueChanged: (newValue) => setOverride(ovrDef.key, newValue)
            }

            StyledText {
                id: overrideSliderValue
                width: 40
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(overrideSlider.value)
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    Component {
        id: overrideComboComponent

        DankDropdown {
            id: overrideCombo
            options: ovrDef.options
            compactMode: true

            Binding {
                target: overrideCombo
                property: "currentValue"
                value: String(ovrValue)
            }

            onValueChanged: (newValue) => setOverride(ovrDef.key, newValue)
        }
    }

    Component {
        id: overrideBoolComponent

        Item {
            height: overrideToggle.height

            DankToggle {
                id: overrideToggle
                anchors.left: parent.left
                checked: ovrValue === true
                onToggled: (checked) => setOverride(ovrDef.key, checked)
            }
        }
    }


    Timer {
        id: layersDebounce
        interval: 400
        onTriggered: loadLayers()
    }

    Component.onCompleted: {
        if (sceneId) reload()
    }

    function reload() {
        if (!sceneId) return
        allProperties = []
        currentValues = {}
        layers = []
        loadOverrides()
        loadLayerChoices()
        loadProperties()
        // with support known, the currentValues change above already queued the layer list
        if (!layersSupported) layersProbe.running = true
    }

    function inheritedValue(key) {
        var d = Utils.sceneOverrideDef(key)
        var fallback = d ? d.def : undefined
        // a video inherits the monitor's Video FPS, scenes its Scene FPS
        return pluginSettings ? pluginSettings.getInheritedSceneSetting(sceneId, key, fallback) : fallback
    }

    function effectiveValue(key) {
        return overrideValues[key] !== undefined ? overrideValues[key] : inheritedValue(key)
    }

    function setOverride(key, value) {
        var updated = Object.assign({}, overrideValues)
        updated[key] = value
        overrideValues = updated
    }

    function clearOverride(key) {
        var updated = Object.assign({}, overrideValues)
        delete updated[key]
        overrideValues = updated
    }

    function loadOverrides() {
        overrideValues = pluginSettings ? pluginSettings.getSceneOverrides(sceneId) : {}
    }

    // reassign (not mutate) so the change signal fires and bindings refresh
    function setPropertyValue(name, value) {
        var updated = Object.assign({}, currentValues)
        updated[name] = value
        currentValues = updated
    }

    // project.json has the order, combo labels and conditions; the engine's list is the fallback
    function loadProperties() {
        var text = pluginSettings ? pluginSettings.projectJsonText(sceneId) : ""
        var parsed = text ? SceneProps.parseProjectProperties(text) : []
        if (parsed.length > 0 || text) {
            allProperties = parsed
            loadSavedValues()
            return
        }
        propertiesLoading = true
        propertiesLoader.command = ["linux-wallpaperengine", Utils.resolveBgArg(sceneId, backgroundsDir), "--list-properties"]
        propertiesLoader.running = true
    }

    Process {
        id: propertiesLoader
        property string propertiesOutput: ""

        stdout: SplitParser {
            onRead: (data) => {
                propertiesLoader.propertiesOutput += data + "\n"
            }
        }

        onExited: (code) => {
            var parsed = code === 0 && propertiesOutput ? PropertiesParser.parseProperties(propertiesOutput) : []
            // the engine's list has neither labels for combo values nor conditions
            allProperties = parsed.map(function(p) {
                var entry = Object.assign({}, p, { label: SceneProps.prettyLabel(p.text || p.name), condition: "" })
                if (p.type === "combo") {
                    entry.options = (p.options || []).map(function(v) { return { label: String(v), value: String(v) } })
                    entry.value = String(p.value)
                } else if (p.type === "slider") {
                    entry.min = p.min !== undefined ? p.min : 0
                    entry.max = p.max !== undefined ? p.max : 100
                    entry.step = p.step > 0 ? p.step : 1
                    entry.precision = entry.step < 1 ? 2 : 0
                }
                return entry
            })
            loadSavedValues()
            propertiesOutput = ""
            propertiesLoading = false
        }
    }

    function loadSavedValues() {
        if (pluginSettings) {
            currentValues = pluginSettings.getSceneProperties(sceneId) || {}
        }
    }

    function loadLayerChoices() {
        var saved = pluginSettings ? pluginSettings.getSceneLayers(sceneId) : {}
        hiddenLayers = saved.hiddenLayers || []
        disabledEffects = saved.disabledEffects || []
        linkLayers = saved.linkLayers !== false
    }

    function setLayerShown(id, shown) {
        var ids = linkLayers && layerLinks.layers[id] ? layerLinks.layers[id] : [id]
        hiddenLayers = SceneProps.setIds(hiddenLayers, ids, !shown)
    }

    function setEffectEnabled(id, enabled) {
        var ids = linkLayers && layerLinks.effects[id] ? layerLinks.effects[id] : [id]
        disabledEffects = SceneProps.setIds(disabledEffects, ids, !enabled)
    }

    function layerHiddenByAncestor(layer) {
        var byId = {}
        for (var i = 0; i < layers.length; i++) byId[layers[i].id] = layers[i]
        var parent = byId[layer.parent]
        for (var depth = 0; parent && depth < 32; depth++) {
            if (hiddenLayers.indexOf(parent.id) !== -1) return true
            parent = byId[parent.parent]
        }
        return false
    }

    // only the patched engine knows --list-layers; an older one would ignore the flag and start
    // the wallpaper in a window instead, so ask its --help first
    Process {
        id: layersProbe
        property bool found: false
        command: ["linux-wallpaperengine", "--help"]

        stdout: SplitParser {
            onRead: (data) => {
                if (data.indexOf("--list-layers") !== -1) layersProbe.found = true
            }
        }

        onExited: {
            layersSupported = found
            found = false
            if (layersSupported && root.shouldBeVisible) loadLayers()
        }
    }

    function loadLayers() {
        if (!sceneId || !layersSupported || wallpaperType !== "scene") return
        if (layersLoader.running) {
            layersLoader.rerun = true
            return
        }
        var cmd = ["linux-wallpaperengine", Utils.resolveBgArg(sceneId, backgroundsDir), "--list-layers"]
        var values = SceneProps.effectiveValues(allProperties, currentValues)
        for (var name in currentValues) {
            if (values[name] === undefined) values[name] = currentValues[name]
        }
        for (var key in values) {
            cmd.push("--set-property")
            cmd.push(key + "=" + SceneProps.propertyArgValue(values[key]))
        }
        layersLoading = true
        layersLoader.command = cmd
        layersLoader.running = true
    }

    Process {
        id: layersLoader
        property string output: ""
        property bool rerun: false

        stdout: SplitParser {
            onRead: (data) => {
                layersLoader.output += data + "\n"
            }
        }

        onExited: (code) => {
            if (code === 0) {
                var all = SceneProps.parseLayerData(output)
                layers = SceneProps.visibleLayerTree(all)
                layerLinks = SceneProps.layerLinks(all)
            }
            output = ""
            layersLoading = false
            if (rerun) {
                rerun = false
                loadLayers()
            }
        }
    }

    function saveProperties() {
        if (pluginSettings) {
            // properties that failed to (or didn't yet) load must not wipe the saved ones
            pluginSettings.saveSceneSettings(sceneId, allProperties.length > 0 ? currentValues : undefined, overrideValues, {
                hiddenLayers: hiddenLayers,
                disabledEffects: disabledEffects,
                linkLayers: linkLayers
            })
        }
    }

    function resetToDefaults() {
        currentValues = {}
        overrideValues = {}
        hiddenLayers = []
        disabledEffects = []
        linkLayers = true
    }
}
