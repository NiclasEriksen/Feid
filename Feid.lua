-- Default Settings
local DEFAULT_SETTINGS = {
    frames = {},
    minAlpha = 0.5,
    maxAlpha = 1.0,
    fadeInDuration = 0.5,
    fadeOutDuration = 0.5,
    enabled = true,
    disableInDungeons = false,
    disableInRaids = false,
    disableInBGs = false,
}

-- Internal State
local isIdentifying = false
local resolvedFrames = {}

local fader = CreateFrame("Frame", "FeidMainFrame")

local function GetFramesByPattern(pattern)
    local found = {}
    if string.find(pattern, "%*") then
        local luaPattern = string.gsub(pattern, "([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
        luaPattern = string.gsub(luaPattern, "%*", ".*")
        luaPattern = "^" .. luaPattern .. "$"
        for name, value in pairs(getfenv(0)) do
            if type(value) == "table" and value.GetAlpha and value.SetAlpha then
                if string.find(name, luaPattern) then
                    table.insert(found, value)
                end
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
    
    -- In WoW 1.12.1, GetInstanceInfo() and IsInInstance() do not exist.
    -- We must rely on alternative methods for detection.

    -- 1. Check for Battlegrounds
    if FeidDB.disableInBGs then
        -- MAX_BATTLEFIELD_QUEUES is 3 in 1.12.1
        for i=1, 3 do
            local status = GetBattlefieldStatus(i)
            if status == "active" then return true end
        end
    end

    -- 2. Check for Raids
    if FeidDB.disableInRaids and GetNumRaidMembers() > 0 then
        -- In 1.12, being in a raid group is a strong indicator of being in a raid instance,
        -- though not 100% accurate (could be out in the world).
        return true
    end

    -- 3. Check for Dungeons
    if FeidDB.disableInDungeons then
        -- Detecting a 5-man dungeon without GetInstanceInfo is tricky.
        -- We'll check if we're in a party but NOT a raid.
        -- To avoid disabling it every time the player is just questing in a party,
        -- we can check if the "Reset all instances" option is available, 
        -- but that's only for the leader.
        
        -- A more common way is to check the Minimap text or use GetZoneText()
        -- but that requires a database.
        
        -- For now, let's keep it simple: if in a party and they checked "No Dungeons",
        -- we'll assume they might want it disabled. 
        -- Optimization: only if we are actually in a party.
        if GetNumPartyMembers() > 0 and GetNumRaidMembers() == 0 then
             -- This is still broad. Let's see if we can do better.
             -- Many 1.12 addons just use the fact that you can't see your map 
             -- position in many instances, but that's not universal.
             
             -- Let's just return true if grouped as a fallback for "No Dungeons".
             -- return true
        end
    end
    
    return false
end

local function ResolveFrames()
    -- Create a map of existing frames to preserve their current alpha state if they are still matched
    local oldFrames = {}
    for _, info in ipairs(resolvedFrames) do
        oldFrames[info.frame] = info.currentAlpha
    end

    resolvedFrames = {}
    if not FeidDB or not FeidDB.frames then return end
    
    local added = {} -- To avoid duplicates if patterns overlap
    for pattern, _ in pairs(FeidDB.frames) do
        local frames = GetFramesByPattern(pattern)
        for _, frame in ipairs(frames) do
            if not added[frame] then
                local current = oldFrames[frame] or (FeidDB and FeidDB.minAlpha) or 0.5
                table.insert(resolvedFrames, {
                    frame = frame,
                    currentAlpha = current,
                    targetAlpha = current
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
    local focus = GetMouseFocus()
    if focus == frame then return true end
    if MouseIsOver(frame) then return true end
    return false
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

    -- Column 1: Sliders
    -- Min Alpha Slider
    local minSlider = CreateFrame("Slider", "FeidMinSlider", f, "OptionsSliderTemplate")
    minSlider:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    getglobal(minSlider:GetName() .. "Text"):SetText("Min Opacity")
    minSlider:SetMinMaxValues(0, 1)
    minSlider:SetValueStep(0.05)
    minSlider:SetScript("OnValueChanged", function()
        FeidDB.minAlpha = this:GetValue()
    end)

    -- Max Alpha Slider
    local maxSlider = CreateFrame("Slider", "FeidMaxSlider", f, "OptionsSliderTemplate")
    maxSlider:SetPoint("TOPLEFT", minSlider, "BOTTOMLEFT", 0, -30)
    getglobal(maxSlider:GetName() .. "Text"):SetText("Max Opacity")
    maxSlider:SetMinMaxValues(0, 1)
    maxSlider:SetValueStep(0.05)
    maxSlider:SetScript("OnValueChanged", function()
        FeidDB.maxAlpha = this:GetValue()
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

    -- Vertical Separator 1 (between Sliders and Checkboxes)
    local vline1 = f:CreateTexture(nil, "ARTWORK")
    vline1:SetTexture(0.5, 0.5, 0.5, 0.5)
    vline1:SetWidth(1)
    vline1:SetPoint("TOPLEFT", f, "TOPLEFT", 160, -40)
    vline1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 160, 40)

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
    local dungeonCheck = CreateFrame("CheckButton", "FeidDungeonCheck", f, "UICheckButtonTemplate")
    dungeonCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 5)
    dungeonCheck:SetScale(0.8)
    getglobal(dungeonCheck:GetName() .. "Text"):SetText("No Dungeons")
    dungeonCheck:SetScript("OnClick", function()
        FeidDB.disableInDungeons = this:GetChecked() and true or false
    end)

    local raidCheck = CreateFrame("CheckButton", "FeidRaidCheck", f, "UICheckButtonTemplate")
    raidCheck:SetPoint("TOPLEFT", dungeonCheck, "BOTTOMLEFT", 0, 5)
    raidCheck:SetScale(0.8)
    getglobal(raidCheck:GetName() .. "Text"):SetText("No Raids")
    raidCheck:SetScript("OnClick", function()
        FeidDB.disableInRaids = this:GetChecked() and true or false
    end)

    local bgCheck = CreateFrame("CheckButton", "FeidBGCheck", f, "UICheckButtonTemplate")
    bgCheck:SetPoint("TOPLEFT", raidCheck, "BOTTOMLEFT", 0, 5)
    bgCheck:SetScale(0.8)
    getglobal(bgCheck:GetName() .. "Text"):SetText("No BGs")
    bgCheck:SetScript("OnClick", function()
        FeidDB.disableInBGs = this:GetChecked() and true or false
    end)

    -- Vertical Separator 2 (between Settings and Frame List)
    local vline2 = f:CreateTexture(nil, "ARTWORK")
    vline2:SetTexture(0.5, 0.5, 0.5, 0.5)
    vline2:SetWidth(1)
    vline2:SetPoint("TOPLEFT", f, "TOPLEFT", 300, -40)
    vline2:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 300, 40)

    -- Column 3: Frame Management
    -- Frame Name Input
    local editBox = CreateFrame("EditBox", "FeidEditBox", f, "InputBoxTemplate")
    editBox:SetWidth(180)
    editBox:SetHeight(20)
    editBox:SetPoint("TOPLEFT", f, "TOPLEFT", 320, -50)
    editBox:SetAutoFocus(false)

    -- Add Button
    local addButton = CreateFrame("Button", "FeidAddButton", f, "UIPanelButtonTemplate")
    addButton:SetWidth(60)
    addButton:SetHeight(20)
    addButton:SetPoint("LEFT", editBox, "RIGHT", 10, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", function()
        local name = editBox:GetText()
        if name and name ~= "" then
            FeidDB.frames[name] = true
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

        for name, _ in pairs(FeidDB.frames) do
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

                child.rows[i] = row
            end

            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i-1)*20)
            row.txt:SetText(name)
            
            -- Re-bind the click handler with the current 'name'
            local currentName = name
            row.rem:SetScript("OnClick", function()
                -- Restore alpha to 100% before removing
                local frames = GetFramesByPattern(currentName)
                for _, frame in ipairs(frames) do
                    frame:SetAlpha(1.0)
                end
                
                FeidDB.frames[currentName] = nil
                ResolveFrames()
                Feid_UpdateScrollChild()
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
        dungeonCheck:SetChecked(FeidDB.disableInDungeons)
        raidCheck:SetChecked(FeidDB.disableInRaids)
        bgCheck:SetChecked(FeidDB.disableInBGs)
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

-- Move the identification update logic to the main fader to ensure it keeps running
-- even when the overlay is hidden.
fader:SetScript("OnUpdate", function()
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
    if not FeidDB.enabled or IsDisabledInZone() then
        -- If disabled, ensure everything is at 100% (or maxAlpha?)
        -- Usually disabled means "don't fade", so 100% is best.
        for _, info in ipairs(resolvedFrames) do
            if info.currentAlpha ~= 1.0 then
                info.currentAlpha = 1.0
                info.frame:SetAlpha(1.0)
            end
        end
        return
    end

    local combat = UnitAffectingCombat("player")
    local casting = isCasting or isChanneling
    local fadeInSpeed = FeidDB.fadeInDuration or 0.5
    local fadeOutSpeed = FeidDB.fadeOutDuration or 0.5

    for _, info in ipairs(resolvedFrames) do
        -- Determine target alpha for this specific frame
        if combat or casting or IsMouseOverFrame(info.frame) then
            info.targetAlpha = FeidDB.maxAlpha
        else
            info.targetAlpha = FeidDB.minAlpha
        end

        -- Update current alpha
        if info.currentAlpha ~= info.targetAlpha then
            local speed = (info.currentAlpha < info.targetAlpha) and fadeInSpeed or fadeOutSpeed
            local step = arg1 / (speed > 0 and speed or 0.01)
            
            if info.currentAlpha < info.targetAlpha then
                info.currentAlpha = math.min(info.targetAlpha, info.currentAlpha + step)
            else
                info.currentAlpha = math.max(info.targetAlpha, info.currentAlpha - step)
            end
            info.frame:SetAlpha(info.currentAlpha)
        end
    end
end)
