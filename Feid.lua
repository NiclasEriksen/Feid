-- Default Settings
local DEFAULT_SETTINGS = {
    frames = {},
    minAlpha = 0.5,
    maxAlpha = 1.0,
    fadeInDuration = 0.5,
    fadeOutDuration = 0.5,
    enabled = true,
    disableInParty = false,
    disableInRaids = false,
    disableInBGs = false,
    fullHPManaOnly = false,
}

-- Internal State
local isIdentifying = false
local resolvedFrames = {}

local fader = CreateFrame("Frame", "FeidMainFrame")

local frameCache = nil
local function GetFramesByPattern(pattern)
    local found = {}
    if string.find(pattern, "%*") then
        if not frameCache then
            frameCache = {}
            for name, value in pairs(getfenv(0)) do
                if type(value) == "table" and value.GetAlpha and value.SetAlpha then
                    table.insert(frameCache, { name = name, frame = value })
                end
            end
        end

        local luaPattern = string.gsub(pattern, "([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
        luaPattern = string.gsub(luaPattern, "%*", ".*")
        luaPattern = "^" .. luaPattern .. "$"
        
        for _, info in ipairs(frameCache) do
            if string.find(info.name, luaPattern) then
                table.insert(found, info.frame)
            end
        end
    else
        local frame = getglobal(pattern)
        if frame and frame.SetAlpha then
            table.insert(found, frame)
        end
    end
    return found
end

local function IsDisabledInZone()
    if not FeidDB then return false end

    -- 1. Check for Battlegrounds
    if FeidDB.disableInBGs then
        -- MAX_BATTLEFIELD_QUEUES is 3 in 1.12.1
        for i=1, 3 do
            local status = GetBattlefieldStatus(i)
            if status == "active" then return true end
        end
    end

    if FeidDB.disableInRaids and GetNumRaidMembers() > 0 then
        return true
    end

    if FeidDB.disableInParty then
        if GetNumPartyMembers() > 0 and GetNumRaidMembers() == 0 then
             return true
        end
    end
    
    return false
end

local function ResolveFrames()
    -- Create a map of existing frames to preserve their current alpha state if they are still matched
    local oldFrames = {}
    if resolvedFrames then
        for _, info in ipairs(resolvedFrames) do
            oldFrames[info.frame] = info.currentAlpha
        end
    end

    resolvedFrames = {}
    if not FeidDB or not FeidDB.frames then return end
    
    local added = {} -- To avoid duplicates if patterns overlap
    for pattern, config in pairs(FeidDB.frames) do
        local frames = GetFramesByPattern(pattern)
        for _, frame in ipairs(frames) do
            if not added[frame] then
                -- Ensure config is upgraded to table if it's old boolean/nil
                if type(config) ~= "table" then
                    config = { useDefault = true }
                    FeidDB.frames[pattern] = config
                end

                local current = oldFrames[frame] or (FeidDB and FeidDB.minAlpha) or 0.5
                
                table.insert(resolvedFrames, {
                    frame = frame,
                    currentAlpha = current,
                    targetAlpha = current,
                    config = config
                })
                added[frame] = true
            end
        end
    end
end

local function SetAllAlphas(alpha)
    for _, info in ipairs(resolvedFrames) do
        info.frame:SetAlpha(alpha)
        info.currentAlpha = alpha
        info.targetAlpha = alpha
    end
end

local function IsMouseOverFrame(frame)
    if not frame:IsVisible() then return false end
    local focus = GetMouseFocus()
    if focus == frame then return true end
    return MouseIsOver(frame)
end

-- Smooth Fading Logic
-- (Moved OnUpdate logic lower to combine with Identify Logic)

-- Event Handling
fader:RegisterEvent("PLAYER_REGEN_DISABLED")
fader:RegisterEvent("PLAYER_REGEN_ENABLED")
fader:RegisterEvent("PLAYER_ENTERING_WORLD")
fader:RegisterEvent("VARIABLES_LOADED")
fader:RegisterEvent("SPELLCAST_START")
fader:RegisterEvent("SPELLCAST_STOP")
fader:RegisterEvent("SPELLCAST_FAILED")
fader:RegisterEvent("SPELLCAST_INTERRUPTED")
fader:RegisterEvent("SPELLCAST_CHANNEL_START")
fader:RegisterEvent("SPELLCAST_CHANNEL_STOP")

local isCasting = false
local isChanneling = false

fader:SetScript("OnEvent", function()
    local event = event or arg1 -- For modern compat if needed, though event is global in 1.12.1
    if event == "VARIABLES_LOADED" then
        if not FeidDB then FeidDB = {} end
        for k, v in pairs(DEFAULT_SETTINGS) do
            if FeidDB[k] == nil then
                FeidDB[k] = v
            end
        end
        ResolveFrames()
        SetAllAlphas(FeidDB.minAlpha)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- targetAlpha is now handled in OnUpdate based on UnitAffectingCombat and Mouseover
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResolveFrames()
        -- Initial state check depends on combat
        local initialAlpha = UnitAffectingCombat("player") and FeidDB.maxAlpha or FeidDB.minAlpha
        SetAllAlphas(initialAlpha)
    elseif event == "SPELLCAST_START" then
        isCasting = true
    elseif event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        isCasting = false
    elseif event == "SPELLCAST_CHANNEL_START" then
        isChanneling = true
    elseif event == "SPELLCAST_CHANNEL_STOP" then
        isChanneling = false
    end
end)

---------------------------------------------------------
-- UI Configuration
---------------------------------------------------------

local function CreateConfigWindow()
    local f = CreateFrame("Frame", "FeidConfigFrame", UIParent)
    f:SetWidth(600)
    f:SetHeight(300)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -15)
    title:SetText("Feid Configuration")

    -- Vertical Separator 1 (between Sliders and Checkboxes)
    local vline1 = f:CreateTexture(nil, "ARTWORK")
    vline1:SetTexture(0.5, 0.5, 0.5, 0.5)
    vline1:SetWidth(1)
    vline1:SetPoint("TOPLEFT", f, "TOPLEFT", 160, -40)
    vline1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 160, 40)

    local function UpdateGlobalFading()
        for _, info in ipairs(resolvedFrames) do
            if not info.config or info.config.useDefault then
                -- Target alpha will be updated in next OnUpdate
            end
        end
    end

    -- Column 1: Sliders
    -- Min Alpha Slider
    local minSlider = CreateFrame("Slider", "FeidMinSlider", f, "OptionsSliderTemplate")
    minSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    getglobal(minSlider:GetName() .. "Text"):SetText("Min Opacity")
    minSlider:SetMinMaxValues(0, 1)
    minSlider:SetValueStep(0.05)
    minSlider:SetScript("OnValueChanged", function()
        FeidDB.minAlpha = this:GetValue()
        UpdateGlobalFading()
    end)

    -- Max Alpha Slider
    local maxSlider = CreateFrame("Slider", "FeidMaxSlider", f, "OptionsSliderTemplate")
    maxSlider:SetPoint("TOPLEFT", minSlider, "BOTTOMLEFT", 0, -30)
    getglobal(maxSlider:GetName() .. "Text"):SetText("Max Opacity")
    maxSlider:SetMinMaxValues(0, 1)
    maxSlider:SetValueStep(0.05)
    maxSlider:SetScript("OnValueChanged", function()
        FeidDB.maxAlpha = this:GetValue()
        UpdateGlobalFading()
    end)

    -- Fade In Slider
    local inSlider = CreateFrame("Slider", "FeidInSlider", f, "OptionsSliderTemplate")
    inSlider:SetPoint("TOPLEFT", maxSlider, "BOTTOMLEFT", 0, -30)
    getglobal(inSlider:GetName() .. "Text"):SetText("Fade In Time")
    inSlider:SetMinMaxValues(0, 2)
    inSlider:SetValueStep(0.1)
    inSlider:SetScript("OnValueChanged", function()
        FeidDB.fadeInDuration = this:GetValue()
    end)

    -- Fade Out Slider
    local outSlider = CreateFrame("Slider", "FeidOutSlider", f, "OptionsSliderTemplate")
    outSlider:SetPoint("TOPLEFT", inSlider, "BOTTOMLEFT", 0, -30)
    getglobal(outSlider:GetName() .. "Text"):SetText("Fade Out Time")
    outSlider:SetMinMaxValues(0, 2)
    outSlider:SetValueStep(0.1)
    outSlider:SetScript("OnValueChanged", function()
        FeidDB.fadeOutDuration = this:GetValue()
    end)

    -- Column 2: Checkboxes
    -- Enable Checkbox
    local enableCheck = CreateFrame("CheckButton", "FeidEnableCheck", f, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 175, -45)
    enableCheck:SetScale(0.9)
    getglobal(enableCheck:GetName() .. "Text"):SetText("Enabled")
    enableCheck:SetScript("OnClick", function()
        FeidDB.enabled = this:GetChecked() and true or false
    end)

    -- Disable in Zone Checkboxes
    local partyCheck = CreateFrame("CheckButton", "FeidPartyCheck", f, "UICheckButtonTemplate")
    partyCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 5)
    partyCheck:SetScale(0.8)
    getglobal(partyCheck:GetName() .. "Text"):SetText("Disable in party")
    partyCheck:SetScript("OnClick", function()
        FeidDB.disableInParty = this:GetChecked() and true or false
    end)

    local raidCheck = CreateFrame("CheckButton", "FeidRaidCheck", f, "UICheckButtonTemplate")
    raidCheck:SetPoint("TOPLEFT", partyCheck, "BOTTOMLEFT", 0, 5)
    raidCheck:SetScale(0.8)
    getglobal(raidCheck:GetName() .. "Text"):SetText("Disable in raids")
    raidCheck:SetScript("OnClick", function()
        FeidDB.disableInRaids = this:GetChecked() and true or false
    end)

    local bgCheck = CreateFrame("CheckButton", "FeidBGCheck", f, "UICheckButtonTemplate")
    bgCheck:SetPoint("TOPLEFT", raidCheck, "BOTTOMLEFT", 0, 5)
    bgCheck:SetScale(0.8)
    getglobal(bgCheck:GetName() .. "Text"):SetText("Disable in BGs")
    bgCheck:SetScript("OnClick", function()
        FeidDB.disableInBGs = this:GetChecked() and true or false
    end)

    local fullCheck = CreateFrame("CheckButton", "FeidFullCheck", f, "UICheckButtonTemplate")
    fullCheck:SetPoint("TOPLEFT", bgCheck, "BOTTOMLEFT", 0, 5)
    fullCheck:SetScale(0.8)
    getglobal(fullCheck:GetName() .. "Text"):SetText("Only fade when HP/Mana full")
    fullCheck:SetScript("OnClick", function()
        FeidDB.fullHPManaOnly = this:GetChecked() and true or false
    end)

    -- Vertical Separator 2 (between Settings and Frame List)
    local vline2 = f:CreateTexture(nil, "ARTWORK")
    vline2:SetTexture(0.5, 0.5, 0.5, 0.5)
    vline2:SetWidth(1)
    vline2:SetPoint("TOPLEFT", f, "TOPLEFT", 300, -40)
    vline2:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 300, 40)

    -- Popup for Individual Frame Configuration
    local function CreateFrameConfigPopup()
        local p = CreateFrame("Frame", "FeidFrameConfigPopup", UIParent)
        p:SetWidth(250)
        p:SetHeight(420)
        p:SetPoint("CENTER", UIParent, "CENTER")
        p:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 }
        })
        p:EnableMouse(true)
        p:SetMovable(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", function() this:StartMoving() end)
        p:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        p:SetFrameStrata("DIALOG")
        p:Hide()

        local ptitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ptitle:SetPoint("TOP", p, "TOP", 0, -15)
        ptitle:SetText("Frame Settings")

        -- Frame Name EditBox
        local pNameEdit = CreateFrame("EditBox", "FeidPopupNameEdit", p, "InputBoxTemplate")
        pNameEdit:SetWidth(180)
        pNameEdit:SetHeight(20)
        pNameEdit:SetPoint("TOP", p, "TOP", 0, -50)
        pNameEdit:SetAutoFocus(false)
        local pNameLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pNameLabel:SetPoint("BOTTOMLEFT", pNameEdit, "TOPLEFT", 0, 5)
        pNameLabel:SetText("Frame name")

        -- Use Default Checkbox
        local pDefaultCheck = CreateFrame("CheckButton", "FeidPopupDefaultCheck", p, "UICheckButtonTemplate")
        pDefaultCheck:SetPoint("TOPLEFT", pNameEdit, "BOTTOMLEFT", -5, -15)
        getglobal(pDefaultCheck:GetName() .. "Text"):SetText("Use Default")

        -- Individual Sliders
        local function CreatePopupSlider(name, label, min, max, step, yOffset)
            local s = CreateFrame("Slider", "FeidPopup" .. name .. "Slider", p, "OptionsSliderTemplate")
            s:SetPoint("TOPLEFT", pDefaultCheck, "BOTTOMLEFT", 5, yOffset)
            s:SetWidth(180)
            getglobal(s:GetName() .. "Text"):SetText(label)
            s:SetMinMaxValues(min, max)
            s:SetValueStep(step)
            return s
        end

        local pMinSlider = CreatePopupSlider("Min", "Min Opacity", 0, 1, 0.05, -30)
        local pMaxSlider = CreatePopupSlider("Max", "Max Opacity", 0, 1, 0.05, -70)
        local pInSlider = CreatePopupSlider("In", "Fade In Time", 0, 2, 0.1, -110)
        local pOutSlider = CreatePopupSlider("Out", "Fade Out Time", 0, 2, 0.1, -150)

        -- Invert Checkbox
        local pInvertCheck = CreateFrame("CheckButton", "FeidPopupInvertCheck", p, "UICheckButtonTemplate")
        pInvertCheck:SetPoint("TOPLEFT", pOutSlider, "BOTTOMLEFT", -5, -15)
        getglobal(pInvertCheck:GetName() .. "Text"):SetText("Invert")

        -- Full HP/Mana Checkbox
        local pFullCheck = CreateFrame("CheckButton", "FeidPopupFullCheck", p, "UICheckButtonTemplate")
        pFullCheck:SetPoint("TOPLEFT", pInvertCheck, "BOTTOMLEFT", 0, 5)
        getglobal(pFullCheck:GetName() .. "Text"):SetText("Only fade when HP/Mana full")

        local sliders = {pMinSlider, pMaxSlider, pInSlider, pOutSlider, pInvertCheck, pFullCheck}
        local function UpdatePopupState()
            local enabled = not pDefaultCheck:GetChecked()
            for _, s in ipairs(sliders) do
                if enabled then
                    if s.Enable then s:Enable() end
                    local txt = getglobal(s:GetName() .. "Text")
                    if txt then txt:SetTextColor(1, 0.82, 0) end
                    if s.SetAlpha then s:SetAlpha(1.0) end
                else
                    if s.Disable then s:Disable() end
                    local txt = getglobal(s:GetName() .. "Text")
                    if txt then txt:SetTextColor(0.5, 0.5, 0.5) end
                    if s.SetAlpha then s:SetAlpha(0.5) end
                end
            end
        end
        pDefaultCheck:SetScript("OnClick", UpdatePopupState)

        -- Apply/Cancel Buttons
        local apply = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        apply:SetWidth(80)
        apply:SetHeight(22)
        apply:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 25, 20)
        apply:SetText("Apply")

        local cancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        cancel:SetWidth(80)
        cancel:SetHeight(22)
        cancel:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -25, 20)
        cancel:SetText("Cancel")
        cancel:SetScript("OnClick", function() p:Hide() end)

        apply:SetScript("OnClick", function()
            local oldName = p.oldName
            local newName = pNameEdit:GetText()
            if not newName or newName == "" then return end

            local cfg = {
                useDefault = pDefaultCheck:GetChecked() and true or false,
                minAlpha = pMinSlider:GetValue(),
                maxAlpha = pMaxSlider:GetValue(),
                fadeInDuration = pInSlider:GetValue(),
                fadeOutDuration = pOutSlider:GetValue(),
                invert = pInvertCheck:GetChecked() and true or false,
                fullHPManaOnly = pFullCheck:GetChecked() and true or false
            }

            if oldName ~= newName then
                FeidDB.frames[oldName] = nil
            end
            FeidDB.frames[newName] = cfg
            
            ResolveFrames()
            Feid_UpdateScrollChild()
            p:Hide()
        end)

        p.Open = function(self, name)
            local cfg = FeidDB.frames[name]
            if type(cfg) ~= "table" then
                cfg = { useDefault = true, minAlpha = FeidDB.minAlpha, maxAlpha = FeidDB.maxAlpha, fadeInDuration = FeidDB.fadeInDuration, fadeOutDuration = FeidDB.fadeOutDuration, invert = false, fullHPManaOnly = false }
            end
            self.oldName = name
            pNameEdit:SetText(name)
            pDefaultCheck:SetChecked(cfg.useDefault)
            pMinSlider:SetValue(cfg.minAlpha or FeidDB.minAlpha)
            pMaxSlider:SetValue(cfg.maxAlpha or FeidDB.maxAlpha)
            pInSlider:SetValue(cfg.fadeInDuration or FeidDB.fadeInDuration)
            pOutSlider:SetValue(cfg.fadeOutDuration or FeidDB.fadeOutDuration)
            pInvertCheck:SetChecked(cfg.invert)
            pFullCheck:SetChecked(cfg.fullHPManaOnly)

            -- Trigger the visual update for disabled states
            UpdatePopupState()
            self:Show()
        end

        return p
    end
    local popup = CreateFrameConfigPopup()

    -- Column 3: Frame Management
    -- Frame Name Input
    local editBox = CreateFrame("EditBox", "FeidEditBox", f, "InputBoxTemplate")
    editBox:SetWidth(180)
    editBox:SetHeight(20)
    editBox:SetPoint("TOPLEFT", f, "TOPLEFT", 320, -50)
    editBox:SetAutoFocus(false)

    local editBoxLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editBoxLabel:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, 5)
    editBoxLabel:SetText("Frame name")

    -- Add Button
    local addButton = CreateFrame("Button", "FeidAddButton", f, "UIPanelButtonTemplate")
    addButton:SetWidth(60)
    addButton:SetHeight(20)
    addButton:SetPoint("LEFT", editBox, "RIGHT", 10, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", function()
        local name = editBox:GetText()
        if name and name ~= "" then
            FeidDB.frames[name] = { useDefault = true }
            editBox:SetText("")
            ResolveFrames()
            -- After resolving, ensure new frames start at current global state
            local combat = UnitAffectingCombat("player")
            local target = combat and FeidDB.maxAlpha or FeidDB.minAlpha
            for _, info in ipairs(resolvedFrames) do
                info.frame:SetAlpha(target)
                info.currentAlpha = target
                info.targetAlpha = target
            end
            Feid_UpdateScrollChild()
        end
    end)

    -- Identify Button
    local idButton = CreateFrame("Button", "FeidIdButton", f, "UIPanelButtonTemplate")
    idButton:SetWidth(100)
    idButton:SetHeight(20)
    idButton:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -10)
    idButton:SetText("Identify")
    idButton:SetScript("OnClick", function()
        isIdentifying = true
        FeidIdentifyOverlay.step = 0
        FeidIdentifyOverlay:Show()
        -- Add a visual cue that we are in identify mode
        FeidIdentifyOverlay:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"})
        FeidIdentifyOverlay:SetBackdropColor(1, 1, 1, 0.2)
        DEFAULT_CHAT_FRAME:AddMessage("Feid: Click a frame to identify it.")
    end)

    -- ScrollFrame for List
    local sf = CreateFrame("ScrollFrame", "FeidScrollFrame", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", idButton, "BOTTOMLEFT", 0, -15)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -35, 30)

    local content = CreateFrame("Frame", "FeidScrollChild", sf)
    content:SetWidth(230)
    content:SetHeight(1)
    sf:SetScrollChild(content)

    function Feid_UpdateScrollChild()
        local i = 0
        local child = FeidScrollChild

        -- Recycled frame management
        if not child.rows then child.rows = {} end
        for _, row in ipairs(child.rows) do row:Hide() end

        -- Get sorted keys for consistent display
        local sortedNames = {}
        for name, _ in pairs(FeidDB.frames) do
            table.insert(sortedNames, name)
        end
        table.sort(sortedNames)

        for _, name in ipairs(sortedNames) do
            i = i + 1
            local row = child.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row:SetWidth(230)
                row:SetHeight(20)
                
                local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                txt:SetPoint("LEFT", row, "LEFT", 5, 0)
                row.txt = txt

                local rem = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                rem:SetWidth(40)
                rem:SetHeight(18)
                rem:SetPoint("RIGHT", row, "RIGHT", -5, 0)
                rem:SetText("Del")
                row.rem = rem

                local cog = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                cog:SetWidth(40)
                cog:SetHeight(18)
                cog:SetPoint("RIGHT", rem, "LEFT", -5, 0)
                cog:SetText("Edit")
                
                row.cog = cog

                child.rows[i] = row
            end

            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i-1)*20)
            row.txt:SetText(name)
            
            -- Re-bind the click handler with the current 'name'
            local currentName = name
            row.rem:SetScript("OnClick", function()
                -- Restore alpha to 100% before removing
                local frames = GetFramesByPattern(currentName)
                if frames then
                    for _, frame in ipairs(frames) do
                        frame:SetAlpha(1.0)
                    end
                end
                
                FeidDB.frames[currentName] = nil
                ResolveFrames()
                Feid_UpdateScrollChild()
            end)

            row.cog:SetScript("OnClick", function()
                popup:Open(currentName)
            end)
            
            row:Show()
        end
        content:SetHeight(math.max(1, i * 20))
    end

    f:SetScript("OnShow", function()
        enableCheck:SetChecked(FeidDB.enabled)
        minSlider:SetValue(FeidDB.minAlpha)
        maxSlider:SetValue(FeidDB.maxAlpha)
        inSlider:SetValue(FeidDB.fadeInDuration)
        outSlider:SetValue(FeidDB.fadeOutDuration)
        partyCheck:SetChecked(FeidDB.disableInParty)
        raidCheck:SetChecked(FeidDB.disableInRaids)
        bgCheck:SetChecked(FeidDB.disableInBGs)
        fullCheck:SetChecked(FeidDB.fullHPManaOnly)
        Feid_UpdateScrollChild()
    end)

    -- Close Button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    return f
end

-- Slash Command
SLASH_FEID1 = "/feid"
SlashCmdList["FEID"] = function()
    if not FeidConfigFrame then CreateConfigWindow() end
    if FeidConfigFrame:IsShown() then
        FeidConfigFrame:Hide()
    else
        FeidConfigFrame:Show()
    end
end

-- Identify Logic
local overlay = CreateFrame("Button", "FeidIdentifyOverlay", UIParent)
overlay:SetAllPoints(UIParent)
overlay:SetFrameStrata("TOOLTIP")
overlay:Hide()
overlay:RegisterForClicks("LeftButtonDown", "RightButtonDown")

overlay.step = 0
overlay:SetScript("OnClick", function()
    this.step = 1
end)

local throttleTimer = 0
local STATE_THROTTLE = 0.1 -- Update state 10 times per second

-- Move the identification update logic to the main fader to ensure it keeps running
-- even when the overlay is hidden.
fader:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0
    -- Identify Logic
    if isIdentifying and FeidIdentifyOverlay.step > 0 then
        if FeidIdentifyOverlay.step == 1 then
            -- Frame 1: Hide the overlay
            FeidIdentifyOverlay:Hide()
            FeidIdentifyOverlay.step = 2
        elseif FeidIdentifyOverlay.step == 2 then
            -- Frame 2: The overlay is definitely gone, check focus
            local frame = GetMouseFocus()
            if frame and frame ~= WorldFrame and frame:GetName() then
                FeidEditBox:SetText(frame:GetName())
                DEFAULT_CHAT_FRAME:AddMessage("Feid: Identified " .. frame:GetName())
            elseif frame == WorldFrame then
                DEFAULT_CHAT_FRAME:AddMessage("Feid: Clicked the world, no frame identified.")
            else
                DEFAULT_CHAT_FRAME:AddMessage("Feid: Could not identify frame (it might be anonymous).")
            end
            isIdentifying = false
            FeidIdentifyOverlay.step = 0
        end
    end

    -- Smooth Fading Logic for individual frames
    if not FeidDB or not FeidDB.enabled or IsDisabledInZone() then
        -- If disabled, ensure everything is at 100%
        for _, info in ipairs(resolvedFrames) do
            if info.currentAlpha ~= 1.0 then
                info.currentAlpha = 1.0
                info.frame:SetAlpha(1.0)
            end
        end
        return
    end

    local combat, casting, notFull
    throttleTimer = throttleTimer + elapsed
    local updateStates = false
    if throttleTimer >= STATE_THROTTLE then
        updateStates = true
        throttleTimer = 0
        combat = UnitAffectingCombat("player")
        casting = isCasting or isChanneling
        notFull = (UnitHealth("player") < UnitHealthMax("player")) or (UnitMana("player") < UnitManaMax("player"))
    end

    for _, info in ipairs(resolvedFrames) do
        if updateStates then
            local cfg = info.config
            local minAlpha, maxAlpha, invert, fullHPManaOnly
            
            if cfg and not cfg.useDefault then
                minAlpha = cfg.minAlpha or FeidDB.minAlpha
                maxAlpha = cfg.maxAlpha or FeidDB.maxAlpha
                invert = cfg.invert
                fullHPManaOnly = cfg.fullHPManaOnly
            else
                minAlpha = FeidDB.minAlpha
                maxAlpha = FeidDB.maxAlpha
                invert = false
                fullHPManaOnly = FeidDB.fullHPManaOnly
            end

            -- Determine target alpha for this specific frame
            local mouseOver = IsMouseOverFrame(info.frame)
            local isTriggered = combat or casting or mouseOver or (fullHPManaOnly and notFull)
            if invert then
                isTriggered = not isTriggered
            end

            if mouseOver then
                info.targetAlpha = 1.0
            elseif isTriggered then
                info.targetAlpha = maxAlpha
            else
                info.targetAlpha = minAlpha
            end
        end

        -- Update current alpha
        if info.currentAlpha ~= info.targetAlpha then
            local cfg = info.config
            local fadeInSpeed, fadeOutSpeed
            if cfg and not cfg.useDefault then
                fadeInSpeed = cfg.fadeInDuration or FeidDB.fadeInDuration
                fadeOutSpeed = cfg.fadeOutDuration or FeidDB.fadeOutDuration
            else
                fadeInSpeed = FeidDB.fadeInDuration
                fadeOutSpeed = FeidDB.fadeOutDuration
            end

            local speed = (info.currentAlpha < info.targetAlpha) and fadeInSpeed or fadeOutSpeed
            local step = elapsed / (speed > 0 and speed or 0.01)
            
            if info.currentAlpha < info.targetAlpha then
                info.currentAlpha = math.min(info.targetAlpha, info.currentAlpha + step)
            else
                info.currentAlpha = math.max(info.targetAlpha, info.currentAlpha - step)
            end
            info.frame:SetAlpha(info.currentAlpha)
        end
    end
end)
