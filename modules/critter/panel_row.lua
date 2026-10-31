-- panel_row.lua — Simple UI
-- The Tiny Critter row of the Quick Settings panel: the module of the Home
-- Screen, built for the width of the panel. The critter, its decorations, its
-- bubble and what it says are the settings of Settings > Tiny Critter; only
-- its position and scale are the panel's own, under the bar's prefix.
-- The statistics are the ones already in memory for today: none is read here.

local UIManager   = require("ui/uimanager")
local SUISettings = require("infra/sui_store")
local VirtualPaths = require("infra/sui_virtual_paths")
local _           = require("infra/sui_i18n").translate

local M = {}

local PFX         = "simpleui_qs_bar_"
local ENABLED_KEY = "simpleui_qs_bar_critter_enabled"

function M.isEnabled() return SUISettings:isTrue(ENABLED_KEY) end
function M.setEnabled(on) SUISettings:saveSetting(ENABLED_KEY, on) end

-- Frees the row `touch_menu` shows, if any.
function M.release(touch_menu)
    local row = touch_menu._sui_qs_critter
    if row then
        touch_menu._sui_qs_critter = nil
        row:free()
    end
end

-- Closes the menu and opens the book `filepath`, from the reader or not.
local function openBook(touch_menu, filepath)
    touch_menu:onClose()
    UIManager:nextTick(function()
        local ReaderUI = package.loaded["apps/reader/readerui"] or require("apps/reader/readerui")
        local virtual = VirtualPaths.toVirtual(filepath)
        if ReaderUI.instance then
            ReaderUI.instance:switchDocument(virtual)
        else
            ReaderUI:showReader(virtual)
        end
    end)
end

-- Opens the settings of the row in a window: the row's own and, apart, the
-- critter's. Closes the menu `touch_menu` first.
local function openSettings(touch_menu)
    local SUIWindow = require("engines/sui_window")
    local function buildRoot(ctx)
        local ctx_menu = SUIWindow.makeCtxMenu(ctx)
        return SUIWindow.MenuTable{
            items      = M.getMenuItems(ctx_menu.refresh, ctx_menu),
            inner_w    = ctx.inner_w,
            repaint    = function() ctx.repaint() end,
            push_stack = function(id, params)
                if type(id) == "string" then ctx.push(id, params) else ctx.push("nested_menu", params) end
            end,
            on_close   = function() end,
        }
    end
    local win = SUIWindow:new{
        name           = "sui_win_context",
        title          = SUIWindow.makeSettingsTitle(_("Tiny Critter")),
        screens        = SUIWindow.makeSettingsScreens(buildRoot),
        position       = "bottom",
    }
    touch_menu:onClose()
    win:show()
end

-- The row for a panel `width` wide, nil when it is off. Registers its tap
-- target in `refs.buttons` and its focus stop in `refs.focus_rows`.
function M.build(touch_menu, refs, width)
    M.release(touch_menu)
    if not M.isEnabled() then return nil end

    local Critter = require("modules/critter/module_critter")
    local stats = (package.loaded["modules/module_stats_provider"]
        or require("modules/module_stats_provider")).getToday()
    local cell
    local row = Critter.build(width, {
        pfx         = PFX,
        stats       = stats or {},
        stats_stale = stats == nil,
        open_fn     = function(filepath) openBook(touch_menu, filepath) end,
        on_hold     = function() openSettings(touch_menu) end,
        kbStops     = function(_id, stops)
            cell = stops[1] and stops[1].widget
        end,
    })
    if cell then
        table.insert(refs.buttons, {
            widget   = cell,
            callback = function() return cell:onTapCritter() end,
        })
        table.insert(refs.focus_rows, { cell })
    end
    touch_menu._sui_qs_critter = row
    return row
end

-- Items of the bar's menu for the row: whether it shows, where the critter
-- stands and how big it is, then the critter's own settings. `refresh` redraws
-- the menu and the open panels; `outer_menu` is the context of the menu the
-- items are shown in, if any.
function M.getMenuItems(refresh, outer_menu)
    local Critter  = require("modules/critter/module_critter")
    local ctx_menu = { pfx = PFX, _ = _, refresh = refresh }
    local items = {
        {
            text           = _("Show Tiny Critter"),
            checked_func   = M.isEnabled,
            keep_menu_open = true,
            callback       = function()
                M.setEnabled(not M.isEnabled())
                refresh()
            end,
        },
    }
    for _i, item in ipairs(Critter.makePlacementItems(ctx_menu)) do items[#items + 1] = item end
    items[#items + 1] = Critter.makeScaleItem(ctx_menu)
    table.insert(items, 1, require("modules/critter/menu").makeSettingsItem(outer_menu))
    return items
end

return M
