describe("reader footer patches", function()
    local saved_modules

    local function apply_patch(name)
        ZenSpec.unload(name)
        require(name)()
    end

    before_each(function()
        saved_modules = nil
        _G.__ZEN_UI_PLUGIN = nil
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/util", {
            template = function(text, ...)
                local values = { ... }
                return (text:gsub("%%(%d+)", function(index)
                    return tostring(values[tonumber(index)])
                end))
            end,
        })
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        if saved_modules then
            ZenSpec.unload("modules/reader/patches/reader_footer")
            for name, module in pairs(saved_modules) do
                package.loaded[name] = module or nil
            end
        end
    end)

    it("formats chapter time for sub-minute, singular, and plural durations", function()
        local ReaderFooter = {
            textGeneratorMap = {
                chapter_time_to_read = function() return "stock" end,
                dynamic_filler = function() return "          ", true end,
            },
            genAllFooterText = function() return "all" end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { chapter_time_format = "full" } },
        }
        apply_patch("modules/reader/patches/reader_footer_time_format")

        local footer = {
            pageno = 10,
            ui = {
                statistics = { settings = { is_enabled = true }, avg_time = 30 },
                toc = { getChapterPagesLeft = function() return 1 end },
                document = { getTotalPagesLeft = function() return 99 end },
            },
        }
        local nbsp = "\u{00A0}"
        local hair = "\u{200A}"
        assert.are.equal(hair .. "<" .. nbsp .. "1" .. nbsp .. "min" .. nbsp
            .. "left" .. nbsp .. "in" .. nbsp .. "chapter",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        footer.ui.statistics.avg_time = 60
        assert.are.equal(hair .. "1" .. nbsp .. "min" .. nbsp .. "left" .. nbsp
            .. "in" .. nbsp .. "chapter",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        footer.ui.toc.getChapterPagesLeft = function() return 4 end
        assert.are.equal(hair .. "4" .. nbsp .. "min" .. nbsp .. "left" .. nbsp
            .. "in" .. nbsp .. "chapter",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        footer.ui.statistics._zenPagesInStatisticsUnits = function(_stats, pages)
            return pages / 2
        end
        assert.are.equal(hair .. "2" .. nbsp .. "min" .. nbsp .. "left" .. nbsp
            .. "in" .. nbsp .. "chapter",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))
    end)

    it("formats compact and abbreviated chapter times", function()
        local ReaderFooter = {
            textGeneratorMap = {
                chapter_time_to_read = function() return "stock" end,
                dynamic_filler = function() return "          ", false end,
            },
            genAllFooterText = function() return "all" end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { chapter_time_format = "compact" } },
        }
        apply_patch("modules/reader/patches/reader_footer_time_format")

        local footer = {
            pageno = 10,
            ui = {
                statistics = { settings = { is_enabled = true }, avg_time = 60 },
                toc = { getChapterPagesLeft = function() return 4 end },
                document = { getTotalPagesLeft = function() return 99 end },
            },
        }
        local nbsp = "\u{00A0}"
        local hair = "\u{200A}"
        assert.are.equal(hair .. "4" .. nbsp .. "min" .. nbsp .. "left",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        _G.__ZEN_UI_PLUGIN.config.reader_footer.chapter_time_format = "number"
        assert.are.equal(hair .. "4m", ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))
        local text, merge = ReaderFooter.textGeneratorMap.dynamic_filler(footer)
        assert.are.equal("          ", text)
        assert.is_false(merge)

        footer.ui.statistics.avg_time = 30
        footer.ui.toc.getChapterPagesLeft = function() return 1 end
        assert.are.equal(hair .. "< 1m", ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        footer.ui.statistics.avg_time = 60
        footer.ui.toc.getChapterPagesLeft = function() return 60 end
        assert.are.equal(hair .. "1h", ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        footer.ui.toc.getChapterPagesLeft = function() return 65 end
        assert.are.equal(hair .. "1h 5m", ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))
    end)

    it("uses KOReader's chapter-time formatter for the default format", function()
        local original_filler = function() return "          ", false end
        local ReaderFooter = {
            textGeneratorMap = {
                chapter_time_to_read = function() return "01:05" end,
                dynamic_filler = original_filler,
            },
            genAllFooterText = function() return "all" end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { chapter_time_format = "koreader" } },
        }
        apply_patch("modules/reader/patches/reader_footer_time_format")

        assert.are.equal("01:05", ReaderFooter.textGeneratorMap.chapter_time_to_read({}))
        local text, merge = ReaderFooter.textGeneratorMap.dynamic_filler({})
        assert.are.equal("          ", text)
        assert.is_false(merge)
    end)

    it("preserves native dynamic filler spacing for full and compact chapter time", function()
        local original_filler = function() return "          ", true end
        local footer = {
            pageno = 1,
            footerTextGenerators = { original_filler },
            ui = {
                statistics = { settings = { is_enabled = true }, avg_time = 60 },
                toc = { getChapterPagesLeft = function() return 1 end },
                document = { getTotalPagesLeft = function() return 1 end },
            },
        }
        for _i, format in ipairs({ "full", "compact" }) do
            local ReaderFooter = {
                textGeneratorMap = {
                    chapter_time_to_read = function() return "stock" end,
                    dynamic_filler = original_filler,
                },
            }
            ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
            _G.__ZEN_UI_PLUGIN = {
                config = { reader_footer = { chapter_time_format = format } },
            }
            apply_patch("modules/reader/patches/reader_footer_time_format")

            local text, merge = ReaderFooter.textGeneratorMap.dynamic_filler(footer)
            assert.are.equal("          ", text)
            assert.is_true(merge)
            assert.are.equal(original_filler, ReaderFooter.textGeneratorMap.dynamic_filler)
        end
    end)

    it("preserves KOReader's dynamic filler marker in verbose mode", function()
        local ReaderFooter = {
            textGeneratorMap = {
                chapter_time_to_read = function() return "chapter" end,
                dynamic_filler = function() return nil, true, true end,
            },
            genAllFooterText = function() return "all" end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { chapter_time_format = "full" } },
        }
        apply_patch("modules/reader/patches/reader_footer_time_format")

        local text, merge, is_filler = ReaderFooter.textGeneratorMap.dynamic_filler({})
        assert.is_nil(text)
        assert.is_true(merge)
        assert.is_true(is_filler)
    end)

    it("keeps configured image documents hidden after load and footer toggles", function()
        local ready_calls, mode
        local ReaderFooter = {
            onReaderReady = function() ready_calls = (ready_calls or 0) + 1 end,
            applyFooterMode = function(_, value) mode = value end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = { config = { reader_footer = { hide_in_cbz = true } } }
        apply_patch("modules/reader/patches/reader_footer_cbz_hide")

        local refresh_args
        local footer = {
            ui = { document = { file = "/books/Comic.CBZ" } },
            view = { footer_visible = true },
            refreshFooter = function(_, first, second) refresh_args = { first, second } end,
        }
        ReaderFooter.onReaderReady(footer)
        assert.are.equal(1, ready_calls)
        assert.is_false(footer.view.footer_visible)
        assert.same({ true, true }, refresh_args)

        footer.view.footer_visible = true
        ReaderFooter.applyFooterMode(footer, 3)
        assert.are.equal(3, mode)
        assert.is_false(footer.view.footer_visible)
    end)

    it("keeps a disabled bottom status bar hidden after reopening a book", function()
        local ready_calls, applied_mode
        local ReaderFooter = {
            onReaderReady = function() ready_calls = (ready_calls or 0) + 1 end,
            applyFooterMode = function(self, mode)
                applied_mode = mode
                self.view.footer_visible = mode ~= self.mode_list.off
            end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { status_bar_enabled = false } },
        }
        apply_patch("modules/reader/patches/reader_footer_cbz_hide")

        local refresh_args
        local footer = {
            mode_list = { off = 0 },
            ui = { document = { file = "/books/Novel.epub" } },
            view = { footer_visible = true },
            applyFooterMode = ReaderFooter.applyFooterMode,
            refreshFooter = function(_, first, second) refresh_args = { first, second } end,
        }
        ReaderFooter.onReaderReady(footer)

        assert.are.equal(1, ready_calls)
        assert.are.equal(0, applied_mode)
        assert.is_false(footer.view.footer_visible)
        assert.same({ true, true }, refresh_args)
    end)

    it("persists customized bottom status bar items before closing an EPUB", function()
        local save_calls = 0
        local ReaderFooter = {
            onReaderReady = function() end,
            applyFooterMode = function() end,
            onSaveSettings = function() save_calls = save_calls + 1 end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = { config = { reader_footer = {} } }
        G_reader_settings:saveSetting("footer", { time = false, battery = true })
        apply_patch("modules/reader/patches/reader_footer_cbz_hide")

        local customized = {
            time = true,
            battery = false,
            book_title = true,
            order = { [0] = "off", "book_title", "time", "battery" },
        }
        ReaderFooter.onSaveSettings({
            settings = customized,
            ui = { document = { file = "/books/Novel.epub" } },
        })

        assert.are.equal(1, save_calls)
        assert.are.equal(customized, G_reader_settings:readSetting("footer"))
        assert.is_true(G_reader_settings:readSetting("footer").book_title)
        assert.same(customized.order, G_reader_settings:readSetting("footer").order)
    end)

    it("leaves ordinary documents and disabled image hiding unchanged", function()
        local refreshes = 0
        local ReaderFooter = {
            onReaderReady = function() end,
            applyFooterMode = function(self) self.view.footer_visible = true end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = { config = { reader_footer = { hide_in_cbz = false } } }
        apply_patch("modules/reader/patches/reader_footer_cbz_hide")

        local footer = {
            ui = { document = { file = "/books/Novel.epub" } },
            view = { footer_visible = true },
            refreshFooter = function() refreshes = refreshes + 1 end,
        }
        ReaderFooter.onReaderReady(footer)
        ReaderFooter.applyFooterMode(footer, 1)
        assert.is_true(footer.view.footer_visible)
        assert.are.equal(0, refreshes)
    end)

    it("keeps forced footer refreshes behind overlays and clears a hidden footer", function()
        saved_modules = {}
        for _i, name in ipairs({
            "apps/reader/modules/readerfooter", "apps/reader/readerui", "device", "ffi/blitbuffer",
            "ui/bidi", "ui/geometry", "ui/uimanager", "ui/widget/container/leftcontainer", "ui/widget/textwidget",
        }) do
            saved_modules[name] = package.loaded[name] or false
        end
        local repaint, repaint_full, received
        local ReaderFooter = {
            textGeneratorMap = {
                battery = function() return "" end,
                page_progress = function() return "" end,
                dynamic_filler = function() return "" end,
            },
            shouldBeRepainted = function() return repaint, repaint_full end,
            _updateFooterText = function(_, force_repaint, full_repaint)
                received = { force_repaint, full_repaint }
            end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        ZenSpec.replace("apps/reader/readerui", {})
        ZenSpec.replace("device", { screen = {} })
        for _i, name in ipairs({
            "ffi/blitbuffer", "ui/bidi", "ui/geometry", "ui/uimanager",
            "ui/widget/container/leftcontainer", "ui/widget/textwidget",
        }) do
            ZenSpec.replace(name, {})
        end
        ZenSpec.replace("ui/uimanager", { scheduleIn = function() end })
        _G.__ZEN_UI_PLUGIN = { config = { features = {} } }
        apply_patch("modules/reader/patches/reader_footer")
        local footer = setmetatable({
            settings = { progress_margin_width = 10 },
            view = { footer_visible = true },
        }, { __index = ReaderFooter })

        repaint = false -- PageBrowser covers the footer.
        footer:_updateFooterText(true)
        assert.is_false(received[1])
        repaint, repaint_full = true, true -- A smaller overlay needs the full stack repainted.
        footer:_updateFooterText(true)
        assert.is_true(received[1])
        assert.is_true(received[2])
        repaint_full = nil -- Reader is visible again.
        footer:_updateFooterText(true)
        assert.is_true(received[1])
        assert.is_nil(received[2])
        repaint = false
        footer.view.footer_visible = false
        footer:_updateFooterText(true, true)
        assert.is_true(received[1])
        assert.is_true(received[2])
    end)

    it("opts into book margins without changing saved footer spacing and restores it when disabled", function()
        saved_modules = {}
        for _i, name in ipairs({
            "apps/reader/modules/readerfooter", "apps/reader/readerui",
            "common/reader_status_bar", "device", "ffi/blitbuffer", "ui/bidi",
            "ui/geometry", "ui/uimanager", "ui/widget/container/leftcontainer", "ui/widget/textwidget",
        }) do
            saved_modules[name] = package.loaded[name] or false
        end
        local painted_x, text_margin, layout_margin, builds, resets = nil, nil, nil, 0, 0
        local ReaderFooter = {
            textGeneratorMap = {
                battery = function() return "" end,
                page_progress = function() return "" end,
                dynamic_filler = function() return "" end,
            },
            textOptionTitles = function() end,
            set_mode_index = function() end,
            addToMainMenu = function() end,
            updateFooterContainer = function(self)
                builds = builds + 1
                self.vertical_frame = { paintTo = function(_frame, _bb, x) painted_x = x end }
            end,
            resetLayout = function(self, force)
                assert.is_true(force)
                layout_margin = self.settings.progress_margin_width
                resets = resets + 1
            end,
            _updateFooterText = function(self)
                text_margin = self.settings.progress_margin_width
                return "updated"
            end,
            genAllFooterText = function() return "" end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        ZenSpec.replace("apps/reader/readerui", {})
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_self, value) return value * 2 end },
        })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_GRAY_5 = 5 })
        ZenSpec.replace("ui/bidi", {})
        ZenSpec.replace("ui/geometry", {})
        ZenSpec.replace("ui/uimanager", { scheduleIn = function() end })
        ZenSpec.replace("ui/widget/container/leftcontainer", {})
        ZenSpec.replace("ui/widget/textwidget", {})
        ZenSpec.unload("common/reader_status_bar")
        _G.__ZEN_UI_PLUGIN = { config = { features = {} } }
        apply_patch("modules/reader/patches/reader_footer")

        local document = { configurable = { h_page_margins = { 30, 50 } } }
        local footer = setmetatable({
            ui = { document = document },
            settings = { disable_progress_bar = true, progress_margin = false, progress_margin_width = 10 },
            horizontal_margin = 3,
        }, { __index = ReaderFooter })
        footer:updateFooterContainer()
        footer.vertical_frame:paintTo({}, 100, 0)
        assert.are.equal(100, painted_x)
        assert.are.equal("updated", footer:_updateFooterText())
        assert.are.equal(10, text_margin)
        assert.are.equal(3, footer.horizontal_margin)
        assert.are.equal(1, builds)
        assert.are.equal(0, resets)

        _G.__ZEN_UI_PLUGIN.config.features.reader_status_bar_margins = true
        footer:updateFooterContainer()
        assert.are.equal(80, footer.horizontal_margin)
        assert.are.equal(10, footer.settings.progress_margin_width)
        assert.is_false(footer.settings.progress_margin)
        footer.vertical_frame:paintTo({}, 100, 0)
        assert.are.equal(80, painted_x)

        assert.are.equal("updated", footer:_updateFooterText())
        assert.are.equal(40, text_margin)
        assert.are.equal(10, footer.settings.progress_margin_width)
        assert.are.equal(2, builds)
        document.configurable.h_page_margins = { 40, 40 }
        footer.vertical_frame:paintTo({}, 100, 0)
        assert.are.equal(100, painted_x)
        document.configurable.h_page_margins = { 50, 70 }
        footer:_updateFooterText()
        assert.are.equal(120, footer.horizontal_margin)
        assert.are.equal(60, text_margin)
        assert.are.equal(60, layout_margin)
        assert.are.equal(10, footer.settings.progress_margin_width)
        assert.are.equal(3, builds)
        assert.are.equal(1, resets)

        _G.__ZEN_UI_PLUGIN.config.features.reader_status_bar_margins = false
        footer:_updateFooterText()
        assert.are.equal(3, footer.horizontal_margin)
        assert.are.equal(10, text_margin)
        assert.are.equal(10, layout_margin)
        assert.is_false(footer.settings.progress_margin)
        assert.are.equal(4, builds)
        assert.are.equal(2, resets)
        footer.vertical_frame:paintTo({}, 100, 0)
        assert.are.equal(100, painted_x)

        _G.__ZEN_UI_PLUGIN.config.features.reader_status_bar_margins = true
        local fixed_footer = setmetatable({
            ui = { document = {} },
            settings = { disable_progress_bar = true, progress_margin_width = 10 },
            horizontal_margin = 3,
        }, { __index = ReaderFooter })
        fixed_footer:updateFooterContainer()
        assert.are.equal(3, fixed_footer.horizontal_margin)
        assert.are.equal(10, fixed_footer.settings.progress_margin_width)
        fixed_footer.vertical_frame:paintTo({}, 100, 0)
        assert.are.equal(100, painted_x)

        document.getPageMargins = function() return { left = 30, right = 50 } end
        footer:updateFooterContainer()
        assert.are.equal(40, footer.horizontal_margin)
        footer.vertical_frame:paintTo({}, 100, 0)
        assert.are.equal(90, painted_x)
        footer:_updateFooterText()
        assert.are.equal(20, text_margin)
        assert.are.equal(10, footer.settings.progress_margin_width)

        local screen = package.loaded["device"].screen
        screen.scaleBySize = function(_self, value) return math.ceil(value * 1264 / 600) end
        document.getPageMargins = function() return { left = 64, right = 64 } end
        footer:updateFooterContainer()
        assert.are.equal(64, footer.horizontal_margin)
        footer:_updateFooterText()
        assert.are.equal(64, screen:scaleBySize(text_margin))
        assert.are.equal(10, footer.settings.progress_margin_width)
    end)

    local function load_native_footer()
        local modules = {
            ["device"] = {
                screen = {
                    getWidth = function() return 1264 end,
                    scaleBySize = function(_self, value) return value end,
                },
                hasBattery = function() return false end,
                hasAuxBattery = function() return false end,
                hasColorScreen = function() return false end,
                isAndroid = function() return false end,
                isTouchDevice = function() return false end,
            },
            ["ui/bidi"] = {
                wrap = function(text) return text end,
                mirroredUILayout = function() return false end,
            },
            ["ui/size"] = { span = { horizontal_default = 0 }, padding = { tiny = 0 } },
            ["ui/widget/container/widgetcontainer"] = {
                extend = function(_self, values) return values end,
            },
            ["ui/uimanager"] = { scheduleIn = function() end },
            ["gettext"] = setmetatable({ pgettext = function(_context, text) return text end }, {
                __call = function(_self, text) return "native:" .. text end,
            }),
            ["ui/widget/textwidget"] = {
                new = function(_self, values)
                    return {
                        getSize = function()
                            return { w = #values.text:gsub("\u{200A}", " ") * 8 }
                        end,
                        free = function() end,
                    }
                end,
            },
            ["apps/reader/readerui"] = {},
            ["ffi/util"] = package.loaded["ffi/util"],
            ["ffi/blitbuffer"] = {},
            ["ui/geometry"] = {},
            ["ui/widget/container/leftcontainer"] = {},
        }
        -- Exercise KOReader's actual mode ordering and generator selection without a display.
        local native = assert(loadfile("frontend/apps/reader/modules/readerfooter.lua"))
        setfenv(native, setmetatable({
            require = function(name) return modules[name] or {} end,
            G_defaults = { readSetting = function(_self, key)
                if key == "DTAP_ZONE_MINIBAR" then return { w = 1, h = 1 } end
                return 14
            end },
        }, { __index = _G }))
        local ReaderFooter = native()
        modules["apps/reader/modules/readerfooter"] = ReaderFooter
        saved_modules = {}
        for name, module in pairs(modules) do
            saved_modules[name] = package.loaded[name] or false
            ZenSpec.replace(name, module)
        end
        local preset_module = "modules/reader/patches/reader_footer_presets"
        saved_modules[preset_module] = package.loaded[preset_module] or false
        ZenSpec.unload(preset_module)
        ZenSpec.replace("gettext", function(text) return text end)
        apply_patch("modules/reader/patches/reader_footer")
        return ReaderFooter
    end

    it("centers the LCR preset and joins pages with percentage when the second filler is disabled", function()
        local ReaderFooter = load_native_footer()
        local chapter_text = "19 min left in chapter"
        ReaderFooter.textGeneratorMap.chapter_time_to_read = function() return chapter_text end
        ReaderFooter.textGeneratorMap.page_progress = function() return "461/608" end
        ReaderFooter.textGeneratorMap.percentage = function() return "76%" end
        local footer = setmetatable({
            settings = require("modules/reader/patches/reader_footer_presets")[5].footer,
            horizontal_margin = 0,
            _saved_screen_width = 1264,
        }, { __index = ReaderFooter })
        footer:set_mode_index()

        for _i, left_text in ipairs({ chapter_text, "" }) do
            chapter_text = left_text
            footer:updateFooterTextGenerator()
            assert.are.equal(5, #footer.footerTextGenerators)
            local text = footer:genFooterText():gsub("\u{200A}", " ")
            local page_start = assert(text:find("461/608", 1, true))
            local page_center = (page_start - 1 + #"461/608" / 2) * 8
            assert.is_true(math.abs(page_center - 632) <= 8)
            assert.are.equal("76%", text:sub(-3))
            assert.is_nil(text:find("•", 1, true))
        end

        chapter_text = "19 min left in chapter"
        footer.settings.dynamic_filler2 = false
        footer:updateFooterTextGenerator()
        local text = footer:genFooterText():gsub("\u{200A}", " ")
        assert.are.equal(4, #footer.footerTextGenerators)
        assert.matches("461/608 • 76%%$", text)
        assert.is_true((assert(text:find("461/608", 1, true)) - 1) * 8 > 1264 * 0.75)
    end)

    it("shows one working second filler across gettext catalogs and migrates its saved order", function()
        local ReaderFooter = load_native_footer()
        local footer = setmetatable({
            settings = require("modules/reader/patches/reader_footer_presets")[5].footer,
            ui = {},
            view = { footer_visible = true },
            custom_text = "ZenOS",
            custom_text_repetitions = 1,
            refreshFooter = function(self) self.refreshed = true end,
            rescheduleFooterAutoRefreshIfNeeded = function() end,
        }, { __index = ReaderFooter })
        footer.settings.dynamic_filler_2 = true
        footer.settings.dynamic_filler2 = false
        footer.settings.order = {
            [0] = "off", "chapter_time_to_read", "dynamic_filler", "page_progress",
            "dynamic_filler_2", "percentage", "dynamic_filler2",
        }
        footer:set_mode_index()
        assert.is_true(footer.settings.dynamic_filler2)
        assert.is_nil(footer.settings.dynamic_filler_2)
        assert.are.equal("dynamic_filler2", footer.mode_index[4])
        local filler_count = 0
        footer.mode_list = {}
        for i = 0, footer.mode_nb - 1 do
            local name = footer.mode_index[i]
            footer.mode_list[name] = i
            assert.are_not.equal("dynamic_filler_2", name)
            if name == "dynamic_filler2" then filler_count = filler_count + 1 end
        end
        assert.are.equal(1, filler_count)
        footer:set_has_no_mode()
        footer.reclaim_height = footer.settings.reclaim_height
        footer:updateFooterTextGenerator()

        local menu_items = {}
        footer:addToMainMenu(menu_items)
        local filler_item, arrange_item
        filler_count = 0
        for _i, item in ipairs(menu_items.status_bar.sub_item_table) do
            if item.text == "native:Status bar items" then
                for _j, child in ipairs(item.sub_item_table) do
                    if child.text_func and child.text_func():match("Dynamic filler 2$") then
                        filler_item = child
                        filler_count = filler_count + 1
                    end
                end
            elseif item.text == "native:Configure items" then
                arrange_item = item.sub_item_table[1]
            end
        end
        assert.are.equal(1, filler_count)
        assert.is_true(filler_item.checked_func())
        filler_item.callback()
        assert.is_false(footer.settings.dynamic_filler2)
        assert.is_true(footer.refreshed)
        assert.are.equal(4, #footer.footerTextGenerators)
        filler_item.callback()
        assert.is_true(footer.settings.dynamic_filler2)
        assert.are.equal(5, #footer.footerTextGenerators)

        local arrange_name = "common/ui/zen_arrange_list"
        saved_modules[arrange_name] = package.loaded[arrange_name] or false
        local arranged
        ZenSpec.replace(arrange_name, { show = function(options) arranged = options.item_table end })
        arrange_item.callback()
        assert.are.equal("dynamic_filler2", arranged[4].label)
        assert.is_false(arranged[4].dim)

        footer.settings.dynamic_filler_2 = false
        footer:set_mode_index()
        assert.is_true(footer.settings.dynamic_filler2)
        assert.is_nil(footer.settings.dynamic_filler_2)

        footer.settings.dynamic_filler_2 = false
        footer.settings.dynamic_filler2 = false
        footer:set_mode_index()
        assert.is_false(footer.settings.dynamic_filler2)
        assert.is_nil(footer.settings.dynamic_filler_2)
    end)

    it("keeps the progress anchor out of cycling and uses the Zen arrange list", function()
        local dependency_names = {
            "apps/reader/modules/readerfooter",
            "apps/reader/readerui",
            "common/ui/zen_arrange_list",
            "device",
            "ffi/blitbuffer",
            "ui/bidi",
            "ui/geometry",
            "ui/uimanager",
            "ui/widget/container/leftcontainer",
            "ui/widget/textwidget",
        }
        saved_modules = {}
        for _i, name in ipairs(dependency_names) do
            saved_modules[name] = package.loaded[name] or false
        end

        local stock_arrange_called = false
        local ReaderFooter = {
            textGeneratorMap = {
                battery = function() return "battery" end,
                page_progress = function() return "page" end,
                dynamic_filler = function() return "" end,
            },
            textOptionTitles = function(_self, option) return option end,
            set_mode_index = function(self)
                self.mode_index = {
                    [0] = "off",
                    "page_progress",
                    "progress_bar",
                    "dynamic_filler2",
                }
                self.mode_nb = 4
            end,
            addToMainMenu = function(self, menu_items)
                menu_items.status_bar = {
                    sub_item_table = {
                        {
                            text = "Status bar items",
                            sub_item_table = {
                                { text_func = function() return self:textOptionTitles("page_progress") end },
                                { text = "External content" },
                            },
                        },
                        {
                            text = "Configure items",
                            sub_item_table = {
                                {
                                    text = "Arrange items in status bar",
                                    callback = function() stock_arrange_called = true end,
                                },
                                { text_func = function() return self:textOptionTitles("all_at_once") end },
                            },
                        },
                    },
                }
            end,
            updateFooterContainer = function() end,
            _updateFooterText = function() end,
            genAllFooterText = function() return "" end,
            updateFooterTextGenerator = function(self) self.updated = true end,
            onUpdateFooter = function(self) self.repainted = true end,
        }
        local footer = setmetatable({
            settings = {
                disable_progress_bar = true,
                dynamic_filler2 = false,
                page_progress = true,
                progress_bar = true,
            },
            mode_index = {
                [0] = "off",
                "page_progress",
                "progress_bar",
                "dynamic_filler2",
            },
            mode_nb = 4,
            mode_list = {
                off = 0,
                page_progress = 1,
                progress_bar = 2,
                dynamic_filler2 = 3,
            },
        }, { __index = ReaderFooter })
        local arrange_options
        local dirty = false
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        ZenSpec.replace("apps/reader/readerui", {
            instance = { view = { footer = footer } },
        })
        ZenSpec.replace("common/ui/zen_arrange_list", {
            show = function(options) arrange_options = options end,
        })
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_self, value) return value end },
        })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_GRAY_5 = 5 })
        ZenSpec.replace("ui/bidi", { wrap = function(text) return text end })
        ZenSpec.replace("ui/geometry", {})
        ZenSpec.replace("ui/widget/container/leftcontainer", {})
        ZenSpec.replace("ui/widget/textwidget", {})
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function() end,
            setDirty = function() dirty = true end,
        })

        apply_patch("modules/reader/patches/reader_footer")
        assert.is_nil(footer.settings.progress_bar)
        footer.settings.progress_bar = true
        footer:set_mode_index()
        assert.is_nil(footer.settings.progress_bar)

        local menu_items = {}
        footer:addToMainMenu(menu_items)
        local arrange_item = menu_items.status_bar.sub_item_table[2].sub_item_table[1]
        assert.is_false(arrange_item.enabled_func())
        arrange_item.callback()

        assert.is_false(stock_arrange_called)
        assert.are.equal("Arrange items", arrange_options.title)
        assert.is_true(arrange_options.item_table[2].dim)

        footer.settings.disable_progress_bar = false
        assert.is_true(arrange_item.enabled_func())
        arrange_item.callback()
        assert.is_false(arrange_options.item_table[2].dim)
        arrange_options.callback()
        assert.is_true(footer.updated)
        assert.is_true(footer.repainted)
        assert.is_true(dirty)
    end)
end)
