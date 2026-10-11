describe("Quickstart embedded color picker", function()
    local Screen, saved_modules, closed, applied, freed
    local module_names = {
        "common/quickstart/quickstart_screen", "common/ui/zen_button", "common/ui/zen_title_style",
        "device", "device/input", "gettext", "ui/font", "ui/geometry", "ui/uimanager",
        "ui/widget/container/inputcontainer", "ui/widget/iconwidget", "ui/widget/imagewidget",
        "ui/widget/textboxwidget", "ui/widget/textwidget",
        "common/ui/color_wheel_widget",
    }

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(module_names) do saved_modules[name] = package.loaded[name] end
        closed, applied, freed = 0, 0, 0
        local Widget = {}
        function Widget:extend(values) return setmetatable(values, { __index = self }) end
        function Widget:new(values)
            values = self:extend(values)
            if values.init then values:init() end
            return values
        end
        function Widget:registerTouchZones() end
        function Widget:getSize() return { w = self.width or 120, h = self.height or 24 } end
        function Widget:paintTo() end
        function Widget:free() end
        for _i, name in ipairs({
            "ui/widget/container/inputcontainer", "ui/widget/textboxwidget", "ui/widget/textwidget",
            "ui/widget/iconwidget", "ui/widget/imagewidget",
        }) do ZenSpec.replace(name, Widget) end
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_self, value) return value end,
            },
            hasKeys = function() return false end,
        })
        ZenSpec.replace("device/input", {})
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("ui/geometry", { new = function(_self, values) return values end })
        ZenSpec.replace("ui/uimanager", {
            setDirty = function() end,
            close = function() closed = closed + 1 end,
            scheduleIn = function() end,
        })
        ZenSpec.replace("common/ui/zen_button", {
            paintFilled = function(_bb, x, y, w, h, text)
                return { x = x, y = y, w = w, h = h, text = text }
            end,
        })
        ZenSpec.replace("common/ui/color_wheel_widget", {
            new = function(_self, values)
                values.paintTo = function() end
                values.onApply = function() applied = applied + 1 end
                values.free = function() freed = freed + 1 end
                return values
            end,
        })
        ZenSpec.replace("common/ui/zen_title_style", {
            HEADER_CONTENT_HEIGHT = 60, DIVIDER_HEIGHT = 1,
            VERTICAL_PADDING = 10, ROW_HEIGHT = 40,
            DIVIDER_COLOR = require("ffi/blitbuffer").COLOR_BLACK,
            getTitleFace = function() return {} end,
        })
        ZenSpec.unload("common/quickstart/quickstart_screen")
        Screen = require("common/quickstart/quickstart_screen")
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do package.loaded[name] = saved_modules[name] end
        _G.__ZEN_QUICKSTART_JUST_CLOSED = nil
    end)

    local function screen()
        return Screen:new{
            pages = {{
                title = "Accent color",
                description = "Choose a color",
                color_picker = { hex = "#0088FF", opacity = 75 },
            }, { title = "You're All Set", finale = true }},
        }
    end

    local function paint(widget)
        local Blitbuffer = require("ffi/blitbuffer")
        local bb = Blitbuffer.new(600, 800, Blitbuffer.TYPE_BBRGB32)
        widget:paintTo(bb, 0, 0)
        bb:free()
    end

    it("embeds the picker below the description without an accent button", function()
        local widget = screen()
        paint(widget)
        local picker = assert(widget[1])
        assert.is_true(picker.embedded)
        assert.are.equal(widget, picker.show_parent)
        assert.are.equal("#0088FF", picker.hex)
        assert.are.equal(75, picker.opacity)
        assert.is_true(picker.dimen.h < widget._L.dot_y - widget._L.img_y)
        assert.is_nil(widget._finale_btn)
        assert.are.equal(1, widget._page_idx)
        assert.are.equal(0, closed)
    end)

    it("applies and frees the embedded picker when continuing", function()
        local widget = screen()
        paint(widget)
        widget:_onTap({ pos = { x = 500, y = widget._L.nav_y + 1 } })

        assert.are.equal(2, widget._page_idx)
        assert.is_nil(widget[1])
        assert.are.equal(1, applied)
        assert.are.equal(1, freed)
    end)

    it("applies the embedded selection when closing the quickstart", function()
        local widget = screen()
        paint(widget)

        widget:onClose()

        assert.are.equal(1, applied)
        assert.are.equal(1, closed)
    end)

    it("keeps the finale Get Started button closing the quickstart", function()
        local widget = screen()
        widget:onQsNextPage()
        paint(widget)
        local button = widget._finale_btn
        assert.are.equal("Get Started", button.text)

        widget:_onTap({ pos = { x = button.x + 1, y = button.y + 1 } })

        assert.are.equal(1, closed)
        assert.are.equal(0, applied)
    end)
end)
