describe("Kindle exit message", function()
    local originals, getenv_stub, execute_stub, buffer, Device, UIManager, events, framework, message
    local module_names = {
        "device", "ui/uimanager", "ui/font", "ui/widget/textboxwidget", "gettext",
        "ui/widget/imagewidget", "common/plugin_root", "common/utils",
        "util",
        "common/zen_logger", "modules/global/patches/kindle_exit_message",
    }

    before_each(function()
        originals = {}
        for _i, name in ipairs(module_names) do originals[name] = package.loaded[name] end
        local original_getenv = os.getenv
        framework, events, message = "yes", {}, nil
        execute_stub, buffer = nil, nil
        getenv_stub = stub(os, "getenv", function(name)
            if name == "STOP_FRAMEWORK" then return framework end
            return original_getenv(name)
        end)
        Device = {
            isKindle = function() return true end,
            exit = function(self, code)
                assert.are.equal(Device, self)
                events[#events + 1] = "exit"
                self.screen:close()
                return code, "finished"
            end,
            screen = {
                bb = {},
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_self, value) return value end,
                close = function() events[#events + 1] = "close" end,
                refreshFull = function(_self, ...)
                    assert.are.same({ 0, 0, 600, 800 }, { ... })
                    events[#events + 1] = "refresh"
                end,
            },
        }
        for _i, name in ipairs({ "beforePaint", "clear", "refreshWaitForLast", "afterPaint" }) do
            Device.screen[name] = function() events[#events + 1] = name end
        end
        UIManager = { _exit_code = 0 }
        ZenSpec.replace("device", Device)
        ZenSpec.replace("ui/uimanager", UIManager)
        ZenSpec.replace("gettext", function(text) return "translated: " .. text end)
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("common/plugin_root", ZenSpec.root)
        ZenSpec.replace("common/utils", { resolveLocalIcon = function(directory, name)
            assert.are.equal(ZenSpec.root .. "/icons/", directory)
            assert.are.equal("zen_ui", name)
            return directory .. name .. ".svg"
        end })
        ZenSpec.replace("ui/widget/imagewidget", { new = function(_self, values)
            assert.are.equal(ZenSpec.root .. "/icons/zen_ui.svg", values.file)
            assert.are.same({ 240, 240 }, { values.width, values.height })
            return {
                paintTo = function(_widget, bb, x, y)
                    assert.are.equal(Device.screen.bb, bb)
                    assert.are.same({ 180, 255 }, { x, y })
                    events[#events + 1] = "logo"
                end,
                free = function() events[#events + 1] = "logo_free" end,
            }
        end })
        ZenSpec.replace("ui/widget/textboxwidget", { new = function(_self, values)
            message = values
            values.getSize = function() return { w = 560, h = 30 } end
            values.paintTo = function(_widget, bb, x, y)
                assert.are.equal(Device.screen.bb, bb)
                assert.are.same({ 20, 515 }, { x, y })
                events[#events + 1] = "paint"
            end
            values.free = function() events[#events + 1] = "free" end
            return values
        end })
        ZenSpec.replace("common/zen_logger", { new = function()
            return { warn = function() events[#events + 1] = "warning" end }
        end })
        ZenSpec.unload("modules/global/patches/kindle_exit_message")
    end)

    after_each(function()
        if execute_stub then execute_stub:revert() end
        if buffer then buffer:free() end
        getenv_stub:revert()
        for _i, name in ipairs(module_names) do package.loaded[name] = originals[name] end
    end)

    it("paints and completes the refresh before closing the framebuffer", function()
        require("modules/global/patches/kindle_exit_message")()
        local code, result = Device:exit(23)

        assert.are.same({ "exit", "beforePaint", "clear", "logo", "paint", "refresh", "refreshWaitForLast",
            "afterPaint", "free", "logo_free", "close" }, events)
        assert.are.equal("translated: Restoring Kindle GUI…", message.text)
        assert.are.equal("center", message.alignment)
        assert.are.equal(560, message.width)
        assert.are.equal(23, code)
        assert.are.equal("finished", result)
    end)

    it("also handles an implicit normal exit", function()
        require("modules/global/patches/kindle_exit_message")()
        UIManager._exit_code = nil
        Device:exit()
        assert.is_truthy(message)
    end)

    it("does not paint during framebuffer reinitialization", function()
        Device.exit = function(self)
            self.screen:close(true)
            events[#events + 1] = "mode_restored"
            self.screen:close()
        end
        require("modules/global/patches/kindle_exit_message")()
        Device:exit()
        assert.are.same({ "close", "mode_restored", "beforePaint", "clear", "logo", "paint",
            "refresh", "refreshWaitForLast", "afterPaint", "free", "logo_free", "close" }, events)
    end)

    for _i, status in ipairs({ 0, 1 }) do
        it(status == 0 and "starts the helper with native framebuffer copies"
                or "cleans up snapshots if the helper cannot start", function()
            local BB = require("ffi/blitbuffer")
            buffer = BB.new(4, 3, BB.TYPE_BB8)
            buffer:fill(BB.Color8(123))
            Device.screen.bb, Device.screen.data = buffer, buffer.data
            Device.screen.fb_size, Device.screen.device_node = 12, "/dev/fb0"
            Device.screen.night_mode = true
            local arguments
            ZenSpec.replace("util", { shell_escape = function(args)
                arguments = args
                return "quoted helper command"
            end })
            execute_stub = stub(os, "execute", function(command)
                assert.are.equal("quoted helper command >>crash.log 2>&1 &", command)
                assert.are.equal("sh", arguments[1])
                assert.are.equal(ZenSpec.root .. "/modules/global/kindle_restore_screen.sh", arguments[2])
                assert.are.equal("12", arguments[4])
                assert.are.equal("/dev/fb0", arguments[5])
                local screen = assert(io.open(arguments[3] .. "/screen", "rb"))
                assert.are.equal(string.rep(string.char(123), 12), screen:read("*a"))
                screen:close()
                local blank = assert(io.open(arguments[3] .. "/blank", "rb"))
                assert.are.equal(string.rep(string.char(255), 12), blank:read("*a"))
                blank:close()
                return status
            end)
            require("modules/global/patches/kindle_exit_message")()
            Device:exit()
            assert.is_false(Device.screen.night_mode)
            assert.are.equal("close", events[#events])
            if status == 0 then
                os.remove(arguments[3] .. "/screen")
                os.remove(arguments[3] .. "/blank")
                os.remove(arguments[3])
            else
                assert.is_nil(io.open(arguments[3] .. "/screen", "rb"))
                assert.are.equal("warning", events[#events - 1])
            end
        end)
    end

    it("skips restart, reboot, power-off, and other special exits", function()
        require("modules/global/patches/kindle_exit_message")()
        for _i, code in ipairs({ 85, 86, 88, 1 }) do
            UIManager._exit_code = code
            Device:exit()
        end
        UIManager._exit_code = 0
        UIManager._entered_poweroff_stage = true
        Device:exit()
        assert.are.same({ "exit", "close", "exit", "close", "exit", "close", "exit", "close", "exit", "close" }, events)
    end)

    it("skips the message when the Kindle framework is still running", function()
        require("modules/global/patches/kindle_exit_message")()
        framework = "no"
        Device:exit()
        framework = nil
        Device:exit()
        assert.are.same({ "exit", "close", "exit", "close" }, events)
    end)

    it("continues device teardown if rendering fails", function()
        require("modules/global/patches/kindle_exit_message")()
        Device.screen.clear = function() error("framebuffer unavailable") end
        local code, result = Device:exit(23)
        assert.are.same({ "exit", "beforePaint", "warning", "close" }, events)
        assert.are.equal(23, code)
        assert.are.equal("finished", result)
    end)

    it("installs once and leaves other devices unchanged", function()
        local apply = require("modules/global/patches/kindle_exit_message")
        local original_exit = Device.exit
        Device.isKindle = function() return false end
        apply()
        assert.are.equal(original_exit, Device.exit)
        Device.isKindle = function() return true end
        apply()
        local patched = Device.exit
        apply()
        assert.are.equal(patched, Device.exit)
    end)
end)
