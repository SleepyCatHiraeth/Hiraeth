pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

FileView {
    id: colors
    // QUICKSHELL-GIT: path: Quickshell.cachePath("colors.json")
    path: Quickshell.env("HOME") + "/.cache/ambxst/colors.json"
    preload: true
    watchChanges: true
    onFileChanged: {
        reload();
        generationTimer.restart();
    }

    property Connections oledWatcher: Connections {
        target: Config
        function onOledModeChanged() {
            generationTimer.restart();
        }
    }

    property Connections themeWatcher: Connections {
        target: Config.loader
        function onFileChanged() {
            generationTimer.restart();
        }
    }

    property QtCtGenerator qtCtGenerator: QtCtGenerator {
        id: qtCtGenerator
    }

    property GtkGenerator gtkGenerator: GtkGenerator {
        id: gtkGenerator
    }

    property CursorGenerator cursorGenerator: CursorGenerator {}

    property PywalGenerator pywalGenerator: PywalGenerator {
        id: pywalGenerator
    }

    property KittyGenerator kittyGenerator: KittyGenerator {
        id: kittyGenerator
    }

    property SddmGenerator sddmGenerator: SddmGenerator {
        id: sddmGenerator
        colors: colors
    }

    property GreeterGenerator greeterGenerator: GreeterGenerator {
        id: greeterGenerator
    }

    property NvChadGenerator nvChadGenerator: NvChadGenerator {
        id: nvChadGenerator
    }

    property DiscordGenerator discordGenerator: DiscordGenerator {
        id: discordGenerator
    }

    property SpotifyGenerator spotifyGenerator: SpotifyGenerator {
        id: spotifyGenerator
    }

    property MillenniumGenerator millenniumGenerator: MillenniumGenerator {
        id: millenniumGenerator
    }

    property PywalZenGenerator pywalZenGenerator: PywalZenGenerator {
        id: pywalZenGenerator
    }

    // ---- Palette normalization -------------------------------------------------
    // Runs in memory on the publish path only, at the top of generationTimer, so
    // every generator below sees the repaired palette. It must never reach
    // FileView.writeAdapter(): rewriting ~/.cache/ambxst/colors.json would
    // retrigger onFileChanged and loop all ten generators forever.
    function normalizePalette() {
        const names = ["red", "green", "yellow", "blue", "magenta", "cyan"];
        const palette = {};
        for (let i = 0; i < names.length; i++) {
            const n = names[i];
            const ln = "light" + n.charAt(0).toUpperCase() + n.slice(1);
            palette[n] = colors.adapter[n].toString();
            palette[ln] = colors.adapter[ln].toString();
        }
        const repaired = colors.normalizeAnsi(palette);
        if (repaired !== null) {
            console.warn("Colors: repaired ANSI palette " + JSON.stringify(repaired));
            for (const key in repaired)
                colors.adapter[key] = repaired[key];
        }
        // Report any variant that ran out of headroom before the target, so a
        // wallpaper that cannot reach it is visible in the log rather than silent.
        for (let i = 0; i < names.length; i++) {
            const n = names[i];
            const ln = "light" + n.charAt(0).toUpperCase() + n.slice(1);
            const ratio = colors.contrastRatio(colors.adapter[ln].toString(), colors.adapter[n].toString());
            if (ratio < 1.6)
                console.warn("Colors: " + ln + " reaches only " + ratio.toFixed(2) + ":1 against " + n + ", short of the 1.60:1 target");
        }
        const guard = colors.guardContrast(colors.adapter.overBackground.toString(), colors.background.toString());
        if (guard !== null) {
            console.warn("Colors: overBackground contrast " + guard.before.toFixed(2) + ":1 is below 4.5:1, corrected to " + guard.after.toFixed(2) + ":1");
            colors.adapter.overBackground = guard.hex;
        }
    }

    // PALETTE-NORMALIZE-BEGIN
    // Pure JS below: no QML or Qt API, so the self-check in
    // Project/Wiki/raw/palette-step45-selfcheck.js can slice this region verbatim
    // and run the shipped logic under node.
    function hexToRgb(hex) {
        let h = hex.replace("#", "");
        if (h.length === 8)
            h = h.slice(2); // #aarrggbb
        return [parseInt(h.slice(0, 2), 16) / 255, parseInt(h.slice(2, 4), 16) / 255, parseInt(h.slice(4, 6), 16) / 255];
    }

    function rgbToHex(rgb) {
        let out = "#";
        for (let i = 0; i < 3; i++) {
            const n = Math.max(0, Math.min(255, Math.round(rgb[i] * 255)));
            out += (n < 16 ? "0" : "") + n.toString(16);
        }
        return out;
    }

    // chroma is the share of the brightest channel that carries color (HSV
    // saturation). HSL saturation cannot measure health here: every pastel whose
    // brightest channel is 255 reports s = 1.0, so a near-white like #e8ffea looks
    // fully saturated in HSL while its chroma is 0.09.
    function rgbToHsl(rgb) {
        const max = Math.max(rgb[0], rgb[1], rgb[2]);
        const min = Math.min(rgb[0], rgb[1], rgb[2]);
        const d = max - min;
        const l = (max + min) / 2;
        let h = 0;
        if (d > 0) {
            if (max === rgb[0])
                h = 60 * ((((rgb[1] - rgb[2]) / d) % 6 + 6) % 6);
            else if (max === rgb[1])
                h = 60 * ((rgb[2] - rgb[0]) / d + 2);
            else
                h = 60 * ((rgb[0] - rgb[1]) / d + 4);
        }
        const s = d === 0 ? 0 : Math.min(1, d / (1 - Math.abs(2 * l - 1)));
        return {
            h: h,
            s: s,
            l: l,
            chroma: max === 0 ? 0 : d / max
        };
    }

    function hslToHex(h, s, l) {
        const c = (1 - Math.abs(2 * l - 1)) * s;
        const hp = (((h % 360) + 360) % 360) / 60;
        const x = c * (1 - Math.abs((hp % 2) - 1));
        let rgb = [c, 0, x];
        if (hp < 1)
            rgb = [c, x, 0];
        else if (hp < 2)
            rgb = [x, c, 0];
        else if (hp < 3)
            rgb = [0, c, x];
        else if (hp < 4)
            rgb = [0, x, c];
        else if (hp < 5)
            rgb = [x, 0, c];
        const m = l - c / 2;
        return rgbToHex([rgb[0] + m, rgb[1] + m, rgb[2] + m]);
    }

    function hueDistance(a, b) {
        const d = (((a - b) % 360) + 360) % 360;
        return d > 180 ? 360 - d : d;
    }

    function minHueDistance(hue, placed) {
        let best = 360;
        for (let i = 0; i < placed.length; i++)
            best = Math.min(best, hueDistance(hue, placed[i]));
        return best;
    }

    // Places every broken entry at once, anchored on its own canonical ANSI hue
    // and moved away only as far as `target` separation demands, without ever
    // exceeding `maxDrift` degrees from canonical.
    //
    // Placing them jointly matters: repairing one at a time lets the first broken
    // entry take a slot the second needed more, and the old "widest free gap"
    // fallback had no reason to stay near canonical at all -- that is how a
    // repaired yellow landed at 166 deg and rendered teal.
    //
    // Candidates are generated in drift-ascending order, so the first complete
    // assignment is already cheap and the running best prunes the rest hard.
    // Returns the hue per entry (in `broken` order) with the smallest total
    // canonical drift, or null when `target` cannot be met by every entry.
    function assignHues(broken, canonical, healthy, target, maxDrift) {
        if (broken.length === 0)
            return [];
        const candidates = [];
        for (let i = 0; i < broken.length; i++) {
            const c = canonical[broken[i]];
            const list = [];
            for (let d = 0; d <= maxDrift; d++) {
                if (minHueDistance(c + d, healthy) >= target)
                    list.push(c + d);
                if (d > 0 && minHueDistance(c - d, healthy) >= target)
                    list.push(c - d);
            }
            // No hue in range clears the healthy entries, so no assignment can.
            if (list.length === 0)
                return null;
            candidates.push({
                index: i,
                list: list
            });
        }
        // Most-constrained entry first. An impossible target has no incumbent and
        // therefore no bound to prune against, so it would otherwise be discovered
        // only at the leaves; visiting the tightest entry first fails it shallow.
        candidates.sort(function (a, b) {
            return a.list.length - b.list.length;
        });
        let bestTotal = Infinity;
        let bestHues = null;
        // Bounded DFS. Exhausting the budget is reported as "infeasible at this
        // target", which only relaxes separation through the tiers below -- it can
        // never break the hard contract -- and keeps the search inside the 100 ms
        // publish timer on a palette whose healthy entries crowd one arc.
        let budget = 5000;
        function walk(depth, chosen, total) {
            if (budget-- <= 0)
                return;
            if (depth === candidates.length) {
                bestTotal = total;
                bestHues = chosen.slice();
                return;
            }
            const entry = candidates[depth];
            const canon = canonical[broken[entry.index]];
            for (let k = 0; k < entry.list.length; k++) {
                const drift = hueDistance(entry.list[k], canon);
                // Drift-ascending: once the running total cannot beat the
                // incumbent, no later candidate for this entry can either.
                if (total + drift >= bestTotal)
                    break;
                if (minHueDistance(entry.list[k], chosen) < target)
                    continue;
                chosen.push((((entry.list[k] % 360) + 360) % 360));
                walk(depth + 1, chosen, total + drift);
                chosen.pop();
            }
        }
        walk(0, [], 0);
        if (bestHues === null)
            return null;
        // Undo the most-constrained-first reordering.
        const out = [];
        for (let i = 0; i < candidates.length; i++)
            out[candidates[i].index] = bestHues[i];
        return out;
    }

    // Finds the best hues the broken entries can actually hold, preferring to keep
    // each one recognisably its own color over squeezing out the last few degrees
    // of separation.
    //
    // Canonical ANSI hues sit 60 deg apart, so an entry more than 30 deg off its
    // own canonical hue is nearer a neighbour's slot than its own and stops
    // reading as its own color. A yellow boxed in between a healthy red and a
    // healthy green belongs at orange-yellow with 35 deg of clearance, not at
    // green with 40 -- so separation is relaxed before the drift bound is.
    //
    // That preference has a floor. Two hues under 20 deg apart read as the same
    // swatch, which is the defect this whole pass exists to remove, so when the
    // drift-bounded tier cannot stay legible the wider tier takes over and trades
    // the color name away for visible distinctness. Either way the caller warns.
    function placeBrokenHues(broken, canonical, healthy) {
        const tiers = [[30, 20], [180, 1]];
        for (let t = 0; t < tiers.length; t++) {
            // Feasibility only loosens as the target falls, so binary search finds
            // the largest reachable separation in a handful of probes.
            let lo = tiers[t][1];
            let hi = 40;
            let best = null;
            while (lo <= hi) {
                const mid = Math.floor((lo + hi) / 2);
                const hues = assignHues(broken, canonical, healthy, mid, tiers[t][0]);
                if (hues !== null) {
                    best = hues;
                    lo = mid + 1;
                } else {
                    hi = mid - 1;
                }
            }
            if (best !== null)
                return best;
        }
        // Unreachable for six entries on a 360 deg circle, but a placement is the
        // one thing this function may not fail to produce: the caller has already
        // decided these entries are broken and must not ship as they are.
        console.warn("Colors: no hue placement satisfied even 1 deg of separation; falling back to canonical ANSI hues");
        return broken.map(function (n) {
            return canonical[n];
        });
    }

    function relativeLuminance(hex) {
        const rgb = hexToRgb(hex);
        let acc = 0;
        const weight = [0.2126, 0.7152, 0.0722];
        for (let i = 0; i < 3; i++) {
            const v = rgb[i];
            acc += weight[i] * (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
        }
        return acc;
    }

    function contrastRatio(aHex, bHex) {
        const la = relativeLuminance(aHex);
        const lb = relativeLuminance(bHex);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    // Steps `hex` away from `anchorHex` in HSL lightness until their contrast
    // reaches `target`, or until it runs out of room. Hue and saturation are held
    // fixed, so the pushed color stays in the same family instead of washing out.
    // Shared by the light* pass and the overBackground guard: one place knows how
    // to push a color until it clears a ratio.
    function pushToContrast(hex, anchorHex, target, step, lMin, lMax) {
        const c = rgbToHsl(hexToRgb(hex));
        let l = c.l;
        let out = hex;
        let ratio = contrastRatio(out, anchorHex);
        for (let i = 0; i < 256 && ratio < target; i++) {
            const next = l + step;
            if (next < lMin || next > lMax)
                break;
            l = next;
            out = hslToHex(c.h, c.s, l);
            ratio = contrastRatio(out, anchorHex);
        }
        return {
            hex: out,
            ratio: ratio,
            reached: ratio >= target
        };
    }

    // Derives a light* variant from its base by stepping away until it clears the
    // target, or returns null when the variant it already has is good enough.
    //
    // A fixed lightness delta cannot work here. matugen puts these ANSI bases at
    // 85-90% lightness, where +0.08 buys almost no relative luminance (yellow
    // measured 1.038:1) and any larger step clips to pure white, which is the
    // original defect. Stepping picks the direction that still has headroom, and
    // above mid lightness that direction is downward.
    function deriveLightVariant(baseHex, currentHex) {
        const target = 1.6;
        const base = rgbToHsl(hexToRgb(baseHex));
        if (currentHex !== undefined && rgbToHsl(hexToRgb(currentHex)).chroma >= 0.1 && contrastRatio(currentHex, baseHex) >= target)
            return null;
        const step = base.l > 0.5 ? -0.01 : 0.01;
        // Start at the base so hue and saturation are inherited exactly; the
        // bounds keep the result off both pure white and pure black.
        return pushToContrast(baseHex, baseHex, target, step, 0.15, 0.97);
    }

    // Returns only the entries that had to change, or null when nothing needed
    // changing. Bases are repaired only when broken; light* variants are checked
    // on every entry, because a healthy base can still carry a variant too close
    // to it to tell apart.
    function normalizeAnsi(palette) {
        const names = ["red", "green", "yellow", "blue", "magenta", "cyan"];
        // The real ANSI hues, evenly spaced 60 deg apart. A repaired entry is
        // anchored here so color3 still reads yellow and color6 still reads cyan;
        // the earlier table was nudged off these values and had no anchor at all
        // once the canonical slot was taken.
        const canonicalHue = {
            red: 0,
            yellow: 60,
            green: 120,
            cyan: 180,
            blue: 240,
            magenta: 300
        };
        const hsl = {};
        const broken = {};
        const seen = {};
        const placed = [];
        const healthyS = [];
        for (let i = 0; i < names.length; i++) {
            const n = names[i];
            const key = palette[n].toLowerCase();
            hsl[n] = rgbToHsl(hexToRgb(palette[n]));
            if (hsl[n].chroma < 0.1 || seen[key] === true) {
                broken[n] = true;
            } else {
                seen[key] = true;
                placed.push(hsl[n].h);
                healthyS.push(hsl[n].s);
            }
        }
        healthyS.sort(function (a, b) {
            return a - b;
        });
        const refS = healthyS.length > 0 ? Math.max(0.5, healthyS[Math.floor(healthyS.length / 2)]) : 0.8;
        const out = {};
        const brokenNames = names.filter(function (n) {
            return broken[n] === true;
        });
        const assigned = placeBrokenHues(brokenNames, canonicalHue, placed);
        const finalHues = placed.concat(assigned);
        for (let i = 0; i < brokenNames.length; i++) {
            const n = brokenNames[i];
            const hue = assigned[i];
            // Report per entry, not per palette: a set where one entry is boxed in
            // usually places the rest at canonical with room to spare.
            const others = finalHues.filter(function (h, j) {
                return j !== placed.length + i;
            });
            const achieved = minHueDistance(hue, others);
            const drift = hueDistance(hue, canonicalHue[n]);
            if (achieved < 40 || drift > 30)
                console.warn("Colors: " + n + " could not hold both targets; placed at " + hue.toFixed(1) + " deg, achieving " + achieved.toFixed(1) + " deg separation (target 40) at " + drift.toFixed(1) + " deg canonical drift (bound 30)");
            // Stay close to the lightness the scheme produced, but inside a band
            // where a hue is actually visible: at l = 1.0 every hue is white.
            const l = Math.max(0.35, Math.min(0.85, hsl[n].l));
            out[n] = hslToHex(hue, refS, l);
        }
        // Every light* variant, not only the ones whose base was repaired: a
        // healthy base still arrives with a variant the template lightened by a
        // fixed step, which on these near-white bases lands far below the target.
        for (let i = 0; i < names.length; i++) {
            const n = names[i];
            const ln = "light" + n.charAt(0).toUpperCase() + n.slice(1);
            if (palette[ln] === undefined)
                continue;
            const repairedBase = out[n] !== undefined;
            const baseHex = repairedBase ? out[n] : palette[n];
            // A variant of a repaired base was derived from the broken color, so
            // it is stale by construction and is always re-derived.
            const derived = deriveLightVariant(baseHex, repairedBase ? undefined : palette[ln]);
            if (derived !== null && derived.hex.toLowerCase() !== palette[ln].toLowerCase())
                out[ln] = derived.hex;
        }
        return Object.keys(out).length > 0 ? out : null;
    }

    // Returns the corrected overBackground plus both ratios, or null when the
    // palette already clears WCAG AA body text against the background.
    function guardContrast(overHex, bgHex) {
        const before = contrastRatio(overHex, bgHex);
        if (before >= 4.5)
            return null;
        const step = relativeLuminance(bgHex) < 0.18 ? 0.01 : -0.01;
        const pushed = pushToContrast(overHex, bgHex, 4.5, step, 0, 1);
        return {
            hex: pushed.hex,
            before: before,
            after: pushed.ratio
        };
    }
    // PALETTE-NORMALIZE-END

    property Timer generationTimer: Timer {
        id: generationTimer
        interval: 100
        repeat: false
        onTriggered: {
            colors.normalizePalette();
            qtCtGenerator.generate(colors);
            gtkGenerator.generate(colors);
            pywalGenerator.generate(colors);
            kittyGenerator.generate(colors);
            sddmGenerator.generate();
            greeterGenerator.generate();
            nvChadGenerator.generate(colors);
            discordGenerator.generate(colors);
            spotifyGenerator.generate(colors);
            millenniumGenerator.generate(colors);
            pywalZenGenerator.generate(colors);
        }
    }

    adapter: JsonAdapter {
        property color background: "#1a1111"
        property color blue: "#cebdfe"
        property color blueContainer: "#4c3e76"
        property color blueSource: "#0000ff"
        property color blueValue: "#0000ff"
        property color cyan: "#84d5c4"
        property color cyanContainer: "#005045"
        property color cyanSource: "#00ffff"
        property color cyanValue: "#00ffff"
        property color error: "#ffb4ab"
        property color errorContainer: "#93000a"
        property color green: "#b7d085"
        property color greenContainer: "#3a4d10"
        property color greenSource: "#00ff00"
        property color greenValue: "#00ff00"
        property color inverseOnSurface: "#382e2d"
        property color inversePrimary: "#904a46"
        property color inverseSurface: "#f1dedd"
        property color lightBlue: "#cebdfe"
        property color lightCyan: "#84d5c4"
        property color lightGreen: "#b7d085"
        property color lightMagenta: "#fcb0d5"
        property color lightRed: "#ffb4ab"
        property color lightYellow: "#dec56e"
        property color magenta: "#fcb0d5"
        property color magentaContainer: "#6c3353"
        property color magentaSource: "#ff00ff"
        property color magentaValue: "#ff00ff"
        property color overBackground: "#f1dedd"
        property color overBlue: "#35275e"
        property color overBlueContainer: "#e8ddff"
        property color overCyan: "#00382f"
        property color overCyanContainer: "#9ff2e0"
        property color overError: "#690005"
        property color overErrorContainer: "#ffdad6"
        property color overGreen: "#253600"
        property color overGreenContainer: "#d3ec9e"
        property color overMagenta: "#521d3c"
        property color overMagentaContainer: "#ffd8e8"
        property color overPrimary: "#571d1c"
        property color overPrimaryContainer: "#ffdad7"
        property color overPrimaryFixed: "#3b0809"
        property color overPrimaryFixedVariant: "#733331"
        property color overRed: "#561e19"
        property color overRedContainer: "#ffdad6"
        property color overSecondary: "#442928"
        property color overSecondaryContainer: "#ffdad7"
        property color overSecondaryFixed: "#2c1514"
        property color overSecondaryFixedVariant: "#5d3f3d"
        property color overSurface: "#f1dedd"
        property color overSurfaceVariant: "#d8c2c0"
        property color overTertiary: "#402d04"
        property color overTertiaryContainer: "#ffdea7"
        property color overTertiaryFixed: "#271900"
        property color overTertiaryFixedVariant: "#594319"
        property color overWhite: "#00363d"
        property color overWhiteContainer: "#9eeffd"
        property color overYellow: "#3b2f00"
        property color overYellowContainer: "#fce186"
        property color outline: "#a08c8b"
        property color outlineVariant: "#534342"
        property color primary: "#ffb3ae"
        property color primaryContainer: "#733331"
        property color primaryFixed: "#ffdad7"
        property color primaryFixedDim: "#ffb3ae"
        property color red: "#ffb4ab"
        property color redContainer: "#73332e"
        property color redSource: "#ff0000"
        property color redValue: "#ff0000"
        property color scrim: "#000000"
        property color secondary: "#e7bdb9"
        property color secondaryContainer: "#5d3f3d"
        property color secondaryFixed: "#ffdad7"
        property color secondaryFixedDim: "#e7bdb9"
        property color shadow: "#000000"
        property color surface: "#1a1111"
        property color surfaceBright: "#423736"
        property color surfaceContainer: "#271d1d"
        property color surfaceContainerHigh: "#322827"
        property color surfaceContainerHighest: "#3d3231"
        property color surfaceContainerLow: "#231919"
        property color surfaceContainerLowest: "#140c0c"
        property color surfaceDim: "#1a1111"
        property color surfaceTint: "#ffb3ae"
        property color surfaceVariant: "#534342"
        property color tertiary: "#e2c28c"
        property color tertiaryContainer: "#594319"
        property color tertiaryFixed: "#ffdea7"
        property color tertiaryFixedDim: "#e2c28c"
        property color white: "#82d3e0"
        property color whiteContainer: "#004f58"
        property color whiteSource: "#ffffff"
        property color whiteValue: "#ffffff"
        property color yellow: "#dec56e"
        property color yellowContainer: "#554500"
        property color yellowSource: "#ffff00"
        property color yellowValue: "#ffff00"
        property color sourceColor: "#7f2424"
    }

    property color background: Config.oledMode ? "#000000" : adapter.background

    property color surface: Qt.tint(background, Qt.rgba(adapter.overBackground.r, adapter.overBackground.g, adapter.overBackground.b, 0.1))
    property color surfaceBright: Qt.tint(background, Qt.rgba(adapter.overBackground.r, adapter.overBackground.g, adapter.overBackground.b, 0.2))
    property color surfaceContainer: adapter.surfaceContainer
    property color surfaceContainerHigh: adapter.surfaceContainerHigh
    property color surfaceContainerHighest: adapter.surfaceContainerHighest
    property color surfaceContainerLow: adapter.surfaceContainerLow
    property color surfaceContainerLowest: adapter.surfaceContainerLowest
    property color surfaceDim: adapter.surfaceDim
    property color surfaceTint: adapter.surfaceTint
    property color surfaceVariant: adapter.surfaceVariant

    // Direct color properties from adapter
    property color blue: adapter.blue
    property color blueContainer: adapter.blueContainer
    property color blueSource: adapter.blueSource
    property color blueValue: adapter.blueValue
    property color cyan: adapter.cyan
    property color cyanContainer: adapter.cyanContainer
    property color cyanSource: adapter.cyanSource
    property color cyanValue: adapter.cyanValue
    property color error: adapter.error
    property color errorContainer: adapter.errorContainer
    property color green: adapter.green
    property color greenContainer: adapter.greenContainer
    property color greenSource: adapter.greenSource
    property color greenValue: adapter.greenValue
    property color inverseOnSurface: adapter.inverseOnSurface
    property color inversePrimary: adapter.inversePrimary
    property color inverseSurface: adapter.inverseSurface
    property color lightBlue: adapter.lightBlue
    property color lightCyan: adapter.lightCyan
    property color lightGreen: adapter.lightGreen
    property color lightMagenta: adapter.lightMagenta
    property color lightRed: adapter.lightRed
    property color lightYellow: adapter.lightYellow
    property color magenta: adapter.magenta
    property color magentaContainer: adapter.magentaContainer
    property color magentaSource: adapter.magentaSource
    property color magentaValue: adapter.magentaValue
    property color overBackground: adapter.overBackground
    property color overBlue: adapter.overBlue
    property color overBlueContainer: adapter.overBlueContainer
    property color overCyan: adapter.overCyan
    property color overCyanContainer: adapter.overCyanContainer
    property color overError: adapter.overError
    property color overErrorContainer: adapter.overErrorContainer
    property color overGreen: adapter.overGreen
    property color overGreenContainer: adapter.overGreenContainer
    property color overMagenta: adapter.overMagenta
    property color overMagentaContainer: adapter.overMagentaContainer
    property color overPrimary: adapter.overPrimary
    property color overPrimaryContainer: adapter.overPrimaryContainer
    property color overPrimaryFixed: adapter.overPrimaryFixed
    property color overPrimaryFixedVariant: adapter.overPrimaryFixedVariant
    property color overRed: adapter.overRed
    property color overRedContainer: adapter.overRedContainer
    property color overSecondary: adapter.overSecondary
    property color overSecondaryContainer: adapter.overSecondaryContainer
    property color overSecondaryFixed: adapter.overSecondaryFixed
    property color overSecondaryFixedVariant: adapter.overSecondaryFixedVariant
    property color overSurface: adapter.overSurface
    property color overSurfaceVariant: adapter.overSurfaceVariant
    property color overTertiary: adapter.overTertiary
    property color overTertiaryContainer: adapter.overTertiaryContainer
    property color overTertiaryFixed: adapter.overTertiaryFixed
    property color overTertiaryFixedVariant: adapter.overTertiaryFixedVariant
    property color overWhite: adapter.overWhite
    property color overWhiteContainer: adapter.overWhiteContainer
    property color overYellow: adapter.overYellow
    property color overYellowContainer: adapter.overYellowContainer
    property color outline: adapter.outline
    property color outlineVariant: adapter.outlineVariant
    property color primary: adapter.primary
    property color primaryContainer: adapter.primaryContainer
    property color primaryFixed: adapter.primaryFixed
    property color primaryFixedDim: adapter.primaryFixedDim
    property color red: adapter.red
    property color redContainer: adapter.redContainer
    property color redSource: adapter.redSource
    property color redValue: adapter.redValue
    property color scrim: adapter.scrim
    property color secondary: adapter.secondary
    property color secondaryContainer: adapter.secondaryContainer
    property color secondaryFixed: adapter.secondaryFixed
    property color secondaryFixedDim: adapter.secondaryFixedDim
    property color shadow: adapter.shadow
    property color tertiary: adapter.tertiary
    property color tertiaryContainer: adapter.tertiaryContainer
    property color tertiaryFixed: adapter.tertiaryFixed
    property color tertiaryFixedDim: adapter.tertiaryFixedDim
    property color white: adapter.white
    property color whiteContainer: adapter.whiteContainer
    property color whiteSource: adapter.whiteSource
    property color whiteValue: adapter.whiteValue
    property color yellow: adapter.yellow
    property color yellowContainer: adapter.yellowContainer
    property color yellowSource: adapter.yellowSource
    property color yellowValue: adapter.yellowValue
    property color sourceColor: adapter.sourceColor

    property color criticalText: "#FF6B08"
    property color criticalRed: "#FF0028"

    // Semantic aliases
    property color warning: adapter.yellow
    property color success: adapter.green

    // List of available color names for color pickers (excludes internal/source colors)
    readonly property var availableColorNames: ["background", "surface", "surfaceBright", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow", "surfaceContainerLowest", "surfaceDim", "surfaceTint", "surfaceVariant", "primary", "primaryContainer", "primaryFixed", "primaryFixedDim", "secondary", "secondaryContainer", "secondaryFixed", "secondaryFixedDim", "tertiary", "tertiaryContainer", "tertiaryFixed", "tertiaryFixedDim", "error", "errorContainer", "overBackground", "overSurface", "overSurfaceVariant", "overPrimary", "overPrimaryContainer", "overPrimaryFixed", "overPrimaryFixedVariant", "overSecondary", "overSecondaryContainer", "overSecondaryFixed", "overSecondaryFixedVariant", "overTertiary", "overTertiaryContainer", "overTertiaryFixed", "overTertiaryFixedVariant", "overError", "overErrorContainer", "outline", "outlineVariant", "inversePrimary", "inverseSurface", "inverseOnSurface", "shadow", "scrim", "blue", "blueContainer", "overBlue", "overBlueContainer", "lightBlue", "cyan", "cyanContainer", "overCyan", "overCyanContainer", "lightCyan", "green", "greenContainer", "overGreen", "overGreenContainer", "lightGreen", "magenta", "magentaContainer", "overMagenta", "overMagentaContainer", "lightMagenta", "red", "redContainer", "overRed", "overRedContainer", "lightRed", "yellow", "yellowContainer", "overYellow", "overYellowContainer", "lightYellow", "white", "whiteContainer", "overWhite", "overWhiteContainer"]
}
