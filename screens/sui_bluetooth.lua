-- Read-only Bluetooth state per platform (Kindle, Kobo, PocketBook) for the topbar.

local Device = require("device")

local M = {}

local KINDLE_SERVICE = "com.lab126.btfd"
local BLUEZ_SERVICE  = "org.bluez"
local MTK_SERVICE    = "com.kobo.mtk.bluedroid"
local KOBO_PROVIDER  = "kobo_plugin"
local STATE_TTL      = 5

local _backend    = nil -- "kindle" | "kobo" | "pocketbook" | false
local _kobo_dest  = nil -- D-Bus destination of the Kobo stack, or false
local _state      = nil
local _state_time = 0

local function isPlatform(method)
    local ok, v = pcall(function() return Device[method](Device) end)
    return ok and v == true
end

-- Kindle: integer BTstate via LIPC, or nil if unavailable.
local function readKindle()
    local value
    local ok_lipc, lipc = pcall(require, "liblipclua")
    if ok_lipc and lipc then
        local handle = lipc.init("com.github.koreader.simpleui.bluetooth")
        if handle then
            local ok, state = pcall(handle.get_int_property, handle, KINDLE_SERVICE, "BTstate")
            pcall(handle.close, handle)
            if ok and type(state) == "number" then value = state end
        end
    end
    if value == nil then
        local out = io.popen("lipc-get-prop -i " .. KINDLE_SERVICE .. " BTstate 2>/dev/null", "r")
        if out then
            value = out:read("*n")
            out:close()
        end
    end
    if type(value) ~= "number" then return nil end
    return value ~= 0
end

-- PocketBook: parses `netagent bt status`; nil when BT is not reported.
local function readPocketBook()
    local out = io.popen("netagent bt status 2>/dev/null", "r")
    if not out then return nil end
    local text = out:read("*a") or ""
    out:close()
    if text:find("BT_STATE_OFF", 1, true) then return false end
    if text:find("BT_STATE_", 1, true) then return true end
    return nil
end

-- Kobo: Bluetooth controller exposed by a third-party provider, if any.
local function koboProvider()
    local ok, PluginLoader = pcall(require, "pluginloader")
    if not ok or not PluginLoader then return nil end
    local provider = PluginLoader:getPluginInstance(KOBO_PROVIDER)
    local bt = provider and provider.kobo_bluetooth
    if type(bt) ~= "table" or type(bt.isBluetoothEnabled) ~= "function" then return nil end
    local ok_s, supported = pcall(bt.isDeviceSupported, bt)
    return ok_s and supported and bt or nil
end

-- Kobo: D-Bus destination for models with a Bluetooth stack, or false.
local function koboDestination()
    local model = Device.model
    if model == "Kobo_io" or model == "Kobo_goldfinch" or model == "Kobo_cadmus" then
        return BLUEZ_SERVICE
    end
    if isPlatform("isMTK") then
        local f = io.open("/usr/share/dbus-1/system-services/" .. MTK_SERVICE .. ".service", "r")
        if f then
            f:close()
            return MTK_SERVICE
        end
    end
    return false
end

local function dbusBool(dest, path, args)
    local out = io.popen("dbus-send --system --print-reply --reply-timeout=1500 --dest="
        .. dest .. " " .. path .. " " .. args .. " 2>/dev/null", "r")
    if not out then return nil end
    local text = out:read("*a") or ""
    out:close()
    if text:find("boolean true", 1, true) then return true end
    if text:find("boolean false", 1, true) then return false end
    return nil
end

-- Kobo: adapter is on only when its service runs and reports Powered.
local function readKobo()
    local bt = koboProvider()
    if bt then
        local ok, v = pcall(bt.isBluetoothEnabled, bt)
        return ok and v == true
    end
    if not _kobo_dest then return false end
    if dbusBool("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus.NameHasOwner string:" .. _kobo_dest) ~= true then
        return false
    end
    return dbusBool(_kobo_dest, "/org/bluez/hci0",
        "org.freedesktop.DBus.Properties.Get string:org.bluez.Adapter1 string:Powered") == true
end

local function backend()
    if _backend ~= nil then return _backend end
    if isPlatform("isKindle") then
        _backend = readKindle() ~= nil and "kindle"
    elseif isPlatform("isKobo") then
        _kobo_dest = koboDestination()
        _backend = (_kobo_dest or koboProvider()) and "kobo" or false
    elseif isPlatform("isPocketBook") then
        _backend = readPocketBook() ~= nil and "pocketbook"
    else
        _backend = false
    end
    return _backend
end

-- True when this device can report Bluetooth state.
function M.isAvailable()
    return backend() ~= false
end

-- Current Bluetooth state, cached for STATE_TTL seconds.
function M.isOn()
    local b = backend()
    if not b then return false end
    local now = os.time()
    if _state ~= nil and now - _state_time < STATE_TTL then return _state end
    local v
    if b == "kindle" then
        v = readKindle()
    elseif b == "kobo" then
        v = readKobo()
    else
        v = readPocketBook()
    end
    _state, _state_time = v == true, now
    return _state
end

-- Stores a state reported by an event; nil forces a fresh read.
function M.setState(on)
    if on == nil then
        _state, _state_time = nil, 0
    else
        _state, _state_time = on == true, os.time()
    end
end

-- Forgets the detected backend and cached state.
function M.reset()
    _backend, _kobo_dest = nil, nil
    _state, _state_time = nil, 0
end

return M
