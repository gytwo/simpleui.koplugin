-- settings.lua — Simple UI
-- Settings of the critter that are the same on every screen: which critter it
-- is, the look of its bubble and how it behaves. What depends on where it is
-- shown (side, alignment, scale, decorations, text) stays under the screen prefix.

local Config      = require("infra/sui_config")
local SUISettings = require("infra/sui_store")

local M = {}

M.STYLES         = { "pixel", "smooth" }
M.DEFAULT_STYLE  = "pixel"
M.SOURCES        = { "builtin", "both", "custom" }
M.DEFAULT_SOURCE = "both"

-- Decorations a side of the group holds at most, and what each side holds
-- until the user arranges it.
M.DECOR_PER_SIDE = 2
local DEFAULT_DECOR = { left = { "bookcase", "lamp" }, right = {} }

local KEY_PICK   = "simpleui_critter_cfg_pick"           -- id of the chosen critter
local KEY_STYLE  = "simpleui_critter_cfg_bubble_style"   -- "pixel" | "smooth"
local KEY_SOURCE = "simpleui_critter_cfg_source"         -- "builtin" | "both" | "custom"
local KEY_REACT  = "simpleui_critter_cfg_reactions"      -- false = no reactions to events
local KEY_CAT    = "simpleui_critter_cfg_cat_"           -- .. category id; false = category off
local KEY_DECOR  = "simpleui_critter_cfg_decor_"         -- .. side; ids of the decorations of that side, left to right
local KEY_NAME   = "simpleui_critter_user_name"          -- name the user told the critter

-- Where the same settings lived before, under the prefix of the default screen.
local LEGACY_PFX = "simpleui_hs_"
local LEGACY = {
    [KEY_PICK]   = "critter_pick",
    [KEY_STYLE]  = "critter_bubble_style",
    [KEY_SOURCE] = "critter_source",
    [KEY_REACT]  = "critter_reactions",
}
local LEGACY_CAT = "critter_cat_"
local LEGACY_DECOR = "critter_decor_"

function M.pick() return SUISettings:get(KEY_PICK) end
function M.setPick(id) SUISettings:set(KEY_PICK, id) end

function M.bubbleStyle() return Config.readChoice(KEY_STYLE, M.STYLES, M.DEFAULT_STYLE) end
function M.setBubbleStyle(v) SUISettings:set(KEY_STYLE, v) end

function M.source() return Config.readChoice(KEY_SOURCE, M.SOURCES, M.DEFAULT_SOURCE) end
function M.setSource(v) SUISettings:set(KEY_SOURCE, v) end

function M.reactionsOn() return SUISettings:nilOrTrue(KEY_REACT) end
function M.setReactions(on) SUISettings:set(KEY_REACT, on) end

-- Ids of the decorations of `side`, left to right: the ones the user arranged,
-- the default ones until then.
function M.decorIds(side)
    local ids = SUISettings:get(KEY_DECOR .. side)
    return { unpack(type(ids) == "table" and ids or DEFAULT_DECOR[side]) }
end
function M.setDecorIds(side, ids) SUISettings:set(KEY_DECOR .. side, ids) end

-- Name the user gave the critter, nil when there is none.
function M.userName()
    local name = SUISettings:get(KEY_NAME)
    return type(name) == "string" and name ~= "" and name or nil
end
function M.setUserName(name) SUISettings:set(KEY_NAME, name ~= "" and name or nil) end

function M.categoryOn(id) return SUISettings:nilOrTrue(KEY_CAT .. id) end
function M.setCategory(id, on) SUISettings:set(KEY_CAT .. id, on) end

-- Copies the values the default screen had into the global keys that are still
-- unset. The other screens' values are left where they are.
function M.migrateLegacy()
    local function copy(new_key, legacy_key)
        local value = SUISettings:get(LEGACY_PFX .. legacy_key)
        if SUISettings:get(new_key) == nil and value ~= nil then
            SUISettings:set(new_key, value)
        end
    end
    for new_key, legacy_key in pairs(LEGACY) do copy(new_key, legacy_key) end
    for _i, side in ipairs({ "left", "right" }) do
        copy(KEY_DECOR .. side, LEGACY_DECOR .. side)
    end
    for _i, cat in ipairs(require("modules/critter/phrases").CATEGORIES) do
        copy(KEY_CAT .. cat.id, LEGACY_CAT .. cat.id)
    end
end

return M
