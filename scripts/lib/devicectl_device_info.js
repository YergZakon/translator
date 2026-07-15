const isJXA = typeof ObjC !== "undefined";
if (isJXA) {
    ObjC.import("Foundation");
}

function readJSON(path) {
    if (!isJXA && typeof require === "function") {
        return JSON.parse(require("fs").readFileSync(path, "utf8"));
    }

    const value = $.NSString.stringWithContentsOfFileEncodingError(
        $(path),
        $.NSUTF8StringEncoding,
        null
    );

    if (!value) {
        throw new Error("Cannot read devicectl JSON output");
    }

    return JSON.parse(ObjC.unwrap(value));
}

function scalar(value) {
    if (value === null || value === undefined) {
        return "";
    }
    if (["string", "number", "boolean"].includes(typeof value)) {
        return String(value).replace(/[\t\r\n]/g, " ").trim();
    }
    return "";
}

function atPath(object, path) {
    let current = object;
    for (const component of path.split(".")) {
        if (!current || typeof current !== "object" || !(component in current)) {
            return "";
        }
        current = current[component];
    }
    return scalar(current);
}

function firstPath(object, paths) {
    for (const path of paths) {
        const value = atPath(object, path);
        if (value) {
            return value;
        }
    }
    return "";
}

function findValueByKeys(object, keys, depth) {
    if (!object || typeof object !== "object" || depth > 8) {
        return "";
    }

    for (const key of keys) {
        if (Object.prototype.hasOwnProperty.call(object, key)) {
            const value = scalar(object[key]);
            if (value) {
                return value;
            }
        }
    }

    for (const value of Object.values(object)) {
        const match = findValueByKeys(value, keys, depth + 1);
        if (match) {
            return match;
        }
    }
    return "";
}

function findDeviceArray(object, depth) {
    if (!object || typeof object !== "object" || depth > 8) {
        return [];
    }

    if (Array.isArray(object)) {
        const looksLikeDevices = object.some((item) => item && typeof item === "object" && (
            item.hardwareProperties || item.deviceProperties || item.identifier
        ));
        if (looksLikeDevices) {
            return object;
        }
    }

    for (const [key, value] of Object.entries(object)) {
        if (key === "devices" && Array.isArray(value)) {
            return value;
        }
    }

    for (const value of Object.values(object)) {
        const match = findDeviceArray(value, depth + 1);
        if (match.length > 0) {
            return match;
        }
    }
    return [];
}

function normalizedDevice(device) {
    const identifier = firstPath(device, [
        "identifier",
        "deviceIdentifier",
        "deviceProperties.identifier",
        "hardwareProperties.udid",
        "udid"
    ]);
    const name = firstPath(device, [
        "hardwareProperties.marketingName",
        "deviceProperties.marketingName",
        "deviceProperties.name",
        "name",
        "hardwareProperties.productType"
    ]) || findValueByKeys(device, ["marketingName", "modelName", "productType"], 0);
    const osVersion = firstPath(device, [
        "deviceProperties.osVersionNumber",
        "deviceProperties.osVersion",
        "deviceProperties.operatingSystemVersion",
        "operatingSystemVersion",
        "osVersion"
    ]) || findValueByKeys(device, ["osVersionNumber", "operatingSystemVersion", "osVersion"], 0);
    const kind = firstPath(device, [
        "hardwareProperties.deviceType",
        "hardwareProperties.productType",
        "deviceProperties.deviceType",
        "deviceType"
    ]);

    return {
        identifier,
        name: name || "Unknown iPhone",
        osVersion: osVersion || "Unknown",
        isIPhone: /iphone/i.test([name, kind].join(" "))
    };
}

function devicesFromDocument(document) {
    return findDeviceArray(document, 0).map(normalizedDevice);
}

function run(argv) {
    if (argv.length < 2) {
        throw new Error("Usage: devicectl_device_info.js list|details file.json [device-id]");
    }

    const action = argv[0];
    const document = readJSON(argv[1]);
    const devices = devicesFromDocument(document);

    if (action === "list") {
        return devices
            .filter((device) => device.identifier && device.isIPhone)
            .map((device) => [device.identifier, device.name, device.osVersion].join("\t"))
            .join("\n");
    }

    if (action === "details") {
        const expectedIdentifier = argv[2] || "";
        const selected = devices.find((device) => device.identifier === expectedIdentifier)
            || devices.find((device) => device.isIPhone)
            || normalizedDevice(document);
        return [selected.name, selected.osVersion].join("\t");
    }

    throw new Error("Unknown action: " + action);
}

if (typeof module !== "undefined") {
    module.exports = { devicesFromDocument, normalizedDevice };
}
