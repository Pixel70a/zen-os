require("ffi/loadlib")

describe("interface accent", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local originals, plugin, screen, Accent
    local modules = {
        "device", "ui/uimanager", "config/manager", "common/utils", "common/ui/accent",
        "common/ui/zen_slider", "common/ui/zen_toggle",
    }

    before_each(function()
        originals = {}
        for _i, name in ipairs(modules) do originals[name] = package.loaded[name] or false end
        plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        _G.__ZEN_UI_PLUGIN = { config = { accent_color = "#204080" } }
        screen = {
            isColorScreen = function() return true end,
            scaleBySize = function(_self, size) return size end,
        }
        ZenSpec.replace("device", { screen = screen })
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.replace("config/manager", { get = function() return nil end })
        ZenSpec.unload("common/ui/accent")
        ZenSpec.unload("common/utils")
        ZenSpec.unload("common/ui/zen_slider")
        ZenSpec.unload("common/ui/zen_toggle")
        Accent = require("common/ui/accent")
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = plugin
        for _i, name in ipairs(modules) do package.loaded[name] = originals[name] or nil end
    end)

    it("validates saved colors and always uses black on monochrome screens", function()
        assert.are.equal("#204080", Accent.hex())
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(32, 64, 128, 255)), tostring(Accent.color()))
        assert.is_true(Accent.isEnabled())
        for _i, value in ipairs({ false, {}, "#123", "204080", "#GG0000" }) do
            _G.__ZEN_UI_PLUGIN.config.accent_color = value
            assert.are.equal("#000000", Accent.hex())
            assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.color())
            assert.is_false(Accent.isEnabled())
        end
        _G.__ZEN_UI_PLUGIN.config.accent_color = "#abcdef"
        assert.are.equal("#ABCDEF", Accent.hex())
        screen.isColorScreen = function() return false end
        assert.is_false(Accent.isSupported())
        assert.is_false(Accent.isEnabled())
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.color())
        assert.are.equal("#ABCDEF", Accent.hex())
    end)

    it("reads the live config after the temporary patch-application global is cleared", function()
        local config = _G.__ZEN_UI_PLUGIN.config
        ZenSpec.replace("config/manager", { get = function() return config end })
        _G.__ZEN_UI_PLUGIN = nil
        assert.are.equal("#204080", Accent.hex())
        assert.is_true(Accent.isEnabled())
        config.accent_color = "#336699"
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(51, 102, 153, 255)), tostring(Accent.color()))
    end)

    it("disables the accent without losing the saved color or opacity", function()
        local config = _G.__ZEN_UI_PLUGIN.config
        config.accent_opacity = 50
        local color = tostring(Accent.color())
        config.accent_enabled = false
        assert.is_false(Accent.isEnabled())
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.color())
        assert.are.equal(Blitbuffer.COLOR_WHITE, Accent.foreground())
        assert.are.equal("#204080", Accent.hex())
        assert.are.equal(50, Accent.opacity())
        config.accent_enabled = true
        assert.is_true(Accent.isEnabled())
        assert.are.equal(color, tostring(Accent.color()))
    end)

    it("contrasts labels and compensates colors for night mode", function()
        assert.are.equal(Blitbuffer.COLOR_WHITE, Accent.foreground())
        screen.night_mode = true
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(223, 191, 127, 255)), tostring(Accent.color()))
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.foreground())
        screen.night_mode = false
        _G.__ZEN_UI_PLUGIN.config.accent_color = "#FFFF80"
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.foreground())
        _G.__ZEN_UI_PLUGIN.config.accent_color = "#0080FF"
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.foreground())
    end)

    it("blends opacity over the interface background and updates contrast and cached colors", function()
        local config = _G.__ZEN_UI_PLUGIN.config
        assert.are.equal(100, Accent.opacity())
        config.accent_opacity = 50
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(143, 159, 191, 255)), tostring(Accent.color()))
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.foreground())
        screen.night_mode = true
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(239, 223, 191, 255)), tostring(Accent.color()))
        config.accent_opacity = 0
        assert.are.equal(tostring(Blitbuffer.COLOR_WHITE:getColorRGB32()), tostring(Accent.color()))
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.foreground())
        screen.night_mode = false
        assert.are.equal(tostring(Blitbuffer.COLOR_WHITE:getColorRGB32()), tostring(Accent.color()))
        config.accent_opacity = 100
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(32, 64, 128, 255)), tostring(Accent.color()))
        config.accent_color, config.accent_opacity = "#000000", 50
        assert.is_true(Accent.isEnabled())
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(127, 127, 127, 255)), tostring(Accent.color()))
        screen.night_mode = true
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(127, 127, 127, 255)), tostring(Accent.color()))
        screen.isColorScreen = function() return false end
        assert.is_false(Accent.isEnabled())
        assert.are.equal(Blitbuffer.COLOR_BLACK, Accent.color())
    end)

    it("clamps saved opacity and falls back to full opacity for invalid values", function()
        for _i, entry in ipairs({
            { false, 100 }, { {}, 100 }, { "invalid", 100 },
            { -10, 0 }, { 140, 100 }, { 49.6, 50 }, { "25", 25 },
        }) do
            _G.__ZEN_UI_PLUGIN.config.accent_opacity = entry[1]
            assert.are.equal(entry[2], Accent.opacity())
        end
    end)

    it("uses the navbar accent by default and restores saved colors when disabled", function()
        local config = _G.__ZEN_UI_PLUGIN.config
        config.navbar = {}
        local defaults = {
            active_tab_color = { 0, 0, 0 },
            outlined_color = { 0x4F, 0x6F, 0x8F },
            filled_background_color = { 0x4F, 0x6F, 0x8F },
        }
        for key, default in pairs(defaults) do
            assert.are.same({ 32, 64, 128 }, Accent.navbarColor(config, key, default))
            config.navbar[key] = default
            assert.are.same({ 32, 64, 128 }, Accent.navbarColor(config, key, default))
            config.navbar[key] = { 12, 34, 56 }
            config.navbar[key .. "_custom"] = true
            assert.are.same({ 32, 64, 128 }, Accent.navbarColor(config, key, default))
            config.navbar.active_tab_use_accent = false
            assert.are.same({ 12, 34, 56 }, Accent.navbarColor(config, key, default))
            config.navbar[key] = default
            assert.are.same(default, Accent.navbarColor(config, key, default))
            config.navbar.active_tab_use_accent = true
            assert.are.same({ 32, 64, 128 }, Accent.navbarColor(config, key, default))
        end
        local white = { 255, 255, 255 }
        assert.are.same(white, Accent.navbarColor(config, "filled_outline_color", white))
        config.accent_color = "#336699"
        assert.are.same({ 51, 102, 153 }, Accent.navbarColor(config, "active_tab_color", defaults.active_tab_color))
        config.accent_color = "#000000"
        assert.are.same({ 0, 0, 0 }, Accent.navbarColor(config, "outlined_color", defaults.outlined_color))
        screen.night_mode = true
        assert.are.same({ 0, 0, 0 }, Accent.navbarColor(config, "outlined_color", defaults.outlined_color))
        screen.night_mode = false
        config.accent_color = "#336699"
        config.accent_enabled = false
        assert.are.same(defaults.active_tab_color, Accent.navbarColor(config, "active_tab_color", defaults.active_tab_color))
        config.accent_enabled = true
        screen.isColorScreen = function() return false end
        assert.are.same(defaults.active_tab_color, Accent.navbarColor(config, "active_tab_color", defaults.active_tab_color))
        for key, default in pairs(defaults) do
            assert.are.same(default, config.navbar[key])
            assert.is_true(config.navbar[key .. "_custom"])
        end
    end)

    it("uses accent opacity and cancels its night compensation before navbar painting", function()
        local config = _G.__ZEN_UI_PLUGIN.config
        config.accent_opacity = 50
        local default = { 0, 0, 0 }
        assert.are.same({ 143, 159, 191 }, Accent.navbarColor(config, "active_tab_color", default))
        screen.night_mode = true
        assert.are.same({ 16, 32, 64 }, Accent.navbarColor(config, "active_tab_color", default))
        config.accent_opacity = 100
        assert.are.same({ 32, 64, 128 }, Accent.navbarColor(config, "active_tab_color", default))
    end)

    it("uses the accent and its opacity for badges without a custom color", function()
        local utils = require("common/utils")
        local config = {
            accent_color = "#204080", accent_opacity = 100,
            browser_cover_badges = {},
        }
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(32, 64, 128, 255)), tostring(utils.getBadgeColor(config)))
        assert.are.equal(Blitbuffer.COLOR_WHITE, utils.getBadgeTextColor(config))
        assert.is_true(utils.isBadgeDark(config))
        config.accent_opacity = 50
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(143, 159, 191, 255)), tostring(utils.getBadgeColor(config)))
        assert.are.equal(Blitbuffer.COLOR_BLACK, utils.getBadgeTextColor(config))
        assert.is_false(utils.isBadgeDark(config))
        config.accent_color, config.accent_opacity = "#000000", 100
        assert.are.equal(Blitbuffer.COLOR_BLACK, utils.getBadgeColor(config))
        assert.are.equal(Blitbuffer.COLOR_WHITE, utils.getBadgeTextColor(config))
        config.accent_color = "#204080"
        screen.isColorScreen = function() return false end
        assert.are.equal(Blitbuffer.COLOR_BLACK, utils.getBadgeColor(config))
        assert.are.equal(Blitbuffer.COLOR_WHITE, utils.getBadgeTextColor(config))
    end)

    it("preserves custom badge colors and contrast when the accent changes", function()
        local utils = require("common/utils")
        local config = {
            accent_color = "#204080", accent_opacity = 50,
            browser_cover_badges = { badge_color = { 255, 255, 0 } },
        }
        local yellow = tostring(Blitbuffer.ColorRGB32(255, 255, 0, 255))
        assert.are.equal(yellow, tostring(utils.getBadgeColor(config)))
        assert.are.equal(Blitbuffer.COLOR_BLACK, utils.getBadgeTextColor(config))
        assert.is_false(utils.isBadgeDark(config))
        config.accent_color, config.accent_opacity = "#FF0000", 100
        assert.are.equal(yellow, tostring(utils.getBadgeColor(config)))
        assert.are.same({ 255, 255, 0 }, config.browser_cover_badges.badge_color)

        config.browser_cover_badges.badge_color = { 0, 0, 0 }
        assert.are.equal(tostring(Blitbuffer.ColorRGB32(0, 0, 0, 255)), tostring(utils.getBadgeColor(config)))
        assert.are.equal(Blitbuffer.COLOR_WHITE, utils.getBadgeTextColor(config))
        assert.is_true(utils.isBadgeDark(config))
        screen.isColorScreen = function() return false end
        assert.are.equal(Blitbuffer.COLOR_WHITE, utils.getBadgeTextColor(config))

        config.browser_cover_badges.badge_color = nil
        screen.isColorScreen = function() return true end
        assert.are.equal(tostring(Accent.color(config)), tostring(utils.getBadgeColor(config)))
    end)

    it("colors the slider rail and fill while keeping toggle outlines black", function()
        local bb = Blitbuffer.new(160, 60, Blitbuffer.TYPE_BBRGB32)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local slider = require("common/ui/zen_slider"):new{
            width = 120, value_min = 0, value_max = 100, value = 50, knob_radius = 8,
        }
        slider:paintTo(bb, 0, 0)
        for _i, x in ipairs({ 20, 60, 100 }) do
            assert.are.equal(tostring(Accent.color()), tostring(bb:getPixel(x, 11)))
        end
        local toggle = require("common/ui/zen_toggle"):new{ value = true }
        toggle:paintTo(bb, 0, 30)
        for _i, pos in ipairs({ { 28, 30 }, { 1, 44 }, { 54, 44 } }) do
            assert.are.equal(0, bb:getPixel(pos[1], pos[2]):getColor8().a)
        end
        assert.are.equal(tostring(Accent.color()), tostring(bb:getPixel(15, 44)))
        assert.are.equal(255, bb:getPixel(42, 44):getColor8().a)
        toggle:setValue(false)
        toggle:paintTo(bb, 70, 30)
        assert.are.equal(0, bb:getPixel(98, 30):getColor8().a)
        assert.are.equal(255, bb:getPixel(112, 44):getColor8().a)
        bb:free()
    end)

    it("preserves explicit slider colors", function()
        local slider = require("common/ui/zen_slider"):new{
            width = 120, value_min = 0, value_max = 100,
            fill_color = Blitbuffer.COLOR_GRAY, track_color = Blitbuffer.COLOR_LIGHT_GRAY,
            knob_color = Blitbuffer.COLOR_BLACK,
        }
        assert.are.equal(Blitbuffer.COLOR_GRAY, slider.fill_color)
        assert.are.equal(Blitbuffer.COLOR_LIGHT_GRAY, slider.track_color)
        assert.are.equal(Blitbuffer.COLOR_BLACK, slider.knob_color)
    end)

    it("keeps the rail color unchanged when the fill grows over it and retreats", function()
        local bb = Blitbuffer.new(140, 40, Blitbuffer.TYPE_BBRGB32)
        for _i, enabled in ipairs({ true, false }) do
            _G.__ZEN_UI_PLUGIN.config.accent_enabled = enabled
            local slider = require("common/ui/zen_slider"):new{
                width = 120, value_min = 0, value_max = 100, knob_radius = 8,
                hide_knob = true,
            }
            local color = tostring(Accent.color():getColorRGB32())
            for _j, value in ipairs({ 25, 75, 25 }) do
                slider:setValue(value)
                slider:paintTo(bb, 10, 5)
                assert.are.equal(color, tostring(bb:getPixel(80, 16)))
                assert.are.equal(color, tostring(bb:getPixel(20, 16)))
            end
        end
        bb:free()
    end)

    it("keeps the slider accent during drags and after release", function()
        local UIManager = require("ui/uimanager")
        local slider = require("common/ui/zen_slider"):new{
            width = 120, value_min = 0, value_max = 100, value = 50, knob_radius = 8,
        }
        local bb = Blitbuffer.new(160, 60, Blitbuffer.TYPE_BBRGB32)
        local owner = {}
        slider.on_change = function() slider:paintTo(bb, 0, 0) end
        UIManager.setDirty = function(_self, widget, mode)
            assert.are.equal(owner, widget)
            assert.are.equal("ui", mode)
            slider:paintTo(bb, 0, 0)
        end
        for _i, finish in ipairs({ "handlePanRelease", "handleSwipe", "handleMultiSwipe" }) do
            slider:paintTo(bb, 0, 0)
            local gesture = { direction = "east", pos = {
                x = slider:_knobAbsX(), intersectWith = function() return true end,
            } }
            assert.is_true(slider:handlePan(gesture))
            assert.are.equal(tostring(Accent.color()), tostring(bb:getPixel(20, 11)))
            slider.hide_knob = false
            slider:paintTo(bb, 0, 0)
            assert.are.equal(tostring(Accent.color()), tostring(bb:getPixel(60, 11)))
            assert.is_true(slider[finish](slider, gesture, owner, slider.dimen))
            assert.is_false(slider._dragging)
            for _j, x in ipairs({ 20, 60 }) do
                assert.are.equal(tostring(Accent.color()), tostring(bb:getPixel(x, 11)))
            end
        end
        bb:free()
    end)

    it("refreshes the whole slider on first contact and skips repeated drag values", function()
        local slider = require("common/ui/zen_slider"):new{
            width = 120, value_min = 0, value_max = 100, value = 50, knob_radius = 8,
        }
        local calls, regions = 0, {}
        slider.on_change = function()
            calls = calls + 1
            regions[calls] = slider:dirtyDimen()
        end
        local gesture = { direction = "east", pos = {
            x = slider:_knobAbsX(), intersectWith = function() return true end,
        } }
        assert.is_true(slider:handlePan(gesture))
        assert.are.equal(1, calls)
        assert.are.same(slider.dimen, regions[1])
        assert.is_true(slider:handlePan(gesture))
        assert.are.equal(1, calls)
        gesture.pos.x = slider:_valueToX(60)
        assert.is_true(slider:handlePan(gesture))
        assert.are.equal(2, calls)
        assert.are.equal(60, slider:getValue())
        assert.is_true(regions[2].w < slider.dimen.w)
        assert.is_true(slider:handlePan(gesture))
        assert.are.equal(2, calls)
    end)

    it("includes every changed slider pixel in the drag refresh region", function()
        local slider = require("common/ui/zen_slider"):new{
            width = 120, value_min = 0, value_max = 100, value = 50, knob_radius = 8,
        }
        local bb = Blitbuffer.new(160, 60, Blitbuffer.TYPE_BBRGB32)
        slider:paintTo(bb, 20, 10)
        for _i, value in ipairs({ 50, 55, 100, 0, 50 }) do
            local before = bb:copy()
            slider._dragging, slider.hide_knob = true, true
            slider:applyPosition(20 + slider:_valueToX(value))
            slider:paintTo(bb, 20, 10)
            local region = slider:dirtyDimen()
            for y = 0, 59 do
                for x = 0, 159 do
                    if tostring(before:getPixel(x, y)) ~= tostring(bb:getPixel(x, y)) then
                        assert.is_true(x >= region.x and x < region.x + region.w
                            and y >= region.y and y < region.y + region.h)
                    end
                end
            end
            before:free()
        end
        bb:free()
    end)

    it("keeps active icons transparent and leaves the shared buffer untouched", function()
        local source = Blitbuffer.new(2, 2, Blitbuffer.TYPE_BBRGB32)
        source:setPixel(0, 0, Blitbuffer.ColorRGB32(0, 0, 0, 128))
        local icon = { _is_straight_alpha = true, _render = function(self) self._bb = source end }
        Accent.styleIcon(icon, true)
        assert.is_true(icon.alpha)
        assert.is_true(icon._bb_disposable)
        assert.are.equal(0, source:getPixel(0, 0).r)
        assert.are.equal(255, icon._bb:getPixel(0, 0).r)
        assert.are.equal(128, icon._bb:getPixel(0, 0).alpha)
        icon._bb:free()
        icon._is_straight_alpha = false
        Accent.styleIcon(icon, true)
        assert.are.equal(128, icon._bb:getPixel(0, 0).r)
        assert.are.equal(128, icon._bb:getPixel(0, 0).alpha)
        icon._bb:free()
        source:free()
        _G.__ZEN_UI_PLUGIN.config.accent_color = "#FFFF80"
        Accent.styleIcon({ _render = function() error("light accents keep dark icons") end }, true)
    end)
end)
