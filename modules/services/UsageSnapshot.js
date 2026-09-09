.pragma library

// Legacy snapshots carry an envelope timestamp; keep the original age.
function reading(value, updatedAt) {
    if (!value || !Number.isFinite(value.usedPercent) || !Number.isFinite(value.windowMinutes) || value.windowMinutes <= 0)
        return null;
    const time = value.updatedAt || updatedAt;
    if (!Number.isFinite(time) || time <= 0)
        return null;
    return Object.assign({}, value, {
        usedPercent: Math.max(0, Math.min(100, value.usedPercent)),
        updatedAt: time,
        checkedAt: value.checkedAt || updatedAt || time
    });
}

function select(snapshots, ids) {
    const providers = {};
    for (const id of ids) {
        for (const snapshot of snapshots) {
            const value = reading(snapshot && snapshot.providers && snapshot.providers[id], snapshot && snapshot.updatedAt);
            if (value && (!providers[id] || value.updatedAt > providers[id].updatedAt
                    || (value.updatedAt === providers[id].updatedAt && value.checkedAt > providers[id].checkedAt)))
                providers[id] = value;
        }
    }
    return {providers: providers};
}

function stale(value, now, minutes) {
    if (!value || value.error || !Number.isFinite(value.updatedAt))
        return true;
    const reset = Date.parse(value.resetsAt || "");
    return value.updatedAt > now + 60000 || now - value.updatedAt >= minutes * 120000
        || (Number.isFinite(reset) && reset <= now);
}
