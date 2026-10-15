describe("Kindle battery capacity fallback", function()
    local originals, Device, powerd, level, battery_file
    local module_names = {
        "device", "device/wakeupmgr", "luasettings", "ui/uimanager",
        "dispatcher", "ui/widget/confirmbox", "ui/widget/keyvaluepage",
        "modules/global/patches/kindle_battery_capacity",
    }

    local function write_capacity(value)
        local file = assert(io.open(battery_file, "w"))
        file:write(value)
        file:close()
    end

    before_each(function()
        originals = {}
        for _i, name in ipairs(module_names) do originals[name] = package.loaded[name] end
        battery_file, level = os.tmpname(), 80
        write_capacity("79\n")
        ZenSpec.replace("device/wakeupmgr", {})
        local KindlePowerD = dofile("frontend/device/kindle/powerd.lua")
        powerd = setmetatable({
            batt_capacity_file = battery_file,
            lipc_handle = { get_int_property = function(_self, _service, property)
                if property == "battLevel" then return level end
                return 0
            end },
        }, { __index = KindlePowerD })
        Device = {
            isKindle = function() return true end,
            getPowerDevice = function() return powerd end,
        }
        ZenSpec.replace("device", Device)
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.replace("luasettings", { open = function()
            return ZenSpec.memorySettings()
        end })
        for _i, name in ipairs({ "dispatcher", "ui/widget/confirmbox", "ui/widget/keyvaluepage" }) do
            ZenSpec.replace(name, {})
        end
        ZenSpec.unload("modules/global/patches/kindle_battery_capacity")
    end)

    after_each(function()
        os.remove(battery_file)
        for _i, name in ipairs(module_names) do package.loaded[name] = originals[name] end
    end)

    it("keeps native battery statistics working through suspend and resume when LIPC fails", function()
        local BatteryStat = dofile("plugins/batterystat.koplugin/main.lua")
        level = nil
        assert.has_error(function() BatteryStat:onSuspend() end)

        require("modules/global/patches/kindle_battery_capacity")()
        assert.has_no.errors(function() BatteryStat:onSuspend() end)
        assert.is_true(BatteryStat:stat().was_suspending)
        assert.are.equal(1, BatteryStat:stat().awake.percentage)

        write_capacity("78\n")
        assert.has_no.errors(function() BatteryStat:onResume() end)
        assert.is_false(BatteryStat:stat().was_suspending)
        assert.are.equal(1, BatteryStat:stat().sleeping.percentage)
        assert.are.equal(2, BatteryStat:stat().discharging.percentage)
    end)

    it("preserves successful LIPC readings, including zero", function()
        require("modules/global/patches/kindle_battery_capacity")()
        assert.are.equal(80, powerd:getCapacityHW())
        level = 0
        assert.are.equal(0, powerd:getCapacityHW())
    end)

    it("returns to LIPC when it recovers", function()
        require("modules/global/patches/kindle_battery_capacity")()
        level = nil
        assert.are.equal(79, powerd:getCapacityHW())
        level = 78
        assert.are.equal(78, powerd:getCapacityHW())
    end)

    it("does not invent a percentage when both sources are unavailable", function()
        require("modules/global/patches/kindle_battery_capacity")()
        level = nil
        write_capacity("unavailable\n")
        assert.is_nil(powerd:getCapacityHW())
        os.remove(battery_file)
        assert.is_nil(powerd:getCapacityHW())
    end)

    it("installs once", function()
        local apply = require("modules/global/patches/kindle_battery_capacity")
        apply()
        local patched = powerd.getCapacityHW
        apply()
        assert.are.equal(patched, powerd.getCapacityHW)
    end)

    it("leaves other devices and Kindles without a battery file unchanged", function()
        local original = powerd.getCapacityHW
        local apply = require("modules/global/patches/kindle_battery_capacity")
        Device.isKindle = function() return false end
        apply()
        assert.are.equal(original, powerd.getCapacityHW)
        Device.isKindle = function() return true end
        powerd.batt_capacity_file = nil
        apply()
        assert.are.equal(original, powerd.getCapacityHW)
    end)
end)
