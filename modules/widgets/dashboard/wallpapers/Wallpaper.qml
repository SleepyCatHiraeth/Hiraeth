import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.config

PanelWindow {
    id: wallpaper

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "ambxst:wallpaper"
    exclusionMode: ExclusionMode.Ignore

    color: "transparent"

    property string wallpaperDir: expandTilde(wallpaperConfig.adapter.wallPath)
    property string fallbackDir: decodeURIComponent(Qt.resolvedUrl("../../../../assets/wallpapers_example").toString().replace("file://", ""))
    property var wallpaperPaths: []
    property var subfolderFilters: []
    property var allSubdirs: []
    property int currentIndex: 0
    property string currentWallpaper: initialLoadCompleted && wallpaperPaths.length > 0 ? wallpaperPaths[currentIndex] : ""
    property bool initialLoadCompleted: false
    property bool usingFallback: false
    property bool _wallpaperDirInitialized: false
    property string currentMatugenScheme: wallpaperConfig.adapter.matugenScheme
    property var perScreenWallpapers: wallpaperConfig.adapter.perScreenWallpapers || {}
    property string effectiveWallpaper: perScreenWallpapers[currentScreenName] || currentWallpaper
    property string currentScreenName: wallpaper.screen ? wallpaper.screen.name : ""
    property alias tintEnabled: wallpaperAdapter.tintEnabled
    property int thumbnailsVersion: 0
    property bool matugenWaitingForVideoFrame: false
    property string lockscreenFrameInProgress: ""

    property var activeVideo: null

    // Every wallpaper window decodes at one shared size, so the file is
    // decoded once and every window's preload reaches Ready in the same
    // tick. Decoding per screen size instead makes the larger monitor
    // finish late and its fade visibly trails the smaller one.
    readonly property size decodeSize: {
        var w = 0;
        var h = 0;
        const screens = Quickshell.screens || [];
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].width > w)
                w = screens[i].width;
            if (screens[i].height > h)
                h = screens[i].height;
        }
        return Qt.size(w > 0 ? w : wallpaper.width, h > 0 ? h : wallpaper.height);
    }

    readonly property var optimizedPalette: ["background", "overBackground", "shadow", "surface", "surfaceBright", "surfaceDim", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest", "primary", "secondary", "tertiary", "red", "lightRed", "green", "lightGreen", "blue", "lightBlue", "yellow", "lightYellow", "cyan", "lightCyan", "magenta", "lightMagenta"]

    // Blurs the wallpaper while niri's native overview is open. The overview
    // backdrop shows this surface (place-within-backdrop), so blurring it here
    // is what the user sees behind scaled workspace previews.
    readonly property bool overviewBlurPossible: AxctlService.compositorName === "niri"
    readonly property bool overviewBlurActive: Config.desktop.blurWallpaperOnOverview
        && overviewBlurPossible
        && AxctlService.overviewOpen

    // Sync state from the primary wallpaper manager to secondary instances
    Binding {
        target: wallpaper
        property: "wallpaperPaths"
        value: GlobalStates.wallpaperManager.wallpaperPaths
        when: GlobalStates.wallpaperManager !== null && GlobalStates.wallpaperManager !== wallpaper
    }

    Binding {
        target: wallpaper
        property: "currentIndex"
        value: GlobalStates.wallpaperManager.currentIndex
        when: GlobalStates.wallpaperManager !== null && GlobalStates.wallpaperManager !== wallpaper
    }

    Binding {
        target: wallpaper
        property: "subfolderFilters"
        value: GlobalStates.wallpaperManager.subfolderFilters
        when: GlobalStates.wallpaperManager !== null && GlobalStates.wallpaperManager !== wallpaper
    }

    Binding {
        target: wallpaper
        property: "initialLoadCompleted"
        value: GlobalStates.wallpaperManager.initialLoadCompleted
        when: GlobalStates.wallpaperManager !== null && GlobalStates.wallpaperManager !== wallpaper
    }

    property string colorPresetsDir: Quickshell.env("HOME") + "/.config/ambxst/colors"
    property string officialColorPresetsDir: decodeURIComponent(Qt.resolvedUrl("../../../../assets/colors").toString().replace("file://", ""))

    onColorPresetsDirChanged: console.log("Color Presets Directory:", colorPresetsDir)
    property list<string> colorPresets: []
    onColorPresetsChanged: console.log("Color Presets Updated:", colorPresets)
    property string activeColorPreset: wallpaperConfig.adapter.activeColorPreset || ""

    // React to light/dark mode changes
    property bool isLightMode: Config.theme.lightMode
    onIsLightModeChanged: {
        if (activeColorPreset) {
            applyColorPreset();
        } else {
            runMatugenForCurrentWallpaper();
        }
    }

    onActiveColorPresetChanged: {
        if (activeColorPreset) {
            applyColorPreset();
        } else {
            runMatugenForCurrentWallpaper();
        }
    }

    function scanColorPresets() {
        scanPresetsProcess.running = true;
    }

    function applyColorPreset() {
        if (!activeColorPreset)
            return;

        var mode = Config.theme.lightMode ? "light.json" : "dark.json";

        var officialFile = officialColorPresetsDir + "/" + activeColorPreset + "/" + mode;
        var userFile = colorPresetsDir + "/" + activeColorPreset + "/" + mode;
        // QUICKSHELL-GIT: var dest = Quickshell.cachePath("colors.json");
        var dest = Quickshell.env("HOME") + "/.cache/ambxst/colors.json";

        // Try official first, then user. Use bash conditional.
        var cmd = "if [ -f '" + officialFile + "' ]; then cp '" + officialFile + "' '" + dest + "'; else cp '" + userFile + "' '" + dest + "'; fi";

        console.log("Applying color preset:", activeColorPreset);
        applyPresetProcess.command = ["bash", "-c", cmd];
        applyPresetProcess.running = true;
    }

    function setColorPreset(name) {
        wallpaperConfig.adapter.activeColorPreset = name;
    // activeColorPreset property will update automatically via binding to adapter
    }

    // Funciones utilitarias para tipos de archivo
    function expandTilde(path) {
        if (!path || !path.startsWith("~"))
            return path;
        var home = Quickshell.env("HOME");
        if (path === "~")
            return home;
        if (path.startsWith("~/"))
            return home + path.substring(1);
        return path;
    }

    function getFileType(path) {
        var extension = path.toLowerCase().split('.').pop();
        if (['jpg', 'jpeg', 'png', 'webp', 'tif', 'tiff', 'bmp'].includes(extension)) {
            return 'image';
        } else if (['gif'].includes(extension)) {
            return 'gif';
        } else if (['mp4', 'webm', 'mov', 'avi', 'mkv'].includes(extension)) {
            return 'video';
        }
        return 'unknown';
    }

    function getThumbnailPath(filePath) {
        // Compute relative path from wallpaperDir
        var basePath = wallpaperDir.endsWith("/") ? wallpaperDir : wallpaperDir + "/";
        var relativePath = filePath.replace(basePath, "");

        // Replace the filename with .jpg extension
        var pathParts = relativePath.split('/');
        var fileName = pathParts.pop();
        var thumbnailName = fileName + ".jpg";
        var relativeDir = pathParts.join('/');

        // Build the proxy path
        // QUICKSHELL-GIT: var thumbnailPath = Quickshell.cacheDir + "/thumbnails/" + relativeDir + "/" + thumbnailName;
        var thumbnailPath = Quickshell.env("HOME") + "/.cache/ambxst" + "/thumbnails/" + relativeDir + "/" + thumbnailName;
        return thumbnailPath;
    }

    function getDisplaySource(filePath) {
        var fileType = getFileType(filePath);

        // Para el display (WallpapersTab), siempre usar thumbnails si están disponibles
        if (fileType === 'video' || fileType === 'image' || fileType === 'gif') {
            var thumbnailPath = getThumbnailPath(filePath);
            // Verificar si el thumbnail existe (esto es solo para debugging, QML manejará el fallback)
            return thumbnailPath;
        }

        // Fallback al archivo original si no es un tipo soportado
        return filePath;
    }

    function getColorSource(filePath) {
        var fileType = getFileType(filePath);

        // Video colors use the same extracted frame as the lockscreen.
        if (fileType === 'video') {
            return getLockscreenFramePath(filePath);
        }

        // Imágenes y GIFs usan el archivo original para colores
        return filePath;
    }

    function getLockscreenFramePath(filePath) {
        if (!filePath) {
            return "";
        }

        var fileType = getFileType(filePath);

        // Para imágenes estáticas, usar el archivo original
        if (fileType === 'image') {
            return filePath;
        }

        // Para videos y GIFs, usar el frame cacheado
        if (fileType === 'video' || fileType === 'gif') {
            var fileName = filePath.split('/').pop();
            // QUICKSHELL-GIT: var cachePath = Quickshell.cacheDir + "/lockscreen/" + fileName + ".jpg";
            var cachePath = Quickshell.env("HOME") + "/.cache/ambxst" + "/lockscreen/" + fileName + ".jpg";
            return cachePath;
        }

        return filePath;
    }

    function generateLockscreenFrame(filePath) {
        if (!filePath) {
            console.warn("generateLockscreenFrame: empty filePath");
            return;
        }

        if (lockscreenWallpaperScript.running && lockscreenFrameInProgress === filePath)
            return;

        console.log("Generating lockscreen frame for:", filePath);

        // QUICKSHELL-GIT: var dataPath = Quickshell.cacheDir;
        var dataPath = Quickshell.env("HOME") + "/.cache/ambxst";

        lockscreenWallpaperScript.command = ["ambxst", "lockwall", filePath, dataPath];
        lockscreenFrameInProgress = filePath;

        lockscreenWallpaperScript.running = true;
    }

    function getSubfolderFromPath(filePath) {
        var basePath = wallpaperDir.endsWith("/") ? wallpaperDir : wallpaperDir + "/";
        var relativePath = filePath.replace(basePath, "");
        var parts = relativePath.split("/");
        if (parts.length > 1) {
            return parts[0];
        }
        return "";
    }

    function scanSubfolders() {
        if (!wallpaperDir)
            return;
        // Explicitly update command with current wallpaperDir
        var cmd = ["find", "-L", wallpaperDir, "-mindepth", "1", "-name", ".*", "-prune", "-o", "-type", "d", "-print"];
        scanSubfoldersProcess.command = cmd;
        scanSubfoldersProcess.running = true;
    }

    // Update directory watcher when wallpaperDir changes
    onWallpaperDirChanged: {
        // Skip initial spurious changes before config is loaded
        if (!_wallpaperDirInitialized)
            return;

        // Only the primary wallpaper manager should handle directory changes
        if (GlobalStates.wallpaperManager !== wallpaper)
            return;

        console.log("Wallpaper directory changed to:", wallpaperDir);
        usingFallback = false;

        // Clear current lists to reflect change immediately
        wallpaperPaths = [];
        subfolderFilters = [];

        directoryWatcher.path = wallpaperDir;

        // Force update scan command
        var cmd = ["find", "-L", wallpaperDir, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"];
        scanWallpapers.command = cmd;
        scanWallpapers.running = true;

        scanSubfolders();

        // Regenerate thumbnails for the new directory (delayed)
        if (delayedThumbnailGen.running)
            delayedThumbnailGen.restart();
        else
            delayedThumbnailGen.start();
    }

    onCurrentWallpaperChanged:
    // Matugen se ejecuta manualmente en las funciones de cambio
    {}

    function setWallpaper(path, targetScreen = null) {
        if (GlobalStates.wallpaperManager && GlobalStates.wallpaperManager !== wallpaper) {
            GlobalStates.wallpaperManager.setWallpaper(path, targetScreen);
            return;
        }

        console.log("setWallpaper called with:", path, "for screen:", targetScreen);
        initialLoadCompleted = true;
        var pathIndex = wallpaperPaths.indexOf(path);
        if (pathIndex !== -1) {
            if (targetScreen) {
                // If targeting a specific screen, save to perScreenWallpapers instead of currentWall
                let perScreen = Object.assign({}, wallpaperConfig.adapter.perScreenWallpapers || {});
                perScreen[targetScreen] = path;
                wallpaperConfig.adapter.perScreenWallpapers = perScreen;
                
                // The most recently selected wallpaper drives the global palette.
                currentIndex = pathIndex;
                wallpaperConfig.adapter.currentWall = path;
                currentWallpaper = path;
                runMatugenForCurrentWallpaper();
            } else {
                // Global fallback target
                currentIndex = pathIndex;
                wallpaperConfig.adapter.currentWall = path;
                currentWallpaper = path;
                runMatugenForCurrentWallpaper();
            }
            generateLockscreenFrame(path);
        } else {
            console.warn("Wallpaper path not found in current list:", path);
        }
    }

    function clearPerScreenWallpaper(targetScreen) {
        if (GlobalStates.wallpaperManager && GlobalStates.wallpaperManager !== wallpaper) {
            GlobalStates.wallpaperManager.clearPerScreenWallpaper(targetScreen);
            return;
        }
        
        console.log("Clearing per-screen wallpaper for:", targetScreen);
        let perScreen = Object.assign({}, wallpaperConfig.adapter.perScreenWallpapers || {});
        if (perScreen[targetScreen]) {
            delete perScreen[targetScreen];
            wallpaperConfig.adapter.perScreenWallpapers = perScreen;
        }
    }

    function nextWallpaper() {
        if (GlobalStates.wallpaperManager && GlobalStates.wallpaperManager !== wallpaper) {
            GlobalStates.wallpaperManager.nextWallpaper();
            return;
        }

        if (wallpaperPaths.length === 0)
            return;
        initialLoadCompleted = true;
        currentIndex = (currentIndex + 1) % wallpaperPaths.length;
        currentWallpaper = wallpaperPaths[currentIndex];
        wallpaperConfig.adapter.currentWall = wallpaperPaths[currentIndex];
        runMatugenForCurrentWallpaper();
        generateLockscreenFrame(wallpaperPaths[currentIndex]);
    }

    function previousWallpaper() {
        if (GlobalStates.wallpaperManager && GlobalStates.wallpaperManager !== wallpaper) {
            GlobalStates.wallpaperManager.previousWallpaper();
            return;
        }

        if (wallpaperPaths.length === 0)
            return;
        initialLoadCompleted = true;
        currentIndex = currentIndex === 0 ? wallpaperPaths.length - 1 : currentIndex - 1;
        currentWallpaper = wallpaperPaths[currentIndex];
        wallpaperConfig.adapter.currentWall = wallpaperPaths[currentIndex];
        runMatugenForCurrentWallpaper();
        generateLockscreenFrame(wallpaperPaths[currentIndex]);
    }

    function setWallpaperByIndex(index) {
        if (GlobalStates.wallpaperManager && GlobalStates.wallpaperManager !== wallpaper) {
            GlobalStates.wallpaperManager.setWallpaperByIndex(index);
            return;
        }

        if (index >= 0 && index < wallpaperPaths.length) {
            initialLoadCompleted = true;
            currentIndex = index;
            currentWallpaper = wallpaperPaths[currentIndex];
            wallpaperConfig.adapter.currentWall = wallpaperPaths[currentIndex];
            runMatugenForCurrentWallpaper();
            generateLockscreenFrame(wallpaperPaths[currentIndex]);
        }
    }

    // Función para re-ejecutar Matugen con el wallpaper actual
    function setMatugenScheme(scheme) {
        wallpaperConfig.adapter.matugenScheme = scheme;

        if (wallpaperConfig.adapter.activeColorPreset) {
            console.log("Switching to Matugen scheme, clearing preset");
            wallpaperConfig.adapter.activeColorPreset = "";
        } else {
            runMatugenForCurrentWallpaper();
        }
    }

    function runMatugenForCurrentWallpaper(videoFrameReady = false) {
        if (activeColorPreset) {
            console.log("Skipping Matugen because color preset is active:", activeColorPreset);
            return;
        }

        if (currentWallpaper && initialLoadCompleted) {
            console.log("Running Matugen for current wallpaper:", currentWallpaper);

            var fileType = getFileType(currentWallpaper);
            var matugenSource = getColorSource(currentWallpaper);

            console.log("Using source for matugen:", matugenSource, "(type:", fileType + ")");

            if (fileType === "video" && !videoFrameReady) {
                matugenWaitingForVideoFrame = true;
                generateLockscreenFrame(currentWallpaper);
                return;
            }

            // Stop existing processes if running to prioritize new request
            if (matugenProcessWithConfig.running) {
                matugenProcessWithConfig.running = false;
            }

            // Ejecutar matugen con configuración específica
            var commandWithConfig = ["matugen", "image", matugenSource, "--prefer", "saturation", "-c", decodeURIComponent(Qt.resolvedUrl("../../../../assets/matugen/config.toml").toString().replace("file://", "")), "-t", wallpaperConfig.adapter.matugenScheme];
            if (Config.theme.lightMode) {
                commandWithConfig.push("-m", "light");
            }
            matugenProcessWithConfig.command = commandWithConfig;
            matugenProcessWithConfig.running = true;
        }
    }

    function requestVideoSync() {
        if (GlobalStates.wallpaperManager !== wallpaper) {
            if (GlobalStates.wallpaperManager) {
                GlobalStates.wallpaperManager.requestVideoSync();
            }
            return;
        }
        GlobalStates.videoSyncTick++;
    }

    Component.onCompleted: {
        if (currentScreenName)
            GlobalStates.screenWallpapers[currentScreenName] = wallpaper;

        // Only the first Wallpaper instance should manage scanning
        // Other instances (for other screens) share the same data via GlobalStates
        if (GlobalStates.wallpaperManager !== null) {
            // Another instance already registered, skip initialization
            _wallpaperDirInitialized = true;
            return;
        }

        GlobalStates.wallpaperManager = wallpaper;

        // Verify wallpapers.json exists, create with fallback if not
        checkWallpapersJson.running = true;

        // Initial scans - color presets are needed for the wallpapers tab SchemeSelector.
        scanColorPresets();
        presetsWatcher.reload();
        officialPresetsWatcher.reload();
        // Load initial wallpaper config - triggers onWallPathChanged which does the actual scan
        wallpaperConfig.reload();

        // Lockscreen frame generation deferred 5s after boot to reduce peak memory.
        Qt.callLater(function () {
            if (currentWallpaper) {
                lockscreenFrameTimer.start();
            }
        });
    }

    Component.onDestruction: {
        if (currentScreenName && GlobalStates.screenWallpapers[currentScreenName] === wallpaper)
            delete GlobalStates.screenWallpapers[currentScreenName];
    }

    // Deferred lockscreen frame generation to avoid blocking boot
    Timer {
        id: lockscreenFrameTimer
        interval: 5000
        running: false
        repeat: false
        onTriggered: {
            if (currentWallpaper) {
                generateLockscreenFrame(currentWallpaper);
            }
        }
    }

    FileView {
        id: wallpaperConfig
        // QUICKSHELL-GIT: path: Quickshell.cachePath("wallpapers.json")
        path: Quickshell.env("HOME") + "/.cache/ambxst/wallpapers.json"
        watchChanges: true

        onLoaded: {
            if (!wallpaperConfig.adapter.wallPath) {
                console.log("Loaded config but wallPath is empty, using fallback");
                wallpaperConfig.adapter.wallPath = fallbackDir;
            }
        }

        onFileChanged: reload()
        onAdapterUpdated: {
            // Ensure matugenScheme has a default value
            if (!wallpaperConfig.adapter.matugenScheme) {
                wallpaperConfig.adapter.matugenScheme = "scheme-tonal-spot";
            }
            // Update the currentMatugenScheme property to trigger UI updates
            currentMatugenScheme = Qt.binding(function () {
                return wallpaperConfig.adapter.matugenScheme;
            });
            writeAdapter();
        }

        JsonAdapter {
            id: wallpaperAdapter
            property string currentWall: ""
            property string wallPath: ""
            property string matugenScheme: "scheme-tonal-spot"
            property string activeColorPreset: ""
            property bool tintEnabled: false
            property var perScreenWallpapers: ({})

            onActiveColorPresetChanged: {
                if (wallpaperConfig.adapter.activeColorPreset !== wallpaper.activeColorPreset) {
                    wallpaper.activeColorPreset = wallpaperConfig.adapter.activeColorPreset || "";
                }
            }

            onCurrentWallChanged: {
                // Skip during initial load - scanWallpapers handles this
                if (!wallpaper._wallpaperDirInitialized)
                    return;

                // Siempre actualizar si es diferente al actual
                if (currentWall && currentWall !== wallpaper.currentWallpaper) {
                    // If paths are not loaded yet, wait for scanWallpapers to finish
                    if (wallpaper.wallpaperPaths.length === 0) {
                        return;
                    }

                    var pathIndex = wallpaper.wallpaperPaths.indexOf(currentWall);
                    if (pathIndex !== -1) {
                        wallpaper.currentIndex = pathIndex;
                        if (!wallpaper.initialLoadCompleted) {
                            wallpaper.initialLoadCompleted = true;
                        }
                        wallpaper.runMatugenForCurrentWallpaper();
                    } else {
                        console.warn("Saved wallpaper not found in current list:", currentWall);
                    }
                }
            }

            onWallPathChanged: {
                if (wallPath) {
                    var dir = wallpaper.expandTilde(wallPath);
                    console.log("Config wallPath updated:", dir);

                    // Initialize scanning on first valid wallPath load
                    if (!wallpaper._wallpaperDirInitialized && GlobalStates.wallpaperManager === wallpaper) {
                        wallpaper._wallpaperDirInitialized = true;

                        // Set up directory watcher
                        directoryWatcher.path = dir;
                        directoryWatcher.reload();

                        // Perform initial wallpaper scan
                        var cmd = ["find", "-L", dir, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"];
                        scanWallpapers.command = cmd;
                        scanWallpapers.running = true;
                        wallpaper.scanSubfolders();

                        // Start thumbnail generation
                        delayedThumbnailGen.start();
                    }
                }
            }
        }
    }

    Process {
        id: checkWallpapersJson
        running: false
        // QUICKSHELL-GIT: command: ["test", "-f", Quickshell.cachePath("wallpapers.json")]
        command: ["test", "-f", Quickshell.env("HOME") + "/.cache/ambxst/wallpapers.json"]

        onExited: function (exitCode) {
            if (exitCode !== 0) {
                console.log("wallpapers.json does not exist, creating with fallbackDir");
                wallpaperConfig.adapter.wallPath = fallbackDir;
            } else {
                console.log("wallpapers.json exists");
            }
        }
    }

    Process {
        id: matugenProcessWithConfig
        running: false
        command: []

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Matugen (with config) output:", text);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Matugen (with config) error:", text);
                }
            }
        }

        onExited: {
            console.log("Matugen with config finished");
        }
    }

        // Proceso para generar thumbnails de videos
    Process {
        id: thumbnailGeneratorScript
        running: false
        command: ["ambxst", "thumbs", Quickshell.env("HOME") + "/.cache/ambxst" + "/wallpapers.json", Quickshell.env("HOME") + "/.cache/ambxst", fallbackDir]

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Thumbnail Generator:", text);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Thumbnail Generator Error:", text);
                }
            }
        }

        onExited: function (exitCode) {
            lockscreenFrameInProgress = "";
            if (exitCode === 0) {
                console.log("✅ Video thumbnails generated successfully");
                thumbnailsVersion++;
            } else {
                console.warn("⚠️ Thumbnail generation failed with code:", exitCode);
            }
        }
    }

    Timer {
        id: delayedThumbnailGen
        interval: 2000 // Delay 2 seconds after change to not block
        repeat: false
        onTriggered: thumbnailGeneratorScript.running = true
    }

    // Proceso para generar frame de lockscreen con el script de Python
    Process {
        id: lockscreenWallpaperScript
        running: false
        command: []

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.log("Lockscreen Wallpaper Generator:", text);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Lockscreen Wallpaper Generator Error:", text);
                }
            }
        }

        onExited: function (exitCode) {
            if (exitCode === 0) {
                console.log("✅ Lockscreen wallpaper ready");
                if (matugenWaitingForVideoFrame) {
                    matugenWaitingForVideoFrame = false;
                    runMatugenForCurrentWallpaper(true);
                }
            } else {
                matugenWaitingForVideoFrame = false;
                console.warn("⚠️ Lockscreen wallpaper generation failed with code:", exitCode);
            }
        }
    }

    Process {
        id: scanSubfoldersProcess
        running: false
        command: wallpaperDir ? ["find", "-L", wallpaperDir, "-mindepth", "1", "-name", ".*", "-prune", "-o", "-type", "d", "-print"] : []

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("scanSubfolders stdout:", text);
                var rawPaths = text.trim().split("\n").filter(function (f) {
                    return f.length > 0;
                });

                allSubdirs = rawPaths;

                var basePath = wallpaperDir.endsWith("/") ? wallpaperDir : wallpaperDir + "/";

                var topLevelFolders = rawPaths.filter(function (path) {
                    var relative = path.replace(basePath, "");
                    return relative.indexOf("/") === -1;
                }).map(function (path) {
                    return path.split("/").pop();
                }).filter(function (name) {
                    return name.length > 0 && !name.startsWith(".");
                });

                topLevelFolders.sort();
                subfolderFilters = topLevelFolders;
                subfolderFiltersChanged();  // Emitir señal manualmente
                console.log("Updated subfolderFilters:", subfolderFilters);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error scanning subfolders:", text);
                }
            }
        }

        onRunningChanged: {
            if (running) {
                console.log("Starting scanSubfolders for directory:", wallpaperDir);
            } else {
                console.log("Finished scanSubfolders");
            }
        }
    }

    // Directory watcher using FileView to monitor the wallpaper directory
    FileView {
        id: directoryWatcher
        path: wallpaperDir
        watchChanges: true
        printErrors: false

        onFileChanged: {
            if (wallpaperDir === "")
                return;
            console.log("Wallpaper directory changed, rescanning...");
            scanWallpapers.running = true;
            scanSubfoldersProcess.running = true;
            // Regenerar thumbnails si hay nuevos videos (delayed)
            if (delayedThumbnailGen.running)
                delayedThumbnailGen.restart();
            else
                delayedThumbnailGen.start();
        }

        // Remove onLoadFailed to prevent premature fallback activation
    }

    // Recursive directory watchers for subfolders
    Instantiator {
        model: allSubdirs

        delegate: FileView {
            path: modelData
            watchChanges: true
            printErrors: false
            onFileChanged: {
                console.log("Subdirectory content changed (" + path + "), rescanning...");
                scanWallpapers.running = true;
                scanSubfoldersProcess.running = true;

                // Regenerar thumbnails (delayed)
                if (delayedThumbnailGen.running)
                    delayedThumbnailGen.restart();
                else
                    delayedThumbnailGen.start();
            }
        }
    }

    // Directory watcher for user color presets.
    FileView {
        id: presetsWatcher
        path: colorPresetsDir
        watchChanges: true
        printErrors: false

        onFileChanged: {
            console.log("User color presets directory changed, rescanning...");
            scanPresetsProcess.running = true;
        }
    }

    // Directory watcher for official color presets.
    FileView {
        id: officialPresetsWatcher
        path: officialColorPresetsDir
        watchChanges: true
        printErrors: false

        onFileChanged: {
            console.log("Official color presets directory changed, rescanning...");
            scanPresetsProcess.running = true;
        }
    }

    Process {
        id: scanWallpapers
        running: false
        command: wallpaperDir ? ["find", "-L", wallpaperDir, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"] : []

        onRunningChanged: {
            if (running && wallpaperDir === "") {
                console.log("Blocking scanWallpapers because wallpaperDir is empty");
                running = false;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                var files = text.trim().split("\n").filter(function (f) {
                    return f.length > 0;
                });
                if (files.length === 0) {
                    console.log("No wallpapers found in main directory, using fallback");
                    usingFallback = true;
                    scanFallback.running = true;
                } else {
                    usingFallback = false;
                    // Only update if the list has actually changed
                    var newFiles = files.sort();
                    var listChanged = JSON.stringify(newFiles) !== JSON.stringify(wallpaperPaths);
                    if (listChanged) {
                        console.log("Wallpaper directory updated. Found", newFiles.length, "images");
                        wallpaperPaths = newFiles;

                        // Always try to load the saved wallpaper when list changes
                        if (wallpaperPaths.length > 0) {
                            // Trigger thumbnail generation if list changed
                            if (delayedThumbnailGen.running)
                                delayedThumbnailGen.restart();
                            else
                                delayedThumbnailGen.start();

                            if (wallpaperConfig.adapter.currentWall) {
                                var savedIndex = wallpaperPaths.indexOf(wallpaperConfig.adapter.currentWall);
                                if (savedIndex !== -1) {
                                    currentIndex = savedIndex;
                                    console.log("Loaded saved wallpaper at index:", savedIndex);
                                } else {
                                    currentIndex = 0;
                                    console.log("Saved wallpaper not found, using first");
                                }
                            } else {
                                currentIndex = 0;
                            }

                            if (!initialLoadCompleted) {
                                if (!wallpaperConfig.adapter.currentWall) {
                                    wallpaperConfig.adapter.currentWall = wallpaperPaths[0];
                                }
                                initialLoadCompleted = true;
                                // runMatugenForCurrentWallpaper() will be called by onCurrentWallChanged
                            }
                        }
                    }
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("Error scanning wallpaper directory:", text);
                    // Only fallback if we don't already have wallpapers loaded AND we have a valid directory that failed
                    if (wallpaperPaths.length === 0 && wallpaperDir !== "") {
                        console.log("Directory scan failed for " + wallpaperDir + ", using fallback");
                        usingFallback = true;
                        scanFallback.running = true;
                    }
                }
            }
        }
    }

    Process {
        id: scanFallback
        running: false
        command: ["find", "-L", fallbackDir, "-name", ".*", "-prune", "-o", "-type", "f", "(", "-name", "*.jpg", "-o", "-name", "*.jpeg", "-o", "-name", "*.png", "-o", "-name", "*.webp", "-o", "-name", "*.tif", "-o", "-name", "*.tiff", "-o", "-name", "*.gif", "-o", "-name", "*.mp4", "-o", "-name", "*.webm", "-o", "-name", "*.mov", "-o", "-name", "*.avi", "-o", "-name", "*.mkv", ")", "-print"]

        stdout: StdioCollector {
            onStreamFinished: {
                var files = text.trim().split("\n").filter(function (f) {
                    return f.length > 0;
                });
                console.log("Using fallback wallpapers. Found", files.length, "images");

                // Only use fallback if we don't already have main wallpapers loaded
                if (usingFallback) {
                    wallpaperPaths = files.sort();

                    // Initialize fallback wallpaper selection
                    if (wallpaperPaths.length > 0) {
                        if (wallpaperConfig.adapter.currentWall) {
                            var savedIndex = wallpaperPaths.indexOf(wallpaperConfig.adapter.currentWall);
                            if (savedIndex !== -1) {
                                currentIndex = savedIndex;
                            } else {
                                currentIndex = 0;
                            }
                        } else {
                            currentIndex = 0;
                        }

                        if (!initialLoadCompleted) {
                            if (!wallpaperConfig.adapter.currentWall) {
                                wallpaperConfig.adapter.currentWall = wallpaperPaths[0];
                            }
                            initialLoadCompleted = true;
                            // runMatugenForCurrentWallpaper() will be called by onCurrentWallChanged
                        }
                    }
                }
            }
        }
    }

    Process {
        id: scanPresetsProcess
        running: false
        // Scan both directories. find will complain to stderr if one is missing but still output what it finds.
        command: ["find", officialColorPresetsDir, colorPresetsDir, "-mindepth", "1", "-maxdepth", "1", "-type", "d"]

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("Scan Presets Output:", text);
                var rawLines = text.trim().split("\n");
                var uniqueNames = [];
                for (var i = 0; i < rawLines.length; i++) {
                    var line = rawLines[i].trim();
                    if (line.length === 0)
                        continue;
                    var name = line.split('/').pop();
                    // Deduplicate
                    if (uniqueNames.indexOf(name) === -1) {
                        uniqueNames.push(name);
                    }
                }
                uniqueNames.sort();
                console.log("Found color presets:", uniqueNames);
                colorPresets = uniqueNames;
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                // Suppress common "No such file or directory" if one dir is missing
                // console.warn("Scan Presets Error:", text);
            }
        }
    }

    Process {
        id: applyPresetProcess
        running: false
        command: []

        onExited: code => {
            if (code === 0)
                console.log("Color preset applied successfully");
            else
                console.warn("Failed to apply color preset, code:", code);
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: "black"
        focus: true

        Keys.onLeftPressed: {
            if (wallpaper.wallpaperPaths.length > 0) {
                wallpaper.previousWallpaper();
            }
        }

        Keys.onRightPressed: {
            if (wallpaper.wallpaperPaths.length > 0) {
                wallpaper.nextWallpaper();
            }
        }

        WallpaperImage {
            id: wallImage
            anchors.fill: parent
            source: wallpaper.effectiveWallpaper
        }
    }

    // One wallpaper image layer. Two of these are stacked so a change can
    // dissolve, and the tint shader has to sit on each of them - hence a
    // component rather than a second copy of the Image block.
    component WallLayer: Image {
        id: layerImage

        property var paletteTexture: null
        property real paletteSize: 0
        property bool tint: false

        mipmap: true
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        // Must match the preloader's sourceSize exactly, or this is a cache
        // miss and decodes all over again.
        sourceSize.width: wallpaper.decodeSize.width
        sourceSize.height: wallpaper.decodeSize.height

        layer.enabled: tint
        layer.effect: ShaderEffect {
            property var paletteTexture: layerImage.paletteTexture
            property real paletteSize: layerImage.paletteSize
            property real texWidth: layerImage.width
            property real texHeight: layerImage.height

            vertexShader: "palette.vert.qsb"
            fragmentShader: "palette.frag.qsb"
        }
    }

    component WallpaperImage: Item {
        property string source
        // What is actually on screen. It lags `source` until the incoming
        // image has decoded, so the outgoing frame stays up instead of the
        // window going black mid-transition.
        property string displayedSource

        function commitSource() {
            displayedSource = source;
        }

        // Hand the decoded wallpaper to the layers below, which dissolve
        // between the outgoing and incoming frame themselves. Nothing is
        // animated on this item for stills - dimming the whole thing and
        // cutting the image at the dim point is what made the change look
        // abrupt.
        function startTransition() {
            commitSource();
        }

        // Decode the incoming wallpaper off screen before it is shown.
        // Image clears its texture as soon as `source` changes and draws
        // nothing until the decode finishes, which at this screen's
        // sourceSize takes longer than one leg of the animation - the
        // change then reads as an instant pop rather than a fade, and the
        // bigger the monitor the worse it gets. Preloading at the same
        // sourceSize puts the pixmap in QQuickPixmapCache, so the visible
        // swap below is a cache hit.
        Image {
            id: preloader
            visible: false
            asynchronous: true
            cache: true
            sourceSize.width: wallpaper.decodeSize.width
            sourceSize.height: wallpaper.decodeSize.height
            source: (wallImage.source && getFileType(wallImage.source) === 'image') ? "file://" + wallImage.source : ""

            onStatusChanged: {
                if (status === Image.Ready) {
                    wallImage.startTransition();
                } else if (status === Image.Error) {
                    console.warn("Wallpaper preload failed, showing it anyway:", source);
                    wallImage.commitSource();
                }
            }
        }

        onSourceChanged: {
            if (!source) {
                displayedSource = "";
                return;
            }

            if (getFileType(source) === 'image') {
                // The swap waits for `preloader` to finish decoding.
                return;
            }

            // gif/video play on VideoWallpaper's own surface, so there is
            // nothing for us to decode first.
            if (displayedSource !== "" && Config.animDuration > 0) {
                transitionAnimation.restart();
            }
            displayedSource = source;
        }

        SequentialAnimation {
            id: transitionAnimation

            ParallelAnimation {
                NumberAnimation {
                    target: wallImage
                    property: "scale"
                    to: 1.01
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: wallImage
                    property: "opacity"
                    to: 0.5
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
            }

            // Swap at the dimmest point. The pixmap is already decoded, so
            // this is a cache hit and the fade back in carries the new
            // wallpaper.
            ScriptAction {
                script: wallImage.commitSource()
            }

            ParallelAnimation {
                NumberAnimation {
                    target: wallImage
                    property: "scale"
                    to: 1.0
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: wallImage
                    property: "opacity"
                    to: 1.0
                    duration: Config.animDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Loader {
            id: wallpaperLoader
            anchors.fill: parent
            sourceComponent: {
                if (!parent.displayedSource)
                    return null;

                var fileType = getFileType(parent.displayedSource);
                if (fileType === 'image') {
                    return staticImageComponent;
                } else if (fileType === 'gif' || fileType === 'video') {
                    return videoWallpaperComponent;
                }
                return staticImageComponent;
            }

            property string sourceFile: parent.displayedSource
        }

        // The effect pass is only mounted where it can actually trigger;
        // elsewhere the loader renders directly with zero overhead.
        Loader {
            anchors.fill: parent
            active: wallpaper.overviewBlurPossible
            sourceComponent: Component {
                MultiEffect {
                    anchors.fill: parent
                    source: wallpaperLoader
                    autoPaddingEnabled: false
                    // Keep the effect alive while the fade-out animation runs.
                    blurEnabled: wallpaper.overviewBlurActive || blur > 0
                    blurMax: 64
                    blur: wallpaper.overviewBlurActive ? 1.0 : 0.0
                    visible: wallpaperLoader.status === Loader.Ready

                    Behavior on blur {
                        enabled: Config.animDuration > 0
                        NumberAnimation {
                            duration: Config.animDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }

        Component {
            id: staticImageComponent
            Item {
                id: staticImageRoot
                width: parent.width
                height: parent.height
                property string sourceFile: parent.sourceFile
                property bool tint: wallpaper.tintEnabled

                // Subset of colors for optimization (approx 25 colors vs 98)
                readonly property var optimizedPalette: ["background", "overBackground", "shadow", "surface", "surfaceBright", "surfaceDim", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest", "primary", "secondary", "tertiary", "red", "lightRed", "green", "lightGreen", "blue", "lightBlue", "yellow", "lightYellow", "cyan", "lightCyan", "magenta", "lightMagenta"]

                // Palette generation for the shader
                Item {
                    id: paletteSourceItem
                    // Must be visible for ShaderEffectSource to capture it,
                    // but we hide it visually by placing it behind or expecting ShaderEffectSource hideSource behavior.
                    visible: true
                    width: staticImageRoot.optimizedPalette.length
                    height: 1
                    opacity: 0 // Make invisible to eye but maintain presence for capture if needed (though hideSource usually handles this)

                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: staticImageRoot.optimizedPalette
                            Rectangle {
                                width: 1
                                height: 1
                                color: Colors[modelData]
                            }
                        }
                    }
                }

                ShaderEffectSource {
                    id: paletteTextureSource
                    sourceItem: paletteSourceItem
                    hideSource: true
                    visible: false // The source object itself doesn't need to be visible in the scene graph
                    smooth: false
                    recursive: false
                }

                // Two stacked layers. The incoming wallpaper fades in on top
                // of the outgoing one, which is only dropped once the fade
                // has finished, so the screen never passes through black and
                // the image is never cut mid-animation. Its pixmap is already
                // decoded by the preloader, so the incoming layer is Ready
                // before the fade starts.
                property bool frontIsA: true
                readonly property Image frontLayer: frontIsA ? layerA : layerB
                readonly property Image backLayer: frontIsA ? layerB : layerA

                WallLayer {
                    id: layerA
                    anchors.fill: parent
                    tint: staticImageRoot.tint
                    paletteTexture: paletteTextureSource
                    paletteSize: staticImageRoot.optimizedPalette.length
                }

                WallLayer {
                    id: layerB
                    anchors.fill: parent
                    opacity: 0
                    tint: staticImageRoot.tint
                    paletteTexture: paletteTextureSource
                    paletteSize: staticImageRoot.optimizedPalette.length
                }

                SequentialAnimation {
                    id: dissolve
                    property Item incoming: null
                    property Item outgoing: null

                    ParallelAnimation {
                        NumberAnimation {
                            target: dissolve.incoming
                            property: "opacity"
                            from: 0.0
                            to: 1.0
                            duration: Config.animDuration * 2
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            target: dissolve.incoming
                            property: "scale"
                            from: 1.02
                            to: 1.0
                            duration: Config.animDuration * 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    ScriptAction {
                        script: staticImageRoot.retireOutgoing()
                    }
                }

                // Free the frame we just faded away from. Dropping its source
                // releases the texture; keeping it would hold a second
                // full-screen pixmap per screen for nothing.
                function retireOutgoing() {
                    if (!dissolve.outgoing)
                        return;
                    dissolve.outgoing.opacity = 0;
                    dissolve.outgoing.scale = 1.0;
                    dissolve.outgoing.source = "";
                    dissolve.outgoing = null;
                }

                function show(path) {
                    if (!path)
                        return;

                    // A change arriving mid-dissolve snaps that fade to its
                    // end before starting the next one. Stopping it and
                    // leaving the half-faded layer in place would make it the
                    // next dissolve's backdrop, so the incoming wallpaper
                    // would fade in over a partly transparent frame and the
                    // animation would read as a muddy flicker. Clicking
                    // through a folder lands here constantly.
                    if (dissolve.running) {
                        dissolve.stop();
                        if (dissolve.incoming) {
                            dissolve.incoming.opacity = 1.0;
                            dissolve.incoming.scale = 1.0;
                        }
                        retireOutgoing();
                    }

                    // Resolved after the fixup above, which changes which
                    // layer is front and which is free.
                    const incoming = backLayer;
                    const outgoing = frontLayer;
                    // Idempotent: both onSourceFileChanged and
                    // Component.onCompleted can deliver the same path at
                    // startup, and that must not dissolve the wallpaper into
                    // itself.
                    if (outgoing.source.toString() === "file://" + path)
                        return;

                    incoming.source = "file://" + path;
                    incoming.z = 1;
                    outgoing.z = 0;
                    frontIsA = !frontIsA;

                    if (!outgoing.source.toString() || Config.animDuration <= 0) {
                        // Nothing to dissolve from - first wallpaper of the
                        // session, or animations turned off.
                        incoming.opacity = 1.0;
                        incoming.scale = 1.0;
                        outgoing.opacity = 0;
                        outgoing.source = "";
                        return;
                    }

                    dissolve.incoming = incoming;
                    dissolve.outgoing = outgoing;
                    dissolve.restart();
                }

                onSourceFileChanged: show(sourceFile)
                Component.onCompleted: show(sourceFile)
            }
        }

        Component {
            id: videoWallpaperComponent
            VideoWallpaper {
                id: videoWallpaperChild
                sourceFile: parent.sourceFile
                tint: wallpaper.tintEnabled
                onRequestVideoSync: wallpaper.requestVideoSync()

                Component.onCompleted: wallpaper.activeVideo = videoWallpaperChild
                Component.onDestruction: {
                    if (wallpaper.activeVideo === videoWallpaperChild)
                        wallpaper.activeVideo = null;
                }
            }
        }
    }
}
