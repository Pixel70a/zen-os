describe("Kindle wakeup recovery", function()
    local originals, Device, UIManager, powerd, scheduled, events
    local state, fresh_state, reconnects, resumes, alarm_checks, wakeups, open_error
    local old_handle, fresh_handle
    local module_names = {
        "device", "device/wakeupmgr", "device/kindle/mockrtc", "ui/uimanager",
        "liblipclua", "common/zen_logger", "modules/global/patches/kindle_wakeup_recovery",
    }

    before_each(function()
        originals = {}
        for _i, name in ipairs(module_names) do originals[name] = package.loaded[name] end
        scheduled, events = {}, {}
        state, fresh_state = nil, "active"
        reconnects, resumes, alarm_checks, wakeups = 0, 0, 0, 0
        open_error = false
        old_handle = {
            get_string_property = function() return state end,
            close = function(self) self.closed = true end,
        }
        fresh_handle = {
            get_string_property = function() return fresh_state end,
            get_int_property = function() return 78 end,
        }
        local wakeup_mgr = {
            isWakeupAlarmScheduled = function()
                alarm_checks = alarm_checks + 1
                return true
            end,
            wakeupAction = function(_self, delay)
                assert.are.equal(90, delay)
                wakeups = wakeups + 1
                return true
            end,
        }
        ZenSpec.replace("device/wakeupmgr", { new = function() return wakeup_mgr end })
        ZenSpec.replace("device/kindle/mockrtc", {})
        UIManager = {
            scheduleIn = function(_self, delay, callback, owner)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback, owner = owner }
            end,
            broadcastEvent = function(_self, event) events[#events + 1] = event.handler end,
        }
        ZenSpec.replace("ui/uimanager", UIManager)
        local KindlePowerD = dofile("frontend/device/kindle/powerd.lua")
        Device = {
            isKindle = function() return true end,
            supportsScreensaver = function() return true end,
            hasFrontlight = function() return false end,
            screen_saver_mode = true,
            input_inhibited = true,
            _afterResume = function(self)
                self.input_inhibited = false
                UIManager:broadcastEvent(require("ui/event"):new("Resume"))
            end,
            outofScreenSaver = function(self)
                resumes = resumes + 1
                self.screen_saver_mode = false
                powerd:afterResume()
            end,
            getPowerDevice = function() return powerd end,
        }
        powerd = setmetatable({ device = Device, lipc_handle = old_handle }, { __index = KindlePowerD })
        powerd:UIManagerReadyHW(UIManager)
        powerd:initWakeupMgr()
        ZenSpec.replace("device", Device)
        ZenSpec.replace("liblipclua", { init = function(name)
            reconnects = reconnects + 1
            assert.are.equal("com.github.koreader.kindlepowerd", name)
            assert.is_true(old_handle.closed)
            if open_error then error("LIPC unavailable") end
            return fresh_handle
        end })
        ZenSpec.replace("common/zen_logger", { new = function()
            return { warn = function() end }
        end })
        ZenSpec.unload("modules/global/patches/kindle_wakeup_recovery")
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do package.loaded[name] = originals[name] end
    end)

    local function finish_wakeup()
        powerd:wakeupFromSuspend(32802)
        assert.are.equal(1, #scheduled)
        local task = table.remove(scheduled)
        assert.are.equal(15, task.delay)
        task.callback(task.owner)
    end

    it("recovers a missed screensaver exit after reconnecting to powerd", function()
        require("modules/global/patches/kindle_wakeup_recovery")()
        finish_wakeup()
        assert.is_false(Device.screen_saver_mode)
        assert.is_false(Device.input_inhibited)
        assert.are.equal(1, resumes)
        assert.are.equal(1, reconnects)
        assert.are.equal(fresh_handle, powerd.lipc_handle)
        assert.are.equal(78, powerd:getCapacityHW())
        assert.are.same({ "onResume" }, events)
    end)

    it("recovers a missed exit with a healthy connection", function()
        state = "active"
        require("modules/global/patches/kindle_wakeup_recovery")()
        finish_wakeup()
        assert.are.equal(1, resumes)
        assert.are.equal(0, reconnects)
        assert.is_nil(old_handle.closed)
    end)

    it("preserves background wakeup alarms without resuming the UI", function()
        fresh_state = "screenSaver"
        require("modules/global/patches/kindle_wakeup_recovery")()
        finish_wakeup()
        assert.is_true(Device.screen_saver_mode)
        assert.is_true(Device.input_inhibited)
        assert.are.equal(0, resumes)
        assert.are.equal(1, reconnects)
        assert.are.equal(1, alarm_checks)
        assert.are.equal(1, wakeups)
        assert.are.same({}, events)
    end)

    it("does not resume when powerd remains unavailable", function()
        fresh_state = nil
        require("modules/global/patches/kindle_wakeup_recovery")()
        finish_wakeup()
        assert.is_true(Device.input_inhibited)
        assert.are.equal(0, resumes)
        assert.are.equal(1, reconnects)
        assert.are.equal(0, alarm_checks)
    end)

    it("does not resume for sleeping or unknown power states", function()
        require("modules/global/patches/kindle_wakeup_recovery")()
        for _i, value in ipairs({ "screenSaver", "suspended", "readyToSuspend", "", "unknown" }) do
            state = value
            finish_wakeup()
            assert.is_true(Device.input_inhibited, value)
            assert.are.equal(0, resumes, value)
            assert.are.equal(0, reconnects, value)
        end
    end)

    it("tolerates a failed reconnect", function()
        open_error = true
        require("modules/global/patches/kindle_wakeup_recovery")()
        assert.has_no.errors(finish_wakeup)
        assert.is_nil(powerd.lipc_handle)
        assert.is_true(Device.input_inhibited)
        assert.are.equal(0, resumes)
        assert.are.equal(1, reconnects)
    end)

    it("tolerates an unavailable replacement handle", function()
        fresh_handle = nil
        require("modules/global/patches/kindle_wakeup_recovery")()
        assert.has_no.errors(finish_wakeup)
        assert.is_nil(powerd.lipc_handle)
        assert.is_true(Device.input_inhibited)
        assert.are.equal(0, resumes)
    end)

    it("does not repeat a normal screensaver exit", function()
        state = "active"
        require("modules/global/patches/kindle_wakeup_recovery")()
        Device:outofScreenSaver()
        finish_wakeup()
        assert.are.equal(1, resumes)
        assert.are.equal(0, reconnects)
        assert.are.same({ "onResume" }, events)
    end)

    it("installs once", function()
        local apply = require("modules/global/patches/kindle_wakeup_recovery")
        apply()
        local patched = powerd.checkUnexpectedWakeup
        apply()
        assert.are.equal(patched, powerd.checkUnexpectedWakeup)
    end)

    it("leaves other devices and native screensavers unchanged", function()
        local original = powerd.checkUnexpectedWakeup
        local apply = require("modules/global/patches/kindle_wakeup_recovery")
        Device.isKindle = function() return false end
        apply()
        assert.are.equal(original, powerd.checkUnexpectedWakeup)
        Device.isKindle = function() return true end
        Device.supportsScreensaver = function() return false end
        apply()
        assert.are.equal(original, powerd.checkUnexpectedWakeup)
    end)
end)
