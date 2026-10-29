-- sui_bento_sheet.lua — Simple UI
-- Action sheet that places a module in the bento grid of its page: its width
-- (1/3, 1/2, 2/3, full), its position and, optionally, further actions of the
-- caller, and removes the module. A strip at the top shows the module's row as
-- it will render; tapping another module of the strip selects it. Unless the
-- screen has auto-adjust off, a width change makes the neighbour of the row
-- adjust, and the strip says which module was adjusted. The sheet grows to fit
-- and never paginates.
--
--   BentoSheet.show{
--       mod_id        string     module to place (required)
--       pfx           string     settings prefix of the screen (required)
--       layout        table?     layout being edited; loaded when absent
--       subtitle_for  function?  (id) -> summary shown after the preview label
--                                under the title
--       rows          function?  (id) -> extra action rows { text, sui_icon,
--                                chevron, callback } of a module, listed before
--                                "Remove"; the sheet closes before they run
--       on_changed    function?  after every change has been saved
--       on_removed    function?  after the module has been removed
--   }
--   -> window, or nil when the screen is unknown or the module is not placed
--      on any page.

local ActionSheet     = require("engines/sui_action_sheet")
local BentoPreview    = require("engines/sui_bento_preview")
local Bento           = require("infra/sui_bento")
local Config          = require("infra/sui_config")
local Layout          = require("infra/sui_layout")
local _               = require("infra/sui_i18n").translate
local T               = require("ffi/util").template

local BentoSheet = {}

-- Left/right move the module; up/down move its whole row (captions above).
-- A full-width module owns its row, so only up/down are offered.
local MOVES = {
    { dir = "left",  text = "←" },
    { dir = "right", text = "→" },
    { dir = "up",    text = "↑" },
    { dir = "down",  text = "↓" },
}

-- Rows section with two items to a line.
local function pairs_of(items)
    local rows = {}
    for i = 1, #items, 2 do rows[#rows + 1] = { items[i], items[i + 1] } end
    return { type = "rows", rows = rows }
end

function BentoSheet.show(opts)
    local mod_id, pfx = opts.mod_id, opts.pfx
    local layout_key, screen_id = Layout.screenFor(pfx)
    if not layout_key then return nil end
    local layout = opts.layout or Layout.load(pfx, layout_key)
    if not Layout.findPage(layout, mod_id) then return nil end

    local win, message
    local buildSections

    -- Line under the title for the selected module.
    local function messageLine()
        local subtitle = opts.subtitle_for and opts.subtitle_for(mod_id)
        return subtitle and (_("Home Screen row preview") .. " · " .. subtitle)
               or _("Home Screen row preview")
    end

    -- Which modules besides the placed one changed width.
    local function describe(changed)
        local others = {}
        for _i, id in ipairs(changed) do
            if id ~= mod_id then others[#others + 1] = id end
        end
        if #others == 1 then
            return T(_("%1 adjusted to %2"), Layout.getModuleName(others[1]),
                Config.bentoWidthLabel(others[1], pfx))
        elseif #others > 1 then
            return _("Neighbouring modules adjusted")
        end
    end

    -- Saves and repaints once a change has been made. A move always saves: it
    -- reorders the page even when no width changed.
    local function commit(changed, always)
        if #changed > 0 or always then
            Layout.save(layout, pfx, layout_key, screen_id)
            if opts.on_changed then opts.on_changed() end
        end
        message = describe(changed)
        if win then win:update{ sections = buildSections() } end
    end

    local function setWidth(span)
        commit(Layout.setSpan(layout, pfx, mod_id, span))
    end

    local function move(dir)
        commit(Layout.move(layout, pfx, mod_id, dir), true)
    end

    -- Selects another module of the strip.
    local function select(id)
        mod_id  = id
        message = nil
        win:update{ message = messageLine(), sections = buildSections() }
    end

    local function setClassic(on)
        Config.setBentoClassic(on, pfx)
        commit({}, true)
    end

    -- Free width of the classic layout.
    local function askPct()
        require("features/dialogs/sui_dialogs").spin{
            title    = Layout.getModuleName(mod_id),
            info     = _("Share of the row this module occupies.\n100% = full width. A module that does not fit in the row goes under one of the same width."),
            value    = Config.getBentoPct(mod_id, pfx),
            min      = Bento.CLASSIC_MIN,
            max      = Bento.CLASSIC_MAX,
            step     = Bento.CLASSIC_STEP,
            unit     = "%",
            default  = Bento.CLASSIC_MAX,
            on_apply = function(v)
                Config.setBentoPct(v, mod_id, pfx)
                commit({ mod_id }, true)
            end,
        }
    end

    -- Asks, then takes the module off its page. The sheet is already closed.
    local function confirmRemove()
        require("features/dialogs/sui_dialogs").confirm{
            text        = _("Delete") .. " " .. Layout.getModuleName(mod_id) .. "?",
            ok_callback = function()
                Layout.remove(layout, pfx, mod_id)
                Layout.save(layout, pfx, layout_key, screen_id)
                if opts.on_changed then opts.on_changed() end
                if opts.on_removed then opts.on_removed() end
            end,
        }
    end

    function buildSections()
        local page = Layout.findPage(layout, mod_id)
        local ids, spans = Layout.pageSpans(page, pfx)
        local mode      = Layout.mode(pfx)
        local row_total = mode.classic and Bento.CLASSIC_MAX or Bento.ROW
        local can = Bento.canMove(ids, spans, mod_id, mode)

        local widths = {}
        for _i, option in ipairs(Config.bentoSpanOptions()) do
            widths[#widths + 1] = {
                text     = option.label,
                selected = spans[mod_id] == option.value,
                callback = function() setWidth(option.value) end,
            }
        end
        local full = spans[mod_id] >= row_total
        local moves = {}
        for _i, move_option in ipairs(MOVES) do
            local dir = move_option.dir
            if not (full and (dir == "left" or dir == "right")) then
                moves[#moves + 1] = {
                    text     = move_option.text,
                    enabled  = can[dir],
                    callback = function() move(dir) end,
                }
            end
        end
        local move_labels = full and { { text = _("Position"), from = 1 } } or {
            { text = _("Position"), from = 1 },
            { text = _("Move row"), from = 3 },
        }

        local classic = mode.classic
        local bento_rows = Bento.packFor(ids, spans, mode)
        local row_no, own_row
        for r, candidate in ipairs(bento_rows) do
            for _i, id in ipairs(candidate.ids) do
                if id == mod_id then row_no, own_row = r, candidate end
            end
        end

        -- The row of the module, then what the last change did to it.
        local function preview(ctx)
            return BentoPreview.build(ctx, {
                ids        = own_row.ids,
                cols       = own_row.cols,
                spans      = spans,
                row_total  = row_total,
                label_for  = Layout.getModuleName,
                span_label = classic and function(pct) return pct .. "%" end or Config.bentoSpanLabel,
                highlight  = mod_id,
                on_tap     = select,
            }, T(_("Row %1 of %2"), row_no, #bento_rows), message)
        end

        local sections = { { type = "widget", build = preview } }
        if classic then
            sections[#sections + 1] = ActionSheet.list{ {
                text     = _("Module Width"),
                value    = Config.getBentoPct(mod_id, pfx) .. "%",
                sui_icon = "width",
                chevron  = true,
                callback = askPct,
            } }
        else
            sections[#sections + 1] = { type = "note",     text = _("Width") }
            sections[#sections + 1] = { type = "segments", items = widths }
        end
        sections[#sections + 1] = { type = "note",     columns = #moves, labels = move_labels }
        sections[#sections + 1] = { type = "segments", items = moves }

        sections[#sections + 1] = ActionSheet.list{ {
            text     = _("Free widths"),
            sui_icon = "percent",
            toggle   = classic,
            callback = function() setClassic(not classic) end,
        } }

        -- Actions of the caller, then Remove, two to a line.
        local actions = {}
        for _i, row in ipairs(opts.rows and opts.rows(mod_id) or {}) do
            actions[#actions + 1] = {
                text     = row.text,
                sui_icon = row.sui_icon,
                chevron  = row.chevron,
                callback = function()
                    win:close()
                    row.callback()
                end,
            }
        end
        actions[#actions + 1] = {
            text     = _("Remove"),
            sui_icon = "delete",
            callback = function()
                win:close()
                confirmRemove()
            end,
        }
        sections[#sections + 1] = pairs_of(actions)
        return sections
    end

    win = ActionSheet.show{
        name     = "sui_win_bento_sheet",
        title    = _("Width and Position"),
        icon     = "layout",
        message  = messageLine(),
        sections = buildSections(),
    }
    return win
end

return BentoSheet
