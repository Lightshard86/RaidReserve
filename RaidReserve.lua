-- Initialize global storage
RaidReserve_Data = RaidReserve_Data or { 
    reserves = {}, 
    pos = {"CENTER", 0, 0}, 
    selectedChannel = "RAID",
    width = 350,
    height = 400,
    hideBtn = false
}

local prefix = "RAIDRES"
local requests = {} 
local rows = {}
local syncQueue = {} 
local tempReserves = {} 
local addonUsers = {} -- Local table to track players using the addon

-- 1. MAIN WINDOW
local frame = CreateFrame("Frame", "RaidReserveFrame", UIParent)
frame:SetWidth(RaidReserve_Data.width or 350)
frame:SetHeight(RaidReserve_Data.height or 400)
frame:SetPoint("CENTER", 0, 0)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:EnableMouse(true); frame:SetMovable(true); frame:SetResizable(true)
frame:SetMinResize(320, 380); frame:SetMaxResize(600, 850)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() frame:StartMoving() end)
frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

-- Open Logic: Reset users and ping when opening
frame:SetScript("OnShow", function()
    addonUsers = {}
    addonUsers[UnitName("player")] = true
    SendComm("PING")
    UpdateUI()
end)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -15); title:SetText("Raid Reserve List")

-- 1b. ADDON USER TRACKER (Top Right)
local userCount = CreateFrame("Button", "RR_UserTracker", frame)
userCount:SetWidth(60); userCount:SetHeight(20)
userCount:SetPoint("TOPRIGHT", -10, -15)
userCount.text = userCount:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
userCount.text:SetAllPoints()
userCount.text:SetJustifyH("RIGHT")

userCount:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Addon Users:", 1, 1, 1)
    for name in pairs(addonUsers) do
        GameTooltip:AddLine("- " .. name, 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end)
userCount:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- 1a. RESIZE GRIP
local resizeGrip = CreateFrame("Button", nil, frame)
resizeGrip:SetWidth(20); resizeGrip:SetHeight(20); resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
resizeGrip:SetFrameStrata("HIGH"); resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 20)
local gripTex = resizeGrip:CreateTexture(nil, "OVERLAY")
gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
gripTex:SetAllPoints(resizeGrip)
resizeGrip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
resizeGrip:SetScript("OnMouseUp", function() 
    frame:StopMovingOrSizing() 
    RaidReserve_Data.width = frame:GetWidth(); RaidReserve_Data.height = frame:GetHeight()
end)

-- 2. DYNAMIC ROW SYSTEM
local function CreateRow(id)
    local f = CreateFrame("Button", "RR_Row"..id, frame)
    f:SetHeight(18); f:SetPoint("TOPLEFT", 15, -40 - (id * 20)); f:SetPoint("RIGHT", -15, 0)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", 5, 0)
    f:SetScript("OnEnter", function()
        if f.link then
            local _, _, rawLink = string.find(f.link, "|H(item:[%-?%d:]+)|h")
            if rawLink then GameTooltip:SetOwner(this, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(rawLink); GameTooltip:Show() end
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function()
        if not (IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)) then return end
        if f.isRequest then
            local safeLink = string.gsub(f.link, "|", "*")
            if arg1 == "LeftButton" then
                RaidReserve_Data.reserves[f.link] = f.player; requests[f.link] = nil
                SendComm("NOTIF:ACC#!#" .. safeLink .. "#!#" .. f.player)
            else SendComm("NOTIF:DNY#!#" .. safeLink .. "#!#" .. f.player); requests[f.link] = nil end
        else
            if arg1 == "RightButton" and f.link then RaidReserve_Data.reserves[f.link] = nil end
        end
        UpdateUI()
    end)
    f:Hide()
    return f
end
for i=1, 30 do rows[i] = CreateRow(i) end

-- UI ELEMENTS
local recruitEB = CreateFrame("EditBox", "RR_RecruitEB", frame, "InputBoxTemplate")
recruitEB:SetWidth(150); recruitEB:SetHeight(20); recruitEB:SetPoint("BOTTOMLEFT", 20, 80)
recruitEB:SetAutoFocus(false); recruitEB:SetText("")

local dropdown = CreateFrame("Frame", "RR_ChannelDropdown", frame, "UIDropDownMenuTemplate")
dropdown:SetPoint("BOTTOMLEFT", -10, 40)

local hideCB = CreateFrame("CheckButton", "RR_HideCheck", frame, "UICheckButtonTemplate")
hideCB:SetPoint("BOTTOMLEFT", 175, 75)
getglobal(hideCB:GetName().."Text"):SetText("Hide Icon")
hideCB:SetScript("OnClick", function()
    RaidReserve_Data.hideBtn = (this:GetChecked() == 1)
    if RaidReserve_Data.hideBtn then RR_MinimapButton:Hide() else RR_MinimapButton:Show() end
end)

function UpdateUI()
    for i=1, 30 do rows[i]:Hide() end
    local count = 0
    for itemLink, player in pairs(RaidReserve_Data.reserves) do
        count = count + 1
        if rows[count] then
            local row = rows[count]
            row.link = itemLink; row.player = player; row.isRequest = false
            row.text:SetText(itemLink .. "  ->  |cff00ff00" .. player .. "|r"); row:Show()
        end
    end
    local isLead = IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)
    if isLead then pushBtn:Enable(); announceBtn:Enable(); recruitEB:Show(); dropdown:Show(); hideCB:Show()
    else pushBtn:Disable(); announceBtn:Disable(); recruitEB:Hide(); dropdown:Hide(); hideCB:Hide() end
    
    -- Update User Count
    local totalUsers = 0
    for _ in pairs(addonUsers) do totalUsers = totalUsers + 1 end
    userCount.text:SetText("Users: " .. totalUsers)

    hideCB:SetChecked(RaidReserve_Data.hideBtn)
    UIDropDownMenu_SetSelectedValue(dropdown, RaidReserve_Data.selectedChannel or "RAID")
    if isLead then
        for itemLink, player in pairs(requests) do
            count = count + 1
            if rows[count] then
                local row = rows[count]
                row.link = itemLink; row.player = player; row.isRequest = true
                row.text:SetText("|cffffff00[REQ]|r " .. itemLink .. "  ->  " .. player); row:Show()
            end
        end
    end
    if count == 0 then rows[1].text:SetText("No reserves active."); rows[1].link = nil; rows[1]:Show() end
end

-- 3. COMMUNICATION & ANNOUNCE
function SendComm(msg)
    local chan = (GetNumRaidMembers() > 0 and "RAID") or (GetNumPartyMembers() > 0 and "PARTY") or nil
    if chan then SendAddonMessage(prefix, msg, chan) end
end

function AnnounceCustom()
    local val = RaidReserve_Data.selectedChannel or "RAID"
    local chan = (tonumber(val) and "CHANNEL") or val
    local num = tonumber(val)
    local intro = recruitEB:GetText()
    if intro and intro ~= "" then SendChatMessage(intro, chan, nil, num) end
    SendChatMessage("--- Reserved Items: ---", chan, nil, num)
    local currentLine = ""
    for link in pairs(RaidReserve_Data.reserves) do
        if string.len(currentLine .. "  " .. link) > 200 then
            SendChatMessage(currentLine, chan, nil, num); currentLine = link
        else currentLine = (currentLine == "" and link) or (currentLine .. "  " .. link) end
    end
    if currentLine ~= "" then SendChatMessage(currentLine, chan, nil, num) end
end

local syncTimer = 0
frame:SetScript("OnUpdate", function()
    if table.getn(syncQueue) > 0 then
        syncTimer = syncTimer + (arg1 or 0.1)
        if syncTimer > 0.4 then 
            local msg = table.remove(syncQueue, 1)
            if msg then 
                SendComm(msg) 
                if string.sub(msg, 1, 4) == "ADD:" then DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaRR: Syncing...|r")
                elseif msg == "END" then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR: Push Complete!|r") end
            end
            syncTimer = 0
        end
    end
end)

function PushListToRaid()
    if not (IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)) then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR:|r Syncing list to group...")
    syncQueue = {}
    table.insert(syncQueue, "START")
    for link, player in pairs(RaidReserve_Data.reserves) do
        table.insert(syncQueue, "ADD:" .. string.gsub(link, "|", "*") .. ":" .. player)
    end
    table.insert(syncQueue, "END")
end

-- 4. BUTTONS
pushBtn = CreateFrame("Button", "RR_PushBtn", frame, "UIPanelButtonTemplate")
pushBtn:SetWidth(110); pushBtn:SetHeight(25); pushBtn:SetPoint("BOTTOMLEFT", 45, 15)
pushBtn:SetText("Push to Raid")
pushBtn:SetScript("OnClick", function() PushListToRaid() end)

announceBtn = CreateFrame("Button", "RR_AnnounceBtn", frame, "UIPanelButtonTemplate")
announceBtn:SetWidth(110); announceBtn:SetHeight(25); announceBtn:SetPoint("BOTTOMRIGHT", -45, 15)
announceBtn:SetText("Announce")
announceBtn:SetScript("OnClick", function() AnnounceCustom() end)

-- 5. DROPDOWN
local function Dropdown_OnClick()
    UIDropDownMenu_SetSelectedID(RR_ChannelDropdown, this:GetID())
    RaidReserve_Data.selectedChannel = this.value
end
local function Dropdown_Initialize()
    local info = {}
    local channels = {
        { text = "Say", value = "SAY" }, { text = "Party", value = "PARTY" }, { text = "Raid", value = "RAID" },
        { text = "Guild", value = "GUILD" }, { text = "/1", value = "1" }, { text = "/2", value = "2" }, 
        { text = "/3", value = "3" }, { text = "/4", value = "4" },
    }
    for i, entry in pairs(channels) do
        info.text = entry.text; info.value = entry.value; info.func = Dropdown_OnClick
        info.checked = (RaidReserve_Data.selectedChannel == entry.value)
        UIDropDownMenu_AddButton(info)
    end
end
UIDropDownMenu_Initialize(dropdown, Dropdown_Initialize)
UIDropDownMenu_SetWidth(140, dropdown)

-- 6. EVENT HANDLER
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(prefix) end
        if RaidReserve_Data.hideBtn then RR_MinimapButton:Hide() end
        frame:SetWidth(RaidReserve_Data.width or 350); frame:SetHeight(RaidReserve_Data.height or 400)
        UpdateUI()
    elseif event == "RAID_ROSTER_UPDATE" then UpdateUI()
    elseif event == "CHAT_MSG_ADDON" and arg1 == prefix then
        local msg = arg2; local sender = arg4
        if sender == UnitName("player") then return end
        
        -- Addon User Detection
        if msg == "PING" then SendComm("PONG")
        elseif msg == "PONG" then addonUsers[sender] = true; UpdateUI()
        
        elseif msg == "START" then tempReserves = {}
        elseif string.sub(msg, 1, 4) == "ADD:" then
            local lastColon = 0
            for i = string.len(msg), 5, -1 do if string.sub(msg, i, i) == ":" then lastColon = i; break end end
            if lastColon > 4 then
                local encodedLink = string.sub(msg, 5, lastColon - 1)
                tempReserves[string.gsub(encodedLink, "*", "|")] = string.sub(msg, lastColon + 1)
            end
        elseif msg == "END" then
            RaidReserve_Data.reserves = {}
            for k, v in pairs(tempReserves) do RaidReserve_Data.reserves[k] = v end
            UpdateUI()
        elseif string.sub(msg, 1, 4) == "REQ:" then
            local realLink = string.gsub(string.sub(msg, 5), "*", "|")
            requests[realLink] = sender; UpdateUI()
        elseif string.sub(msg, 1, 6) == "NOTIF:" then
            local payload = string.sub(msg, 7); local s1 = string.find(payload, "#!#")
            if s1 then
                local cmd = string.sub(payload, 1, s1 - 1); local rest = string.sub(payload, s1 + 3); local s2 = string.find(rest, "#!#")
                if s2 then
                    local encodedLink = string.sub(rest, 1, s2 - 1); local targetPlayer = string.sub(rest, s2 + 3)
                    if targetPlayer == UnitName("player") then
                        local realLink = string.gsub(encodedLink, "*", "|")
                        if cmd == "ACC" then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Your reserve for " .. realLink .. " was ACCEPTED!|r")
                        else DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Your reserve for " .. realLink .. " was denied.|r") end
                    end
                end
            end
        end
    end
end)

-- 7. SLASH COMMANDS
SLASH_RAIDRESERVE1 = "/rr"
SlashCmdList["RAIDRESERVE"] = function(msg)
    if not msg or msg == "" then if frame:IsShown() then frame:Hide() else frame:Show() end return end
    if msg == "clear" then RaidReserve_Data.reserves = {}; requests = {}; UpdateUI(); return end
    if msg == "push" then PushListToRaid(); return end
    if msg == "announce" then AnnounceCustom(); return end
    local _, _, itemLink = string.find(msg, "(|c%x+|Hitem:[%-?%d:]+|h%[.-%]|h|r)")
    if itemLink then
        if IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0) then
            local remainder = string.gsub(msg, ".*|h|r%s*", "")
            local targetName = (remainder ~= "" and remainder) or UnitName("target") or UnitName("player")
            RaidReserve_Data.reserves[itemLink] = targetName; UpdateUI()
        else SendComm("REQ:" .. string.gsub(itemLink, "|", "*")) end
    end
end

-- 8. MINIMAP BUTTON
local btn = CreateFrame("Button", "RR_MinimapButton", UIParent)
btn:SetWidth(34); btn:SetHeight(34); btn:SetPoint("CENTER", 0, 0); btn:SetMovable(true); btn:EnableMouse(true)
local btnTex = btn:CreateTexture(nil, "BACKGROUND")
btnTex:SetTexture("Interface\\Icons\\INV_Misc_Coin_01"); btnTex:SetWidth(20); btnTex:SetHeight(20); btnTex:SetPoint("CENTER", 0, 0)
local btnBorder = btn:CreateTexture(nil, "OVERLAY")
btnBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); btnBorder:SetWidth(52); btnBorder:SetHeight(52); btnBorder:SetPoint("TOPLEFT", 0, 0)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"); btn:RegisterForClicks("LeftButtonUp")
btn:SetScript("OnMouseDown", function() if IsShiftKeyDown() then btn:StartMoving() end end)
btn:SetScript("OnMouseUp", function() 
    btn:StopMovingOrSizing() 
    local point, _, _, x, y = btn:GetPoint(); RaidReserve_Data.pos = {point, x, y}
end)
btn:SetScript("OnClick", function() if not IsShiftKeyDown() then if frame:IsShown() then frame:Hide() else frame:Show() end end end)