function buildCommandArgs(o) {
    var args = ["linux-wallpaperengine"]

    if (o.assetsDir) {
        args.push("--assets-dir")
        args.push(o.assetsDir)
    }

    // o.streamTarget: render offscreen at o.streamSize ([w, h]) and stream the frames there (patched
    // engine, used for the lock screen) instead of drawing on a screen
    var streaming = !!o.streamTarget
    if (streaming) {
        args.push("--window")
        args.push("0x0x" + o.streamSize[0] + "x" + o.streamSize[1])
        args.push("--stream")
        args.push(o.streamTarget)
    } else if (o.screenMode === "span") {
        args.push("--screen-span")
        args.push(o.screenValue)
    } else {
        args.push("--screen-root")
        args.push(o.screenValue)
    }

    if (!streaming && o.useScreenshot && o.screenshotPath) {
        args.push("--screenshot")
        args.push(o.screenshotPath)
        var screenshotDelay = o.settings.screenshotDelay || 5
        if (screenshotDelay !== 5) {
            args.push("--screenshot-delay")
            args.push(String(screenshotDelay))
        }
    }

    args.push("--bg")
    // Authoritative custom root: when backgroundsDir is set, plain ids resolve against it (a path
    // the engine loads directly), bypassing Steam workshop discovery. Absolute paths pass through.
    var bgArg = o.sceneId
    if (bgArg && bgArg.indexOf("/") === -1 && o.backgroundsDir) {
        bgArg = o.backgroundsDir + "/" + bgArg
    }
    args.push(bgArg)

    if (streaming || o.forceNoAudio || o.settings.silent !== false) {
        args.push("--silent")
    } else {
        var volume = o.settings.volume
        if (volume === undefined || volume === null) volume = 50
        args.push("--volume")
        args.push(String(volume))
    }

    var fps = o.settings.fps || 30
    if (fps !== 30) {
        args.push("--fps")
        args.push(String(fps))
    }

    var scaling = o.settings.scaling || "default"
    if (scaling !== "default") {
        args.push("--scaling")
        args.push(scaling)
    }

    // Always anchor to the wlr-layer-shell "background" layer. DMS desktop
    // widgets render on "bottom", and same-layer stacking is map-order, so a
    // (re)spawned wallpaper left on the engine-default "bottom" would cover
    // them after every screen/scene change. "background" is strictly below
    // "bottom" per the protocol, making the order deterministic. On niri it
    // additionally pairs with place-within-backdrop layer-rules so the
    // wallpaper isn't cloned into every overview workspace card.
    if (!streaming) {
        args.push("--layer")
        args.push("background")
    }

    var sceneProps = o.settings.properties || {}
    for (var propName in sceneProps) {
        args.push("--set-property")
        args.push(propName + "=" + sceneProps[propName])
    }

    // layers and effects the user turned off in Scene Settings (patched engine)
    var hiddenLayers = (o.settings.hiddenLayers || []).join(",")
    if (hiddenLayers) {
        args.push("--hide-layer")
        args.push(hiddenLayers)
    }
    var disabledEffects = (o.settings.disabledEffects || []).join(",")
    if (disabledEffects) {
        args.push("--disable-effect")
        args.push(disabledEffects)
    }

    if (o.settings.disableParticles) args.push("--disable-particles")
    if (o.settings.downscaleToOutput) args.push("--downscale-to-output")
    if (o.settings.disableMouse) args.push("--disable-mouse")
    if (o.settings.disableParallax) args.push("--disable-parallax")
    if (o.settings.noAutoMute) args.push("--noautomute")
    if (o.settings.noAudioProcessing) args.push("--no-audio-processing")
    if (streaming || o.settings.noFullscreenPause) args.push("--no-fullscreen-pause")
    if (o.settings.fullscreenPauseOnlyActive) args.push("--fullscreen-pause-only-active")

    return args
}
