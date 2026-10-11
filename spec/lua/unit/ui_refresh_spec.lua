describe("UI full refresh preference", function()
    local saved_settings
    local getFullRefreshMode = require("common/ui/refresh")

    before_each(function()
        saved_settings = G_reader_settings
        _G.G_reader_settings = ZenSpec.memorySettings()
    end)

    after_each(function()
        _G.G_reader_settings = saved_settings
    end)

    it("keeps the full waveform by default and follows live setting changes", function()
        assert.are.equal("full", getFullRefreshMode())
        G_reader_settings:saveSetting("avoid_flashing_ui", true)
        assert.are.equal("ui", getFullRefreshMode())
        G_reader_settings:saveSetting("avoid_flashing_ui", false)
        assert.are.equal("full", getFullRefreshMode())
    end)
end)
