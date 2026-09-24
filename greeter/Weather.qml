pragma Singleton

import QtQuick
import Quickshell

// Stand-in for AMBXST's WeatherService, fed from the snapshot's `weather`
// block. Conditions come from the last fetch in the user session; sky, sun
// and time of day are computed live, so they are right even if the fetch is a
// few hours old. The helpers below are copied from
// modules/services/WeatherService.qml so WeatherSky renders identically.
// Those helpers are from Ambxst by Axenide (https://github.com/Axenide/Ambxst),
// AGPL-3.0-or-later.
Singleton {
    id: root

    // Older than this and the conditions are too likely to be wrong to show.
    readonly property real maxAgeMs: 6 * 3600 * 1000

    readonly property var data: Theme.config.weather || null
    property real now: Date.now()
    readonly property bool dataAvailable: data !== null && (now - data.updated) < maxAgeMs

    readonly property real currentTemp: dataAvailable ? data.temp : 0
    readonly property string unit: dataAvailable ? data.unit : "C"
    readonly property string location: dataAvailable ? data.location : ""
    readonly property int weatherCode: dataAvailable ? data.code : 0
    readonly property string sunrise: dataAvailable ? data.sunrise : ""
    readonly property string sunset: dataAvailable ? data.sunset : ""

    property real currentHour: 12

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const d = new Date();
            root.currentHour = d.getHours() + d.getMinutes() / 60;
            root.now = d.getTime();
        }
    }

    // Names WeatherSky expects.
    readonly property bool debugMode: false
    readonly property bool isLoading: false
    function updateWeather() {}

    readonly property var effectiveTimeBlend: calculateTimeBlend(currentHour)
    readonly property real effectiveSunProgress: calculateSunProgress(currentHour, 6.0, 18.0)
    readonly property bool effectiveIsDay: currentHour >= (sunrise.length > 0 ? parseTime(sunrise) : 6.0) && currentHour <= (sunset.length > 0 ? parseTime(sunset) : 18.0)
    readonly property string effectiveWeatherDescription: dataAvailable ? data.description : ""
    readonly property string effectiveWeatherEffect: getWeatherEffect(weatherCode)
    readonly property real effectiveWeatherIntensity: getWeatherIntensity(weatherCode)

    function parseTime(timeStr) {
        if (!timeStr)
            return 0;
        var parts = timeStr.split(":");
        return parseInt(parts[0]) + parseInt(parts[1]) / 60;
    }

    function calculateSunProgress(hour, sunriseH, sunsetH) {
        if (hour >= sunriseH && hour <= sunsetH)
            return (hour - sunriseH) / (sunsetH - sunriseH);
        var nightDuration = 24 - (sunsetH - sunriseH);
        if (hour > sunsetH)
            return (hour - sunsetH) / nightDuration;
        return (hour + (24 - sunsetH)) / nightDuration;
    }

    function calculateTimeBlend(hour) {
        var day = 0, evening = 0, night = 0, t;
        if (hour >= 9 && hour <= 17) {
            day = 1.0;
        } else if (hour > 8 && hour < 9) {
            t = hour - 8; evening = 1.0 - t; day = t;
        } else if (hour > 17 && hour < 18) {
            t = hour - 17; day = 1.0 - t; evening = t;
        } else if (hour >= 6 && hour <= 8) {
            evening = 1.0;
        } else if (hour >= 18 && hour <= 20) {
            evening = 1.0;
        } else if (hour > 5 && hour < 6) {
            t = hour - 5; night = 1.0 - t; evening = t;
        } else if (hour > 20 && hour < 21) {
            t = hour - 20; evening = 1.0 - t; night = t;
        } else {
            night = 1.0;
        }
        return { day: day, evening: evening, night: night };
    }

    function getWeatherEffect(code) {
        if (code === 0 || code === 1) return "clear";
        if (code === 2 || code === 3) return "clouds";
        if (code === 45 || code === 48) return "fog";
        if (code >= 51 && code <= 57) return "drizzle";
        if (code >= 61 && code <= 67) return "rain";
        if (code >= 71 && code <= 77) return "snow";
        if (code >= 80 && code <= 82) return "rain";
        if (code >= 85 && code <= 86) return "snow";
        if (code >= 95 && code <= 99) return "thunderstorm";
        return "clear";
    }

    function getWeatherIntensity(code) {
        const table = { 0: 0, 1: 0, 2: 0.5, 3: 1, 45: 0.5, 48: 0.7, 51: 0.3, 56: 0.3, 53: 0.5, 55: 0.7, 57: 0.7,
            61: 0.4, 63: 0.6, 66: 0.6, 65: 0.9, 67: 0.9, 71: 0.3, 73: 0.5, 75: 0.8, 77: 0.8,
            80: 0.5, 81: 0.7, 82: 1, 85: 0.6, 86: 0.9, 95: 0.8 };
        if (code >= 96)
            return 1.0;
        return table[code] !== undefined ? table[code] : 0.0;
    }
}
