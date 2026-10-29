-- features/sui_wallpaper.lua — SimpleUI wallpaper feature module.
--
-- Owns all state and logic for the "Wallpaper" settings sub-page: the cached
-- screen-sized raster of the wallpaper, every simpleui_style_wallpaper_* /
-- simpleui_wallpaper_*
-- setting getter/setter, the on-disk wallpaper directory scan, the
-- per-surface backdrop strength settings for bars, title bar, pagination and
-- modules (they only ever have a visible effect while a wallpaper is
-- active, so they live here next to the settings that gate them, as part of
-- the same sub-page), the tint / eraser painters, and the night-mode hook
-- that invalidates the cache when night mode is toggled.
--
-- The 0–100 strength scale and the backdrop / frame painters themselves live
-- in infra/sui_backdrop.lua; this module only stores the per-surface values
-- and gates them on a wallpaper being active.
--
-- All settings live under the "simpleui_style_wallpaper_*" namespace (plus
-- the standalone "simpleui_library_backdrop" key) — unchanged from
-- before this module existed, since these are user-persisted keys.
--
-- Consumers:
--   * engines/sui_screen_engine.lua — paints the wallpaper behind the
--     Homescreen / Custom Screens body, and derives ctx.has_wallpaper for
--     content modules from styleGetBgWidget().
--   * infra/sui_patches.lua — paints the same wallpaper behind FM,
--     Collections, History and other fullscreen overlays unless the
--     library scrim is fully solid.
--   * modules/module_collections.lua, modules/module_currently.lua,
--     modules/module_quote.lua, engines/sui_book_grid.lua — these never
--     talk to this module directly; they just read ctx.has_wallpaper,
--     which the homescreen engine computes from this module.
--   * features/library/sui_foldercovers.lua — checks styleGetWallpaperShowInFM
--     / styleGetBgWidget directly to decide whether to paint its title strip
--     over the wallpaper, and reads the strip's backdrop strength.
--   * screens/sui_menu.lua — builds the "Wallpaper" TouchMenu / MenuTable
--     entries, consumed both from the native KOReader menu and from the
--     SUIWindow-based Settings window (screens/sui_settings_window.lua).
--   * bars, title bar, pagination and module chrome — read their strength
--     from here and paint it through infra/sui_backdrop.lua.
--
-- Any wallpaper-image setter here that affects what is on screen frees the
-- cached raster; the caller then refreshes the layout once (the menu's
-- _applyFullLayoutRefresh). Backdrop strength setters only store their value:
-- the image is unaffected, so the caller refreshes with the wallpaper cache
-- kept (ScreenEngine.rebuildLayout({ keep_wallpaper = true })).
-- The night-mode hook has no such caller, so it asks the homescreen engine to
-- rebuild itself through a lazy require() inside the function body (never at
-- file scope): engines/sui_screen_engine.lua requires this module directly, and
-- requiring it back at file scope would create a load-order cycle.

local Device      = require("device")
local logger       = require("logger")
local SUISettings  = require("infra/sui_store")
local Backdrop     = require("infra/sui_backdrop")
local Memory       = require("infra/sui_memory")
local ImageWidget  = require("ui/widget/imagewidget")
local lfs          = require("libs/libkoreader-lfs")
local Screen       = Device.screen

local M = {}

-- ---------------------------------------------------------------------------
-- Cache state
-- ---------------------------------------------------------------------------
-- The wallpaper is decoded once and composed into a single screen-sized
-- raster (white base, image, night-mode handling), so the decoded source and
-- the ImageWidget are released right away. Painting and erasing are plain
-- blits from this raster.
local _raster     = nil   -- screen-sized Blitbuffer of the wallpaper, or nil
local _raster_key = nil   -- (screen w/h, night mode) the raster was built for
local _HANDLE     = {}    -- truthy token handed to callers while a raster exists

-- Setting readers — centralised so _buildRaster stays readable.
local function _wpStretch()     return SUISettings:isTrue("simpleui_style_wallpaper_stretch")        end
local function _wpAutoRotate()  return SUISettings:nilOrTrue("simpleui_style_wallpaper_autorotate")  end
local function _wpInvertNight() return SUISettings:isTrue("simpleui_style_wallpaper_invert_night")   end

-- Wallpaper tint strength (0–99): lighten fades towards white, darken towards
-- black. The lighten key keeps its original name so stored settings stay valid.
local KEY_LIGHTEN  = "simpleui_style_wallpaper_opacity"
local KEY_DARKEN   = "simpleui_style_wallpaper_darken"
local _TINT_MIN, _TINT_MAX = 0, 99
M.TINT_MAX = _TINT_MAX

local function _readTint(key) return SUISettings:readSetting(key, _TINT_MIN) end
local function _saveTint(key, val)
    SUISettings:saveSetting(key, math.max(_TINT_MIN, math.min(_TINT_MAX, val or _TINT_MIN)))
end

-- Opacity of the scrim over the wallpaper on the file manager and the
-- fullscreen lists (History, Collections). Older versions stored a "show on
-- all screens" flag instead: on → 0, off → 100 (the default).
local KEY_LIBRARY = "simpleui_library_backdrop"
local KEY_LEGACY_SHOW_IN_FM = "simpleui_wallpaper_show_in_fm"

-- Returns DataStorage/simpleui/sui_wallpapers/, creating it if needed.
local function _styleWallpapersDir()
    local ok_ds, DataStorage = pcall(require, "datastorage")
    local dir
    if ok_ds and DataStorage then
        dir = DataStorage:getSettingsDir() .. "/simpleui/sui_wallpapers"
    else
        local src = debug.getinfo(1, "S").source or ""
        dir = (src:match("^@(.+/)[^/]+/[^/]+$") or "./") .. "sui_wallpapers"
    end
    require("util").makePath(dir)
    return dir
end

-- Composes the wallpaper file into a screen-sized raster, or returns nil when
-- it cannot be decoded. The image is rotated to match the screen orientation
-- (auto-rotate), then either stretched to the whole screen or fitted with its
-- aspect ratio kept and centred; the uncovered bands stay white.
local function _buildRaster(path, sw, sh)
    local RenderImage = require("ui/renderimage")
    local bb = RenderImage:renderImageFile(path, false, nil, nil)
    if not bb then return nil end

    local rotation_angle = 0
    local img_w, img_h = bb:getWidth(), bb:getHeight()
    if _wpAutoRotate() and (img_w > img_h) ~= (sw > sh) then
        rotation_angle = G_reader_settings:isTrue("imageviewer_rotation_landscape_invert")
            and -90 or 90
        img_w, img_h = img_h, img_w
    end

    -- Size the image is drawn at.
    local tw, th = sw, sh
    if not _wpStretch() then
        local scale = math.min(sw / img_w, sh / img_h)
        tw, th = math.floor(img_w * scale), math.floor(img_h * scale)
    end

    -- The widget owns `bb` from here and frees it with itself. The night-mode
    -- inversion it applies covers only the image, so the bands stay white.
    local widget = ImageWidget:new{
        image                 = bb,
        image_disposable      = true,
        width                 = tw,
        height                = th,
        alpha                 = true,
        original_in_nightmode = not _wpInvertNight(),
        rotation_angle        = rotation_angle,
    }
    local Blitbuffer = require("ffi/blitbuffer")
    local canvas = Blitbuffer.new(sw, sh, Screen.bb:getType())
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local ok = pcall(widget.paintTo, widget, canvas, math.floor((sw - tw) / 2), math.floor((sh - th) / 2))
    widget:free()
    if not ok then
        canvas:free()
        return nil
    end
    return canvas
end

-- Returns a truthy handle while a wallpaper is enabled and decodable, else
-- nil. Painters read the raster themselves, so a handle kept by a caller
-- never points at freed memory. The raster is rebuilt when the screen size or
-- night mode changes; a failed decode is remembered for the same key, so it
-- is not retried on every call.
local function _styleGetBgWidget()
    if not SUISettings:isTrue("simpleui_style_wallpaper_enabled") then return nil end
    local path = SUISettings:readSetting("simpleui_style_wallpaper")
    if not path then return nil end

    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local key = sw .. "x" .. sh .. (Screen.night_mode and "n" or "d")
    if _raster_key ~= key then
        if _raster then _raster:free(); _raster = nil end
        local ok, canvas = pcall(_buildRaster, path, sw, sh)
        if ok then _raster = canvas end
        if not _raster then
            logger.warn("sui_wallpaper: cannot load wallpaper:", path, ok and "" or canvas)
        end
        _raster_key = key
    end
    return _raster and _HANDLE or nil
end

-- Frees the cached raster.
local function _styleFreeBgCache()
    if _raster then _raster:free() end
    _raster     = nil
    _raster_key = nil
end

-- Lazily asks the homescreen engine to free the cache (redundant but
-- harmless — see ScreenEngine.rebuildLayout()) and rebuild its layout so a
-- wallpaper setting change is visible immediately. Lazy-required so this
-- module never creates a load-order cycle with the engine, which requires
-- this module directly — same pattern as features/sui_style.lua.
local function _notifyLayoutChanged()
    local ok, HS = pcall(require, "screens/sui_homescreen")
    if ok and HS and HS.rebuildLayout then
        HS.rebuildLayout()
    end
end

-- ---------------------------------------------------------------------------
-- Public API — wallpaper options (consumed by sui_menu.lua and friends)
-- ---------------------------------------------------------------------------

function M.styleGetWallpaper()
    return SUISettings:readSetting("simpleui_style_wallpaper")
end

-- Settings that only make sense while a wallpaper is active.
local function _resetWallpaperDependents()
    SUISettings:del(KEY_LEGACY_SHOW_IN_FM)
    SUISettings:del(KEY_LIBRARY)
end

function M.styleSetWallpaper(path)
    SUISettings:saveSetting("simpleui_style_wallpaper", path)
    if not path then _resetWallpaperDependents() end
    _styleFreeBgCache()
end

function M.styleGetWallpapersDir()
    return _styleWallpapersDir()
end

-- Raster formats accepted for wallpapers. Exported (not local) so callers
-- offering a file browser over the wallpapers directory — e.g. the
-- "Browse…" entry in screens/sui_menu.lua's Select Wallpaper submenu — stay
-- in sync with this list instead of duplicating it.
M.SUPPORTED_WALLPAPER_EXTS = { jpg=true, jpeg=true, png=true, bmp=true, gif=true, webp=true }

function M.styleScanWallpapers()
    local dir     = _styleWallpapersDir()
    local items   = {}
    local exts    = M.SUPPORTED_WALLPAPER_EXTS
    if lfs.attributes(dir, "mode") == "directory" then
        for fname in lfs.dir(dir) do
            -- Skip hidden entries: ".", "..", and metadata files such as "._name.jpg".
            if fname:sub(1, 1) ~= "." then
                local ext = fname:match("%.([^%.]+)$")
                if ext and exts[ext:lower()] then
                    items[#items + 1] = {
                        label = fname:match("^(.+)%.[^%.]+$") or fname,
                        path  = dir .. "/" .. fname,
                    }
                end
            end
        end
        table.sort(items, function(a, b) return a.label:lower() < b.label:lower() end)
    end
    return items
end

--- Returns a truthy handle while the wallpaper raster is available (or nil).
--- Consumed by sui_patches.lua and the screen engine to decide whether to paint the wallpaper.
function M.styleGetBgWidget()
    return _styleGetBgWidget()
end

function M.getLibraryStrength()
    if SUISettings:get(KEY_LEGACY_SHOW_IN_FM) ~= nil then
        if SUISettings:get(KEY_LIBRARY) == nil and SUISettings:isTrue(KEY_LEGACY_SHOW_IN_FM) then
            Backdrop.saveBackdropStrength(KEY_LIBRARY, Backdrop.STRENGTH_MIN)
        end
        SUISettings:del(KEY_LEGACY_SHOW_IN_FM)
    end
    return Backdrop.readBackdropStrength(KEY_LIBRARY, Backdrop.STRENGTH_MAX)
end

function M.setLibraryStrength(n)
    Backdrop.saveBackdropStrength(KEY_LIBRARY, n)
end

--- Consumed by sui_patches.lua to decide whether to paint the wallpaper into
--- fullscreen overlays (Collections, History, etc.) and the FM. A fully solid
--- scrim hides it, so nothing is painted then.
M.styleGetWallpaperShowInFM = SUISettings.memoize(function()
    if not M.styleGetWallpaperEnabled() or not M.styleGetWallpaper() then return false end
    return M.getLibraryStrength() < Backdrop.STRENGTH_MAX
end)
-- True while a wallpaper is painted behind the file manager: it is shown there
-- and its image could be loaded. Whether an image exists does not depend on
-- the screen size or night mode, which only change the widget built for it, so
-- the answer is kept until a setting changes.
M.isWallpaperPaintedInFM = SUISettings.memoize(function()
    return M.styleGetWallpaperShowInFM() and _styleGetBgWidget() ~= nil
end)

function M.styleGetWallpaperEnabled()
    return SUISettings:isTrue("simpleui_style_wallpaper_enabled")
end
function M.styleSetWallpaperEnabled(on)
    local is_on = on ~= false and true or false
    SUISettings:saveSetting("simpleui_style_wallpaper_enabled", is_on)
    if not is_on then _resetWallpaperDependents() end
    _styleFreeBgCache()
end

function M.styleGetWallpaperStretch()
    return _wpStretch()
end
function M.styleSetWallpaperStretch(on)
    SUISettings:saveSetting("simpleui_style_wallpaper_stretch", on ~= false and true or false)
    _styleFreeBgCache()
end

function M.styleGetWallpaperAutoRotate()
    return _wpAutoRotate()
end
function M.styleSetWallpaperAutoRotate(on)
    SUISettings:saveSetting("simpleui_style_wallpaper_autorotate", on ~= false and true or false)
    _styleFreeBgCache()
end

function M.styleGetWallpaperInvertNight()
    return _wpInvertNight()
end
function M.styleSetWallpaperInvertNight(on)
    SUISettings:saveSetting("simpleui_style_wallpaper_invert_night", on and true or false)
    _styleFreeBgCache()
end

-- Tint strengths are applied at paint time (not baked into the raster); the caller refreshes the layout with the cache kept.
function M.styleGetWallpaperLighten()
    return _readTint(KEY_LIGHTEN)
end
function M.styleSetWallpaperLighten(val)
    _saveTint(KEY_LIGHTEN, val)
end

function M.styleGetWallpaperDarken()
    return _readTint(KEY_DARKEN)
end
function M.styleSetWallpaperDarken(val)
    _saveTint(KEY_DARKEN, val)
end

--- Frees the internal wallpaper raster.
--- Must be called after changing the simpleui_style_* keys directly
--- in SUISettings (e.g. after applying a preset), so that the next paint
--- rebuilds it with the new wallpaper.
--- Consumed by engines/sui_screen_engine.lua (rotation handling,
--- ScreenEngine.rebuildLayout()).
function M.freeCache()
    _styleFreeBgCache()
end

-- ---------------------------------------------------------------------------
-- Transparent bars — these only ever apply while a wallpaper is active (a
-- transparent bar with no wallpaper behind it would just show the plain
-- background), so they live here rather than in the homescreen engine, next
-- to the settings that gate them. They are part of the same "Wallpaper"
-- settings sub-page as every other option above.
--
-- Split into two independent settings (status bar / navigation bar).
-- Migration: if the old unified "simpleui_bars_transparent" key is present
-- we copy its value to both new keys once, then delete the legacy key so
-- it doesn't interfere on subsequent launches.
-- ---------------------------------------------------------------------------
do
    local legacy = "simpleui_bars_transparent"
    if SUISettings:get(legacy) ~= nil then
        local v = SUISettings:isTrue(legacy)
        SUISettings:saveSetting("simpleui_statusbar_transparent", v)
        SUISettings:saveSetting("simpleui_navbar_transparent",    v)
        SUISettings:del(legacy)
    end
end

-- ---------------------------------------------------------------------------
-- Surfaces that sit over the wallpaper (scale, tones and painters:
-- infra/sui_backdrop.lua).
--
-- Opacity applies only while a wallpaper is active; without one a surface
-- keeps the opacity of its native look. Tone and frame always apply.
-- Setters only store the value; the caller refreshes the UI once afterwards.
-- Legacy settings migrate once on first read:
--   status / navigation bar transparent true  → opacity 0
--   module solid_bg true                      → opacity 100
-- ---------------------------------------------------------------------------
local STRENGTH_MIN, STRENGTH_MAX = Backdrop.STRENGTH_MIN, Backdrop.STRENGTH_MAX

local KEY_NAVBAR_STYLE = "simpleui_bar_style"
local KEY_NAVBAR_LAYOUT = "simpleui_bar_layout"

-- The full-width bars, keyed by kind. `legacy_transparent` is the flag older
-- versions stored instead of an opacity; `native` is the opacity the bar has
-- without a wallpaper: 100 where the bar paints its own fill, 0 where the
-- host draws it.
local BARS = {
    statusbar  = { key = "simpleui_statusbar",  native = STRENGTH_MAX, legacy_transparent = "simpleui_statusbar_transparent" },
    navbar     = { key = "simpleui_navbar",     native = STRENGTH_MAX, legacy_transparent = "simpleui_navbar_transparent" },
    pagination = { key = "simpleui_pagination", native = STRENGTH_MIN },
    titlebar   = { key = "simpleui_titlebar",   native = STRENGTH_MIN },
}

local BAR_SURFACE = {}
for kind, bar in pairs(BARS) do
    BAR_SURFACE[kind] = Backdrop.surface(kind, bar.key)
end

-- Surface descriptor of a bar kind, for the menu and for resetting.
function M.barSurface(kind)
    return BAR_SURFACE[kind]
end

-- Surface of the title/author strip below Library covers and the global
-- opacity of modules that set none of their own.
M.COVER_STRIP = Backdrop.surface("cover_strip", "simpleui_cover_strip")
local MODULE_SURFACE = Backdrop.surface("module", "simpleui_module")

-- True while a wallpaper is enabled and selected. Surfaces that only exist
-- over a wallpaper fall back to their native look otherwise.
function M.isWallpaperActive()
    return M.styleGetWallpaperEnabled() and M.styleGetWallpaper() ~= nil
end

-- Opacity stored for a bar, whether or not a wallpaper is active.
function M.getBarStrength(kind)
    local surface, legacy = BAR_SURFACE[kind], BARS[kind].legacy_transparent
    if legacy and SUISettings:get(legacy) ~= nil then
        if SUISettings:get(surface.keys.strength) == nil and SUISettings:isTrue(legacy) then
            Backdrop.saveStrength(surface, STRENGTH_MIN)
        end
        SUISettings:del(legacy)
    end
    return Backdrop.readStrength(surface)
end

function M.setBarStrength(kind, n)
    Backdrop.saveStrength(BAR_SURFACE[kind], n)
end

local function _resolveBar(kind)
    local surface = BAR_SURFACE[kind]
    if M.isWallpaperActive() then
        return Backdrop.resolve(surface, M.getBarStrength(kind))
    end
    local strength = BARS[kind].native
    local customised = Backdrop.readTone(surface) ~= Backdrop.TONE.WHITE or Backdrop.readFrame(surface)
    return Backdrop.resolve(surface, customised and STRENGTH_MAX or strength)
end

local _resolvedBars = {}  -- kind -> memoized _resolveBar

-- Look of a bar as it is painted (see Backdrop.resolve). Without a wallpaper
-- the opacity is the bar's native one, raised to solid when the user chose a
-- tone or frame the native look does not have. Rebuilt only when a setting
-- changes, so the returned table is shared and must not be modified.
function M.resolveBar(kind)
    local resolved = _resolvedBars[kind]
    if not resolved then
        resolved = SUISettings.memoize(function() return _resolveBar(kind) end)
        _resolvedBars[kind] = resolved
    end
    return resolved()
end

-- True while a bar is fully transparent and the wallpaper image is loaded, so
-- the bars show the wallpaper instead of a plain surface.
function M.barsRevealWallpaper()
    if M.resolveBar("navbar").strength > 0 and M.resolveBar("statusbar").strength > 0 then
        return false
    end
    return _styleGetBgWidget() ~= nil
end

-- Look of a card or button surface as painted. Opacity applies only over a
-- wallpaper; without one the surface is solid.
function M.resolveSurface(surface)
    return Backdrop.resolve(surface, not M.isWallpaperActive() and STRENGTH_MAX or nil)
end

-- Paints the pagination bar surface (tone, opacity and frame) across the full
-- width of the rows y .. y + h. Nothing is painted while the surface is fully
-- transparent and has no frame.
function M.paintPaginationBar(bb, y, h)
    local surface = M.resolveBar("pagination")
    if surface.strength > 0 or surface.border_sz > 0 then
        Backdrop.paintBar(bb, y, h, surface, "top")
    end
end

-- True while a bar surface is painted behind native controls (the pagination
-- bar and the title bar). Those controls must then draw without their own
-- white background.
M.paintsBehindNativeControls = SUISettings.memoize(function()
    return M.resolveBar("pagination").strength > 0 or M.resolveBar("titlebar").strength > 0
end)

-- Navigation bar layouts. Older versions stored a style instead:
--   default → full width; framed → floating with its frame; bare → floating
--   without frame and fully transparent. A full-width bar keeps the rule it
--   always had, except when it was transparent.
M.NAVBAR_LAYOUT = { FULL = "full", FLOATING = "floating" }

function M.getNavbarLayout()
    local stored = SUISettings:readSetting(KEY_NAVBAR_LAYOUT)
    if stored then return stored end

    local style = SUISettings:readSetting(KEY_NAVBAR_STYLE) or "default"
    local surface = BAR_SURFACE.navbar
    local layout = style == "default" and M.NAVBAR_LAYOUT.FULL or M.NAVBAR_LAYOUT.FLOATING
    if style == "bare" then
        Backdrop.saveStrength(surface, STRENGTH_MIN)
        Backdrop.saveFrame(surface, false)
    elseif style == "default" and M.getBarStrength("navbar") <= STRENGTH_MIN
            and SUISettings:get(surface.keys.frame) == nil then
        Backdrop.saveFrame(surface, false)
    end
    SUISettings:saveSetting(KEY_NAVBAR_LAYOUT, layout)
    SUISettings:del(KEY_NAVBAR_STYLE)
    return layout
end

function M.setNavbarLayout(layout)
    SUISettings:saveSetting(KEY_NAVBAR_LAYOUT, layout)
end

-- Module opacity; without a wallpaper there is no backdrop to paint.
-- With (pfx, id): per-module override, migrating legacy solid_bg once. Without
-- an override the result is `default`, or the global default when that is nil.
-- With no args: global default.
function M.getModuleBackdropStrength(pfx, id, default)
    if not M.isWallpaperActive() then return STRENGTH_MIN end
    if type(pfx) ~= "string" or not id then
        return Backdrop.readStrength(MODULE_SURFACE)
    end
    local key = pfx .. id .. "_backdrop"
    local solid_key = pfx .. id .. "_solid_bg"
    local n = Backdrop.readBackdropStrength(key)
    -- A stored 0 next to an explicit solid_bg=false is a stale migration
    -- result (meaning "not solid", not "force transparent"): drop it.
    if n == STRENGTH_MIN and SUISettings:get(solid_key) ~= nil and not SUISettings:isTrue(solid_key) then
        SUISettings:del(key)
        n = nil
    end
    if n then return n end
    -- Only solid_bg=true is a positive legacy signal; false means inherit.
    if SUISettings:isTrue(solid_key) then
        SUISettings:saveSetting(key, STRENGTH_MAX)
        return STRENGTH_MAX
    end
    return default or M.getModuleBackdropStrength()
end

function M.setModuleBackdropStrength(n, pfx, id)
    local key = (type(pfx) == "string" and id) and (pfx .. id .. "_backdrop") or MODULE_SURFACE.keys.strength
    Backdrop.saveBackdropStrength(key, n)
end

-- Applies the lighten / darken tint over a region that already holds the
-- wallpaper. Both are cheap in-place blitbuffer operations.
--
-- Night mode inverts the frame after painting, so a tint written towards white
-- reaches the screen as a darkening (and vice versa). The strengths are swapped
-- in night mode so each setting keeps its on-screen meaning.
function M.paintTint(bb, x, y, w, h)
    local lighten, darken = _readTint(KEY_LIGHTEN), _readTint(KEY_DARKEN)
    if Screen.night_mode then lighten, darken = darken, lighten end
    if lighten > 0 then bb:lightenRect(x, y, w, h, lighten / 100) end
    if darken  > 0 then bb:darkenRect(x, y, w, h, darken / 100) end
end

-- Paints the library scrim over the rect (x, y, w, h); nothing while it is
-- fully transparent.
function M.paintLibraryScrim(bb, x, y, w, h)
    Backdrop.paintBackdrop(bb, x, y, w, h, M.getLibraryStrength())
end

-- Paints the wallpaper full-screen, anchored at y=0, then its tint. The raster
-- is opaque, so whatever the buffer held before (e.g. a closed book page) is
-- replaced.
function M.paintBackground(bb, x)
    if not _styleGetBgWidget() then return end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    bb:blitFrom(_raster, x, 0, 0, 0, sw, sh)
    M.paintTint(bb, x, 0, sw, sh)
end

-- Restore a dirty rect to the same appearance module chrome leaves behind:
-- wallpaper (or solid surface) plus an optional backdrop scrim.
--
-- strength / radius / color are optional. Omit them (or pass strength 0) for
-- a plain base restore. Pass the module's chrome strength and colour so gaps
-- inside a card keep the configured opacity and tone after a partial redraw
-- (pagination, swipe).
--
-- The raster is the one paintBackground blits, so it already matches
-- full-frame wallpaper paint including night-mode handling. No extra invert
-- is applied here.
function M.paintEraser(bb, x, y, w, h, strength, radius, color)
    if w <= 0 or h <= 0 then return end
    strength = Backdrop.clampBackdropStrength(strength) or STRENGTH_MIN

    -- Opaque chrome: surface fill alone is the final pixel state.
    if strength >= STRENGTH_MAX then
        Backdrop.paintBackdrop(bb, x, y, w, h, STRENGTH_MAX, radius or 0, color)
        return
    end

    -- Base layer: wallpaper sub-rect, or solid surface when none is set.
    local src = _styleGetBgWidget() and _raster
    local restored = false
    if src then
        local sw = src:getWidth()
        local sh = src:getHeight()
        local rx, ry, rw, rh = x, y, w, h
        if rx < 0 then rw = rw + rx; rx = 0 end
        if ry < 0 then rh = rh + ry; ry = 0 end
        if rx < sw and ry < sh then
            if rx + rw > sw then rw = sw - rx end
            if ry + rh > sh then rh = sh - ry end
            if rw > 0 and rh > 0 then
                restored = pcall(function()
                    bb:blitFrom(src, rx, ry, rx, ry, rw, rh)
                    M.paintTint(bb, rx, ry, rw, rh)
                end)
            end
        end
    end
    if not restored then
        local SUIStyle = require("features/sui_style")
        Backdrop.withInverseGuard(bb, function()
            bb:paintRect(x, y, w, h, SUIStyle.COLOR.surface)
        end)
    end

    Backdrop.paintBackdrop(bb, x, y, w, h, strength, radius or 0, color)
end

-- ---------------------------------------------------------------------------
-- Night-mode change — free the wallpaper cache and rebuild the layout so the
-- next _styleGetBgWidget() call rebuilds the raster with the new inversion
-- state. Called by the night-mode hook in infra/sui_patches.lua.
-- ---------------------------------------------------------------------------
function M.onNightModeChanged()
    _styleFreeBgCache()
    _notifyLayoutChanged()
end

Memory.onReset(M.freeCache)

return M
