-- sui_migrations.lua — Simple UI
-- One-time settings and user-data migrations, run at plugin init. Each step is
-- guarded by its own flag and runs inside pcall, so a failure never blocks the
-- plugin from loading. main.lua requires this module only while the first or last
-- flag is missing; an already migrated install never loads it.

local logger      = require("logger")
local SUISettings = require("infra/sui_store")

local M = {}

function M.run()
    -- -------------------------------------------------------------------
    -- User-data migration (runs once per install / once after upgrade).
    --
    -- v1: move user files out of the plugin folder into DataStorage so
    --     they survive plugin updates, and normalise all settings keys to
    --     the simpleui_ / navbar_ namespace.
    -- -------------------------------------------------------------------
    if not G_reader_settings:isTrue("simpleui_userdata_migrated_v1") then
        pcall(function()
            local ok_ds, DataStorage = pcall(require, "datastorage")
            local ok_lfs, lfs        = pcall(require, "libs/libkoreader-lfs")
            local ok_ffi, ffiutil    = pcall(require, "ffi/util")
            if not (ok_ds and ok_lfs and ok_ffi) then return end

            local data_dir = DataStorage:getSettingsDir() .. "/simpleui"

            -- ── 1. Migrate user files (copy, never overwrite) ─────────
            -- Directory structure is guaranteed by the startup block in main.lua.
            -- Resolve plugin root from this file's path (one level below it).
            local src_info   = debug.getinfo(1, "S").source or ""
            local plugin_root = src_info:sub(1,1) == "@"
                and src_info:sub(2):match("^(.*)/infra/[^/]+$") or nil
            if plugin_root and plugin_root:sub(1,1) ~= "/" then
                local ok_lfs2, lfs2 = pcall(require, "libs/libkoreader-lfs")
                local cwd = ok_lfs2 and lfs2 and lfs2.currentdir()
                if cwd then plugin_root = cwd .. "/" .. plugin_root end
            end

            if plugin_root then
                -- Copy files from src/ to dst/ (never overwrite existing).
                local function copyDirContents(from_dir, to_dir)
                    if lfs.attributes(from_dir, "mode") ~= "directory" then return end
                    for fname in lfs.dir(from_dir) do
                        if fname ~= "." and fname ~= ".." then
                            local src_f = from_dir .. "/" .. fname
                            local dst_f = to_dir .. "/" .. fname
                            if lfs.attributes(src_f, "mode") == "file"
                                and lfs.attributes(dst_f, "mode") ~= "file" then
                                ffiutil.copyFile(src_f, dst_f)
                            end
                        end
                    end
                end

                -- Removes all plain files inside dir, then the dir itself.
                -- Skips silently if dir doesn't exist or still has subdirs.
                local function removeDirIfEmpty(dir)
                    if lfs.attributes(dir, "mode") ~= "directory" then return end
                    for fname in lfs.dir(dir) do
                        if fname ~= "." and fname ~= ".." then
                            local p = dir .. "/" .. fname
                            if lfs.attributes(p, "mode") == "file" then
                                os.remove(p)
                            end
                        end
                    end
                    lfs.rmdir(dir)  -- only succeeds when empty
                end

                -- icons/custom → DataStorage/simpleui/sui_icons/
                -- then remove the now-redundant in-plugin directory.
                copyDirContents(plugin_root .. "/icons/custom",
                                data_dir    .. "/sui_icons")
                removeDirIfEmpty(plugin_root .. "/icons/custom")

                -- modules/custom_quotes → DataStorage/simpleui/sui_quotes/
                -- then remove the now-redundant in-plugin directory.
                copyDirContents(plugin_root .. "/modules/custom_quotes",
                                data_dir    .. "/sui_quotes")
                removeDirIfEmpty(plugin_root .. "/modules/custom_quotes")
            end

            -- ── 2. Migrate renamed settings keys ──────────────────────
            -- Each entry: { old_key, new_key }
            local key_renames = {
                { "sui_tbr_list",             "simpleui_tbr_list"                    },
                { "quote_deck_order",          "simpleui_quote_deck_order"            },
                { "quote_deck_pos",            "simpleui_quote_deck_pos"              },
                { "quote_deck_count",          "simpleui_quote_deck_count"            },
                { "quote_hl_deck_order",       "simpleui_quote_hl_deck_order"         },
                { "quote_hl_deck_pos",         "simpleui_quote_hl_deck_pos"           },
                { "quote_hl_deck_count",       "simpleui_quote_hl_deck_count"         },
                { "quote_custom_deck_order",   "simpleui_quote_custom_deck_order"     },
                { "quote_custom_deck_pos",     "simpleui_quote_custom_deck_pos"       },
                { "quote_custom_deck_count",   "simpleui_quote_custom_deck_count"     },
                { "quote_custom_deck_file",    "simpleui_quote_custom_deck_file"      },
                -- quote_source and quote_custom_file are per-instance (prefixed
                -- with navbar_homescreen_ at runtime); migrate all known slots.
                { "navbar_homescreen_quote_source",      "navbar_homescreen_simpleui_quote_source"      },
                { "navbar_homescreen_quote_custom_file", "navbar_homescreen_simpleui_quote_custom_file" },
            }
            for _, pair in ipairs(key_renames) do
                local old_key, new_key = pair[1], pair[2]
                local val = G_reader_settings:readSetting(old_key)
                if val ~= nil and G_reader_settings:readSetting(new_key) == nil then
                    G_reader_settings:saveSetting(new_key, val)
                end
                G_reader_settings:delSetting(old_key)
            end

            logger.info("simpleui: userdata migration v1 complete")
        end)
        G_reader_settings:saveSetting("simpleui_userdata_migrated_v1", true)
    end
    -- -------------------------------------------------------------------
    -- Settings migration v2: move all navbar_* and simpleui_* keys from
    -- G_reader_settings into SUISettings (the dedicated per-plugin store).
    --
    -- This runs once on first boot after the Phase-3 refactor.  It is safe
    -- to re-run if interrupted: keys that already exist in SUISettings are
    -- not overwritten; keys successfully copied are removed from
    -- G_reader_settings.
    -- -------------------------------------------------------------------
    if not SUISettings:isTrue("simpleui_settings_migrated_v2") then
        pcall(function()
            -- Enumerate every key currently stored in G_reader_settings
            -- and migrate the ones owned by SimpleUI.
            local raw = G_reader_settings.data  -- LuaSettings exposes .data
            if type(raw) ~= "table" then return end

            -- Collect owned keys first; deleting from raw while iterating
            -- it with pairs() has undefined behaviour in Lua and can cause
            -- entries to be skipped.
            local to_migrate = {}
            for k, v in pairs(raw) do
                local owned = (type(k) == "string")
                    and (k:sub(1, 7) == "navbar_" or k:sub(1, 9) == "simpleui_")
                    -- Keep the v1 and v2 migration flags in G_reader_settings
                    -- so they survive a factory reset of sui_settings.lua.
                    and k ~= "simpleui_userdata_migrated_v1"
                if owned then
                    to_migrate[#to_migrate + 1] = { k = k, v = v }
                end
            end

            local migrated = 0
            for _, entry in ipairs(to_migrate) do
                local k, v = entry.k, entry.v
                -- Only copy if SUISettings does not already have the key
                -- (e.g. the user already made changes after the code update).
                if SUISettings:get(k) == nil then
                    SUISettings:set(k, v)
                end
                G_reader_settings:delSetting(k)
                migrated = migrated + 1
            end

            SUISettings:flush()
            logger.info("simpleui: settings migration v2 complete —", migrated, "keys moved to SUISettings")
        end)
        SUISettings:set("simpleui_settings_migrated_v2", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------
    -- Settings migration v3: rename all navbar_* keys inside SUISettings
    -- to the canonical simpleui_* namespace.
    --
    -- Two passes:
    --   1. Fixed renames  — explicit old → new map (fast, readable).
    --   2. Dynamic prefix — bulk rename of per-slot / per-id keys that are
    --      built at runtime via string concatenation.
    --
    -- Rules:
    --   • Only copies when the destination key is absent (never overwrites).
    --   • Old key is always deleted, even when the copy is skipped.
    --   • The whole block runs inside pcall — a crash must never prevent
    --     the plugin from loading on a resource-constrained e-reader.
    --   • Guarded by simpleui_settings_migrated_v3 so it runs at most once.
    -- -------------------------------------------------------------------
    if not SUISettings:isTrue("simpleui_settings_migrated_v3") then
        pcall(function()
            -- ── 1. Fixed renames ─────────────────────────────────────────
            local fixed_renames = {
                -- Bottom bar — general
                { "navbar_enabled",                      "simpleui_bar_enabled"                   },
                { "navbar_mode",                         "simpleui_bar_mode"                      },
                { "navbar_bar_size",                     "simpleui_bar_size"                      },
                { "navbar_bar_size_pct",                 "simpleui_bar_size_pct"                  },
                { "navbar_hide_separator",               "simpleui_bar_hide_separator"            },
                { "navbar_bottom_margin_pct",            "simpleui_bar_bottom_margin_pct"         },
                { "navbar_icon_scale_pct",               "simpleui_bar_icon_scale_pct"            },
                { "navbar_label_scale_pct",              "simpleui_bar_label_scale_pct"           },
                { "navbar_rs_text_scale_pct",            "simpleui_bar_rs_text_scale_pct"         },
                -- Bottom bar — pagination / pager
                { "navbar_pagination_visible",           "simpleui_bar_pagination_visible"        },
                { "navbar_pagination_size",              "simpleui_bar_pagination_size"           },
                { "navbar_pagination_show_subtitle",     "simpleui_bar_pagination_show_subtitle"  },
                { "navbar_navpager_enabled",             "simpleui_bar_navpager_enabled"          },
                { "navbar_dotpager_always",              "simpleui_bar_dotpager_always"           },
                -- Bottom bar — tabs & settings
                { "navbar_tabs",                         "simpleui_bar_tabs"                      },
                { "navbar_bottombar_settings_on_hold",   "simpleui_bar_settings_on_hold"          },
                -- Top bar
                { "navbar_topbar_enabled",               "simpleui_topbar_enabled"                },
                { "navbar_topbar_config",                "simpleui_topbar_config"                 },
                { "navbar_topbar_custom_text",           "simpleui_topbar_custom_text"            },
                { "navbar_topbar_settings_on_hold",      "simpleui_topbar_settings_on_hold"       },
                { "navbar_topbar_swipe_indicator",       "simpleui_topbar_swipe_indicator"        },
                { "navbar_topbar_wifi_hide_when_off",    "simpleui_topbar_wifi_hide_when_off"     },
                { "navbar_topbar_size_pct",              "simpleui_topbar_size_pct"               },
                -- Homescreen bar — fixed keys
                { "navbar_homescreen_pagination_hidden", "simpleui_hs_pagination_hidden"          },
                { "navbar_homescreen_settings_on_hold",  "simpleui_hs_settings_on_hold"           },
                { "navbar_homescreen_overflow_warn",     "simpleui_hs_overflow_warn"              },
                { "navbar_hs_return_to_book_folder",     "simpleui_hs_return_to_book_folder"      },
                { "navbar_homescreen_module_scale",      "simpleui_hs_module_scale"               },
                { "navbar_homescreen_label_scale",       "simpleui_hs_label_scale"                },
                { "navbar_homescreen_scale_linked",      "simpleui_hs_scale_linked"               },
                -- Reading goal
                { "navbar_reading_goal",                 "simpleui_reading_goal"                  },
                { "navbar_reading_goal_physical",        "simpleui_reading_goal_physical"         },
                { "navbar_daily_reading_goal_secs",      "simpleui_daily_reading_goal_secs"       },
                -- Reading goals module display
                { "navbar_reading_goals_show_annual",    "simpleui_reading_goals_show_annual"     },
                { "navbar_reading_goals_show_daily",     "simpleui_reading_goals_show_daily"      },
                { "navbar_reading_goals_layout",         "simpleui_reading_goals_layout"          },
                -- Collections module
                { "navbar_collections_list",             "simpleui_collections_list"              },
                { "navbar_collections_covers",           "simpleui_collections_covers"            },
                { "navbar_collections_badge_position",   "simpleui_collections_badge_position"    },
                { "navbar_collections_badge_color",      "simpleui_collections_badge_color"       },
                { "navbar_collections_badge_hidden",     "simpleui_collections_badge_hidden"      },
                -- Custom quick actions — list & migration flag
                { "navbar_custom_qa_list",               "simpleui_cqa_list"                      },
                { "navbar_custom_qa_migrated_v1",        "simpleui_cqa_migrated_v1"               },
            }

            local migrated = 0

            for _, pair in ipairs(fixed_renames) do
                local old_k, new_k = pair[1], pair[2]
                local val = SUISettings:get(old_k)
                if val ~= nil then
                    if SUISettings:get(new_k) == nil then
                        SUISettings:set(new_k, val)
                    end
                    SUISettings:del(old_k)
                    migrated = migrated + 1
                end
            end

            -- ── 2. Dynamic-prefix renames ─────────────────────────────────
            -- Keys built at runtime via string concatenation:
            --   simpleui_hs_*        (was navbar_homescreen_*)
            --   navbar_cqa_*         →  simpleui_cqa_*
            --   navbar_action_*      →  simpleui_action_*
            --   navbar_custom_*      →  simpleui_custom_*
            --
            -- We collect all renames first, then apply — modifying a table
            -- while iterating it is undefined behaviour in Lua 5.1/5.2.
            local dynamic_prefixes = {
                { old = "navbar_homescreen_",  new = "simpleui_hs_"     },
                { old = "navbar_cqa_",         new = "simpleui_cqa_"    },
                { old = "navbar_action_",      new = "simpleui_action_" },
                { old = "navbar_custom_",      new = "simpleui_custom_" },
            }

            local pending = {}
            for k, v in SUISettings:iterateKeys() do
                for _, pfx in ipairs(dynamic_prefixes) do
                    local plen = #pfx.old
                    if k:sub(1, plen) == pfx.old then
                        local new_k = pfx.new .. k:sub(plen + 1)
                        pending[#pending + 1] = { old_k = k, new_k = new_k, val = v }
                        break
                    end
                end
            end

            for _, entry in ipairs(pending) do
                if SUISettings:get(entry.new_k) == nil then
                    SUISettings:set(entry.new_k, entry.val)
                end
                SUISettings:del(entry.old_k)
                migrated = migrated + 1
            end

            SUISettings:flush()
            logger.info("simpleui: settings migration v3 complete —", migrated, "navbar_* keys renamed to simpleui_*")
        end)
        SUISettings:set("simpleui_settings_migrated_v3", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------
    -- Settings migration v4: rename icon pack keys to integrated sui_ scheme.
    -- -------------------------------------------------------------------
    if not SUISettings:isTrue("simpleui_settings_migrated_v4") then
        pcall(function()
            local icon_renames = {
                { "simpleui_sysicon_bm_normal",     "simpleui_sysicon_sui_browse_normal" },
                { "simpleui_sysicon_bm_author",     "simpleui_sysicon_sui_browse_author" },
                { "simpleui_sysicon_bm_series",     "simpleui_sysicon_sui_browse_series" },
                { "simpleui_sysicon_bm_tags",       "simpleui_sysicon_sui_browse_tags" },
                { "simpleui_sysicon_pg_chev_left",  "simpleui_sysicon_sui_pager_prev" },
                { "simpleui_sysicon_pg_chev_right", "simpleui_sysicon_sui_pager_next" },
                { "simpleui_sysicon_pg_chev_first", "simpleui_sysicon_sui_pager_first" },
                { "simpleui_sysicon_pg_chev_last",  "simpleui_sysicon_sui_pager_last" },
                { "simpleui_sysicon_coll_back",     "simpleui_sysicon_sui_coll_back" },
            }
            local migrated = 0
            for _, pair in ipairs(icon_renames) do
                local old_k, new_k = pair[1], pair[2]
                local val = SUISettings:get(old_k)
                if val ~= nil then
                    if SUISettings:get(new_k) == nil then
                        SUISettings:set(new_k, val)
                    end
                    SUISettings:del(old_k)
                    migrated = migrated + 1
                end
            end
            local icon_presets = SUISettings:get("simpleui_icon_presets")
            if type(icon_presets) == "table" then
                local changed = false
                for _, preset in pairs(icon_presets) do
                    if type(preset._scalar) == "table" then
                        for _, pair in ipairs(icon_renames) do
                            local old_k, new_k = pair[1], pair[2]
                            if preset._scalar[old_k] ~= nil then
                                if preset._scalar[new_k] == nil then
                                    preset._scalar[new_k] = preset._scalar[old_k]
                                end
                                preset._scalar[old_k] = nil
                                changed = true
                            end
                        end
                    end
                end
                if changed then SUISettings:set("simpleui_icon_presets", icon_presets) end
            end
            SUISettings:flush()
            logger.info("simpleui: settings migration v4 complete —", migrated, "icon keys renamed")
        end)
        SUISettings:set("simpleui_settings_migrated_v4", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------
    -- Settings migration v5: standardize titlebar button nomenclature
    -- -------------------------------------------------------------------
    if not SUISettings:isTrue("simpleui_settings_migrated_v5") then
        pcall(function()
            local renames = {
                { "simpleui_tb_item_menu_button",     "simpleui_tb_item_fm_menu" },
                { "simpleui_tb_item_up_button",       "simpleui_tb_item_fm_back" },
                { "simpleui_tb_item_search_button",   "simpleui_tb_item_fm_search" },
                { "simpleui_tb_item_browse_button",   "simpleui_tb_item_fm_browse" },
                { "simpleui_tb_item_title",           "simpleui_tb_item_fm_title" },
                { "simpleui_tb_item_inj_back",        "simpleui_tb_item_sub_menu" },
                { "simpleui_tb_item_inj_right",       "simpleui_tb_item_sub_close" },
                { "simpleui_tb_item_inj_menubutton",  "simpleui_tb_item_sub_menu" },
                { "simpleui_tb_item_inj_closebutton", "simpleui_tb_item_sub_close" },
                { "simpleui_tb_inj_cfg",              "simpleui_tb_sub_cfg" },
            }
            local migrated = 0
            for _, pair in ipairs(renames) do
                local old_k, new_k = pair[1], pair[2]
                local val = SUISettings:get(old_k)
                if val ~= nil then
                    if SUISettings:get(new_k) == nil then
                        SUISettings:set(new_k, val)
                    end
                    SUISettings:del(old_k)
                    migrated = migrated + 1
                end
            end

            local function map_cfg(cfg_key, mapping)
                local cfg = SUISettings:get(cfg_key)
                if type(cfg) == "table" then
                    local changed = false
                    local function map_arr(arr)
                        for i, v in ipairs(arr) do
                            if mapping[v] then arr[i] = mapping[v]; changed = true end
                        end
                    end
                    if type(cfg.side) == "table" then
                        for old_btn, new_btn in pairs(mapping) do
                            if cfg.side[old_btn] ~= nil then
                                cfg.side[new_btn] = cfg.side[old_btn]
                                cfg.side[old_btn] = nil
                                changed = true
                            end
                        end
                    end
                    if type(cfg.order_left) == "table" then map_arr(cfg.order_left) end
                    if type(cfg.order_right) == "table" then map_arr(cfg.order_right) end
                    if changed then
                        SUISettings:set(cfg_key, cfg)
                        migrated = migrated + 1
                    end
                end
            end

            local fm_map = {
                menu_button   = "fm_menu",
                up_button     = "fm_back",
                search_button = "fm_search",
                browse_button = "fm_browse",
                title         = "fm_title"
            }
            local sub_map = {
                inj_back         = "sub_menu",
                inj_right        = "sub_close",
                inj_menubutton   = "sub_menu",
                inj_closebutton  = "sub_close"
            }
            map_cfg("simpleui_tb_fm_cfg", fm_map)
            map_cfg("simpleui_tb_sub_cfg", sub_map)

            logger.info("simpleui: settings migration v5 complete —", migrated, "titlebar keys renamed")
        end)
        SUISettings:set("simpleui_settings_migrated_v5", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------
    -- Settings migration v6: namespace clean-up and key standardisation.
    --
    -- Changes applied:
    --   1. Module enabled_key unification — bare module IDs (e.g. "currently",
    --      "recent", "coverdeck", "tbr", "new_books", "collections",
    --      "reading_goals") gain an explicit "_enabled" suffix to match the
    --      convention already used by clock, reading_stats, action_list, etc.
    --
    --   2. module_coverdeck "flow_" prefix → "coverdeck_" prefix — the old
    --      keys had no "simpleui_" namespace and risked collisions in the
    --      shared G_reader_settings / SUISettings store.
    --
    --   3. simpleui_cqa_* → simpleui_qa_* — "cqa" was undocumented jargon;
    --      "qa" matches the term used throughout the UI.  Also covers the
    --      per-slot dynamic keys simpleui_cqa_{id} → simpleui_qa_{id}.
    --
    --   4. simpleui_collections_* → simpleui_coll_* — shorter, consistent
    --      with the "fc_" brevity used by foldercovers.
    --
    --   5. simpleui_titlebar_custom → simpleui_tb_custom — aligns with the
    --      tb_ alias used by all other titlebar keys.
    --
    --   6. simpleui_tb_size → simpleui_tb_size_pct — consistent with the
    --      other size percentage keys (_bar_size_pct, _topbar_size_pct).
    --
    --   7. simpleui_bar_size (legacy enum "default"|"large") removed — this
    --      key was only written by first-run defaults v1 and was never read
    --      by any code path; the canonical value is simpleui_bar_size_pct.
    --
    -- Rules (identical to all previous migrations):
    --   • Copy only when destination key is absent (never overwrite).
    --   • Always delete the source key, even when copy is skipped.
    --   • Whole block in pcall — a crash must not prevent plugin load.
    --   • Guarded by simpleui_settings_migrated_v6.
    -- -------------------------------------------------------------------
    if not SUISettings:isTrue("simpleui_settings_migrated_v6") then
        pcall(function()
            local migrated = 0

            -- ── Helper: rename a single key ───────────────────────────
            local function _rename(old_k, new_k)
                local val = SUISettings:get(old_k)
                if val ~= nil then
                    if SUISettings:get(new_k) == nil then
                        SUISettings:set(new_k, val)
                    end
                    SUISettings:del(old_k)
                    migrated = migrated + 1
                end
            end

            -- ── 1. Module enabled_key: add _enabled suffix ────────────
            -- For each preset prefix that exists in SUISettings, rename
            -- the bare module-id keys to module-id_enabled.
            -- The only guaranteed preset prefix is "simpleui_hs_" but
            -- user presets can have arbitrary prefixes — we scan all keys.
            local bare_mods = {
                "currently", "recent", "coverdeck",
                "tbr", "new_books", "collections", "reading_goals",
            }
            -- Collect all unique prefixes that have at least one of the
            -- bare keys so we don't have to hardcode "simpleui_hs_".
            local prefixes_seen = {}
            for k, _ in SUISettings:iterateKeys() do
                if type(k) == "string" then
                    for _, mod_id in ipairs(bare_mods) do
                        -- key must end exactly with the bare mod_id
                        -- (no trailing chars) to avoid false matches
                        local sfx = mod_id
                        local klen, slen = #k, #sfx
                        if klen > slen and k:sub(klen - slen + 1) == sfx
                                and k:sub(klen - slen) == "_" then
                            local pfx = k:sub(1, klen - slen)
                            prefixes_seen[pfx] = true
                        end
                    end
                end
            end
            for pfx in pairs(prefixes_seen) do
                for _, mod_id in ipairs(bare_mods) do
                    _rename(pfx .. mod_id, pfx .. mod_id .. "_enabled")
                end
            end

            -- ── 2. module_coverdeck: flow_ → coverdeck_ ───────────────
            -- These keys are prefixed with a homescreen preset prefix
            -- (e.g. "simpleui_hs_") at runtime, so we scan all keys.
            local flow_suffixes = {
                "flow_recent_source",
                "flow_stats_order",
                -- flow_show_{elem} keys are boolean per-element toggles;
                -- we catch them with the dynamic scan below.
            }
            local flow_pending = {}
            for k, v in SUISettings:iterateKeys() do
                if type(k) == "string" then
                    -- Fixed suffixes
                    for _, sfx in ipairs(flow_suffixes) do
                        if k:sub(- #sfx) == sfx then
                            local pfx = k:sub(1, #k - #sfx)
                            local new_sfx = sfx
                                :gsub("^flow_recent_source$", "coverdeck_source")
                                :gsub("^flow_stats_order$",   "coverdeck_stats_order")
                            flow_pending[#flow_pending + 1] = {
                                old_k = k, new_k = pfx .. new_sfx, val = v
                            }
                            break
                        end
                    end
                    -- Dynamic: flow_show_{anything} → coverdeck_show_{anything}
                    local tail = k:match("_flow_show_(.+)$")
                    if tail then
                        local pfx = k:sub(1, #k - #("flow_show_" .. tail))
                        flow_pending[#flow_pending + 1] = {
                            old_k = k,
                            new_k = pfx .. "coverdeck_show_" .. tail,
                            val   = v,
                        }
                    end
                end
            end
            for _, e in ipairs(flow_pending) do
                if SUISettings:get(e.new_k) == nil then
                    SUISettings:set(e.new_k, e.val)
                end
                SUISettings:del(e.old_k)
                migrated = migrated + 1
            end

            -- ── 3. simpleui_cqa_* → simpleui_qa_* ────────────────────
            -- Covers: simpleui_cqa_list, simpleui_cqa_migrated_v1,
            --         simpleui_cqa_custom_qa_{n}, simpleui_cqa_{id}
            -- The migration-v3 target was "simpleui_cqa_*"; we now move
            -- those to "simpleui_qa_*".
            local cqa_pending = {}
            for k, v in SUISettings:iterateKeys() do
                if type(k) == "string" and k:sub(1, 13) == "simpleui_cqa_" then
                    cqa_pending[#cqa_pending + 1] = {
                        old_k = k,
                        new_k = "simpleui_qa_" .. k:sub(14),
                        val   = v,
                    }
                end
            end
            for _, e in ipairs(cqa_pending) do
                if SUISettings:get(e.new_k) == nil then
                    SUISettings:set(e.new_k, e.val)
                end
                SUISettings:del(e.old_k)
                migrated = migrated + 1
            end
            -- Also fix the migration guard written by migrateOldCustomSlots.
            _rename("simpleui_cqa_migrated_v1", "simpleui_qa_migrated_v1")

            -- ── 4. simpleui_collections_* → simpleui_coll_* ──────────
            local coll_renames = {
                { "simpleui_collections_list",           "simpleui_coll_list"           },
                { "simpleui_collections_covers",         "simpleui_coll_covers"         },
                { "simpleui_collections_badge_position", "simpleui_coll_badge_position" },
                { "simpleui_collections_badge_color",    "simpleui_coll_badge_color"    },
                { "simpleui_collections_badge_hidden",   "simpleui_coll_badge_hidden"   },
            }
            for _, pair in ipairs(coll_renames) do
                _rename(pair[1], pair[2])
            end

            -- ── 5. simpleui_titlebar_custom → simpleui_tb_custom ──────
            _rename("simpleui_titlebar_custom", "simpleui_tb_custom")

            -- ── 6. simpleui_tb_size → simpleui_tb_size_pct ───────────
            _rename("simpleui_tb_size", "simpleui_tb_size_pct")

            -- ── 7. Remove legacy simpleui_bar_size enum ───────────────
            -- Never read by any code; only written by first-run defaults v1.
            -- The canonical value is simpleui_bar_size_pct.
            SUISettings:del("simpleui_bar_size")

            SUISettings:flush()
            logger.info("simpleui: settings migration v6 complete —", migrated, "keys renamed/removed")
        end)
        SUISettings:set("simpleui_settings_migrated_v6", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v7:
    -- 1. Restore coverdeck_show_title when written as false by the
    --    "Momentum" preset but never explicitly toggled by the user.
    --    Detects the exact Momentum signature (title=false, author=false,
    --    progress=true, percent=true, book_days=true) and resets to true.
    -- 2. Enable recent_show_finished when it has never been set, so users
    --    upgrading from 1.5.x (where the filter did not exist) don't find
    --    Recent Books / Cover Deck empty because all their books are at 100%.
    -- 3. Enable the automatic update check when it has never been set,
    --    making auto-check opt-out instead of opt-in.
    if not SUISettings:isTrue("simpleui_settings_migrated_v7") then
        pcall(function()
            local PFX       = "simpleui_hs_"
            -- 1. coverdeck_show_title
            local title     = SUISettings:get(PFX .. "coverdeck_show_title")
            local author    = SUISettings:get(PFX .. "coverdeck_show_author")
            local progress  = SUISettings:get(PFX .. "coverdeck_show_progress")
            local percent   = SUISettings:get(PFX .. "coverdeck_show_percent")
            local book_days = SUISettings:get(PFX .. "coverdeck_show_book_days")
            if title == false and author == false
                    and progress == true and percent == true
                    and book_days == true then
                SUISettings:set(PFX .. "coverdeck_show_title", true)
                logger.info("simpleui: migration v7 — restored coverdeck_show_title to true")
            end
            -- 2. recent_show_finished
            if SUISettings:get(PFX .. "recent_show_finished") == nil then
                SUISettings:set(PFX .. "recent_show_finished", true)
                logger.info("simpleui: migration v7 — enabled recent_show_finished")
            end
            -- 3. auto update check
            if SUISettings:get("simpleui_updater_auto_check") == nil then
                SUISettings:set("simpleui_updater_auto_check", true)
                logger.info("simpleui: migration v7 — enabled simpleui_updater_auto_check")
            end
        end)
        SUISettings:set("simpleui_settings_migrated_v7", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v8:
    -- Introduces the unified Cover Deck arrange list (coverdeck_main_order),
    -- replacing the old coverdeck_title_pos above/below/hidden radio and
    -- the separate "Show status bar" toggle for the progress bar.
    --   1. Legacy title_pos == "hidden" had no dedicated key of its own;
    --      fold it into coverdeck_show_title so upgrading users keep the
    --      title hidden instead of it reappearing under the new model.
    --   2. coverdeck_main_order is seeded from title_pos ("above"/"below")
    --      so existing layouts render identically the first time they're
    --      opened under the new arrange list, instead of silently
    --      reverting to the "below" default.
    if not SUISettings:isTrue("simpleui_settings_migrated_v8") then
        pcall(function()
            local PFX       = "simpleui_hs_"
            local title_pos = SUISettings:get(PFX .. "coverdeck_title_pos")
            if title_pos == "hidden" and SUISettings:get(PFX .. "coverdeck_show_title") == nil then
                SUISettings:set(PFX .. "coverdeck_show_title", false)
                logger.info("simpleui: migration v8 — folded coverdeck_title_pos=hidden into coverdeck_show_title=false")
            end
            if SUISettings:get(PFX .. "coverdeck_main_order") == nil then
                local order = (title_pos == "above")
                    and { "title", "author", "covers", "progress", "stats" }
                    or  { "covers", "title", "author", "progress", "stats" }
                SUISettings:set(PFX .. "coverdeck_main_order", order)
                logger.info("simpleui: migration v8 — seeded coverdeck_main_order from legacy title_pos")
            end
        end)
        SUISettings:set("simpleui_settings_migrated_v8", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v9:
    -- Selects the tabs title bar style when no style was ever chosen.
    -- An explicit choice, including classic, is kept.
    if not SUISettings:isTrue("simpleui_settings_migrated_v9") then
        pcall(function()
            if SUISettings:get("simpleui_tb_style") == nil then
                SUISettings:set("simpleui_tb_style", "tabs")
                logger.info("simpleui: migration v9 — title bar style set to tabs")
            end
        end)
        SUISettings:set("simpleui_settings_migrated_v9", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v10:
    -- Folds the finished-books fade toggle into the three-state mode
    -- (show / fade / hide). An explicit "off" becomes "show"; any other
    -- stored value keeps the previous behaviour, "fade".
    if not SUISettings:isTrue("simpleui_settings_migrated_v10") then
        pcall(function()
            local legacy = SUISettings:get("simpleui_fc_fade_finished")
            if legacy == nil then return end
            if SUISettings:get("simpleui_fc_finished_mode") == nil then
                SUISettings:set("simpleui_fc_finished_mode", legacy == false and "show" or "fade")
            end
            SUISettings:del("simpleui_fc_fade_finished")
            logger.info("simpleui: migration v10 — folded finished-books fade toggle into the mode")
        end)
        SUISettings:set("simpleui_settings_migrated_v10", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v11:
    -- Series grouping becomes a per-view setting. An enabled global flag
    -- enables it in every view that supported it, keeping the previous
    -- behaviour; the global flag is then dropped.
    if not SUISettings:isTrue("simpleui_settings_migrated_v11") then
        pcall(function()
            local legacy_key = "simpleui_fc_series_grouping"
            local legacy = SUISettings:get(legacy_key)
            if legacy == nil then return end
            for _, mode in ipairs({ "normal", "author", "tags" }) do
                local key = legacy_key .. "_" .. mode
                if SUISettings:get(key) == nil then SUISettings:set(key, legacy == true) end
            end
            SUISettings:del(legacy_key)
            logger.info("simpleui: migration v11 — series grouping split per view")
        end)
        SUISettings:set("simpleui_settings_migrated_v11", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v12:
    -- Library badge settings move to the cover elements registry: the
    -- combined visibility/variant enums split into `show` + variant and
    -- the keys gain the "simpleui_style_badge_" prefix.
    if not SUISettings:isTrue("simpleui_settings_migrated_v12") then
        pcall(function()
            require("features/sui_cover_elements").migrateLegacyBadges()
        end)
        SUISettings:set("simpleui_settings_migrated_v12", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v13:
    -- Folder cover settings move to the cover elements registry (the name
    -- visibility enums merge into `show`, the stack's `hide` becomes
    -- `show`) and the library caption flags to the captions keys.
    if not SUISettings:isTrue("simpleui_settings_migrated_v13") then
        pcall(function()
            require("features/sui_cover_elements").migrateLegacyFolder()
        end)
        pcall(function()
            require("features/library/sui_foldercovers").migrateLegacyCaptions()
        end)
        SUISettings:set("simpleui_settings_migrated_v13", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------

    -- Settings migration v14:
    -- The critter, its bubble style, phrase source, topics and reactions
    -- become global settings, taken from the default screen's.
    if not SUISettings:isTrue("simpleui_settings_migrated_v14") then
        pcall(function()
            require("modules/critter/settings").migrateLegacy()
        end)
        SUISettings:set("simpleui_settings_migrated_v14", true)
        SUISettings:flush()
    end
    -- -------------------------------------------------------------------
end

return M
