-- 0. INITIALIZE STORAGE
RaidReserve_Data = RaidReserve_Data or {}
if not RaidReserve_Data.reserves then RaidReserve_Data.reserves = {} end
if not RaidReserve_Data.legUpgrades then RaidReserve_Data.legUpgrades = {} end
if not RaidReserve_Data.stats then RaidReserve_Data.stats = {won = 0, total = 0} end
if not RaidReserve_Data.pos then RaidReserve_Data.pos = {"CENTER", 0, 0} end
if RaidReserve_Data.width == nil then RaidReserve_Data.width = 360 end
if RaidReserve_Data.height == nil then RaidReserve_Data.height = 520 end
if RaidReserve_Data.hideBtn == nil then RaidReserve_Data.hideBtn = false end
if RaidReserve_Data.showStats == nil then RaidReserve_Data.showStats = true end
if RaidReserve_Data.selectedChannel == nil then RaidReserve_Data.selectedChannel = "RAID" end

local prefix = "RAIDRES"
local requests, rows, syncQueue, tempReserves = {}, {}, {}, {}
local addonUsers = {} -- Table for tooltip names
local upgradeList = {"Thunderfury", "Sulfuras", "Priest Staff", "Ashbringer", "Splinter", "Hunter Bow", "Dagger", "Shamy Mace", "Shamy Totem", "Druid Staff"}
local activePopupData = nil

-- 1. HELPER FUNCTIONS
function SetSafeTooltip(anchorFrame, link)
    if not link then return end
    local _, _, rawLink = string.find(link, "(item:[%-?%d:]+)")
    if rawLink then 
        GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(rawLink)
        GameTooltip:Show() 
    end
end

function SendComm(msg) 
    local chan = (GetNumRaidMembers() > 0 and "RAID") or (GetNumPartyMembers() > 0 and "PARTY")
    if chan then SendAddonMessage(prefix, msg, chan) end
end

-- 2. UI OBJECT CREATION
local frame = CreateFrame("Frame", "RaidReserveFrame", UIParent)
frame:SetWidth(RaidReserve_Data.width); frame:SetHeight(RaidReserve_Data.height); frame:SetPoint("CENTER", 0, 0)
frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 }})
frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95); frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
frame:EnableMouse(true); frame:SetMovable(true); frame:SetResizable(true); frame:SetMinResize(340, 500)
frame:RegisterForDrag("LeftButton"); frame:Hide()
frame:SetScript("OnDragStart", function() frame:StartMoving() end)
frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOP", 0, -12); title:SetText("RAID RESERVE"); title:SetTextColor(1, 0.82, 0)

-- 2a. USER TRACKER (TOP RIGHT)
local userCount = CreateFrame("Button", "RR_UserTracker", frame)
userCount:SetWidth(80); userCount:SetHeight(20); userCount:SetPoint("TOPRIGHT", -12, -12)
userCount:EnableMouse(true)
userCount.text = userCount:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); userCount.text:SetAllPoints(); userCount.text:SetJustifyH("RIGHT"); userCount.text:SetTextColor(0.5, 0.5, 0.5)

userCount:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Addon Users In Group:", 1, 1, 1)
    local any = false
    for name in pairs(addonUsers) do
        GameTooltip:AddLine("- " .. name, 0, 1, 0)
        any = true
    end
    if not any then GameTooltip:AddLine("Only you.", 0.5, 0.5, 0.5) end
    GameTooltip:Show()
end)
userCount:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- 2b. LOOT JOURNAL (STATS)
local sFrame = CreateFrame("Frame", "RR_StatsFrame", frame)
sFrame:SetWidth(200); sFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0); sFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 2, 0)
sFrame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 }})
sFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95); sFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

local sTitle = sFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal"); sTitle:SetPoint("TOP", 0, -15); sTitle:SetText("LOOT JOURNAL"); sTitle:SetTextColor(1, 0.82, 0)
local sTotalLabel = sFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); sTotalLabel:SetPoint("TOPLEFT", 20, -50); sTotalLabel:SetText("Total Reserved:"); sTotalLabel:SetTextColor(0, 0.8, 1)
local sTotalVal = sFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); sTotalVal:SetPoint("LEFT", sTotalLabel, "RIGHT", 10, 0); sTotalVal:SetText("0")
local sWonLabel = sFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); sWonLabel:SetPoint("TOPLEFT", 20, -80); sWonLabel:SetText("Items Dropped:"); sWonLabel:SetTextColor(0, 0.8, 1)
local sWonVal = sFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); sWonVal:SetPoint("LEFT", sWonLabel, "RIGHT", 10, 0); sWonVal:SetText("0")
local sBarLabel = sFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); sBarLabel:SetPoint("TOP", 0, -125); sBarLabel:SetText("Loot Luck Gauge"); sBarLabel:SetTextColor(0.7, 0.7, 0.7)

local sBar = CreateFrame("StatusBar", nil, sFrame); sBar:SetWidth(160); sBar:SetHeight(18); sBar:SetPoint("TOP", 0, -145); sBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); sBar:SetMinMaxValues(0, 100); sBar:SetValue(0)
local sBarBG = sBar:CreateTexture(nil, "BACKGROUND"); sBarBG:SetAllPoints(); sBarBG:SetTexture(0.1, 0.1, 0.1, 1)
local sPercentText = sBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); sPercentText:SetPoint("CENTER", 0, 0); sPercentText:SetText("0%")
local sBanterText = sFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); sBanterText:SetPoint("TOP", sBar, "BOTTOM", 0, -10); sBanterText:SetWidth(180); sBanterText:SetText("")
local sResetBtn = CreateFrame("Button", nil, sFrame, "UIPanelButtonTemplate"); sResetBtn:SetWidth(80); sResetBtn:SetHeight(20); sResetBtn:SetPoint("BOTTOM", 0, 15); sResetBtn:SetText("Reset")

-- 2c. CHOICE WINDOW (POPUP)
local choiceFrame = CreateFrame("Frame", "RR_ChoiceFrame", UIParent)
choiceFrame:SetWidth(280); choiceFrame:SetHeight(140); choiceFrame:SetPoint("CENTER", 0, 100)
choiceFrame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 }})
choiceFrame:SetBackdropColor(0.1, 0.1, 0.1, 1); choiceFrame:SetFrameStrata("DIALOG"); choiceFrame:Hide()
local choiceTitle = choiceFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal"); choiceTitle:SetPoint("TOP", 0, -20); choiceTitle:SetWidth(240)
local btnWon = CreateFrame("Button", nil, choiceFrame, "UIPanelButtonTemplate"); btnWon:SetWidth(80); btnWon:SetHeight(24); btnWon:SetPoint("BOTTOMLEFT", 15, 20); btnWon:SetText("DROP!")
local btnLost = CreateFrame("Button", nil, choiceFrame, "UIPanelButtonTemplate"); btnLost:SetWidth(80); btnLost:SetHeight(24); btnLost:SetPoint("BOTTOM", 0, 20); btnLost:SetText("*_*")
local btnRem = CreateFrame("Button", nil, choiceFrame, "UIPanelButtonTemplate"); btnRem:SetWidth(80); btnRem:SetHeight(24); btnRem:SetPoint("BOTTOMRIGHT", -15, 20); btnRem:SetText("Remove")

local line = frame:CreateTexture(nil, "ARTWORK"); line:SetHeight(1); line:SetPoint("BOTTOMLEFT", 20, 185); line:SetPoint("BOTTOMRIGHT", -20, 185); line:SetTexture(0.3, 0.3, 0.3, 0.8)
local goblinText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); goblinText:SetPoint("BOTTOM", line, "TOP", 0, 4); goblinText:SetText("")
local recruitLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); recruitLabel:SetPoint("BOTTOMLEFT", 25, 165); recruitLabel:SetText("Announce Message: (Example: LF 2 MC)"); recruitLabel:SetTextColor(0, 0.8, 1)
local recruitEB = CreateFrame("EditBox", "RR_RecruitEB", frame, "InputBoxTemplate"); recruitEB:SetPoint("BOTTOMLEFT", 22, 145); recruitEB:SetPoint("BOTTOMRIGHT", -22, 145); recruitEB:SetHeight(20); recruitEB:SetAutoFocus(false); recruitEB:SetText("")
local chanLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); chanLabel:SetPoint("BOTTOMLEFT", 25, 118); chanLabel:SetText("Channel:"); chanLabel:SetTextColor(0, 0.8, 1)
local dropdown = CreateFrame("Frame", "RR_ChannelDropdown", frame, "UIDropDownMenuTemplate"); dropdown:SetPoint("BOTTOMLEFT", -5, 88)
local legLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); legLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 195, 118); legLabel:SetText("Leg. Upgrade:"); legLabel:SetTextColor(0, 0.8, 1)
local legDropdown = CreateFrame("Frame", "RR_LegDropdown", frame, "UIDropDownMenuTemplate"); legDropdown:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 165, 88)
local hideCB = CreateFrame("CheckButton", "RR_HideCheck", frame, "UICheckButtonTemplate"); hideCB:SetPoint("BOTTOMLEFT", 30, 58); getglobal(hideCB:GetName().."Text"):SetText("Hide Icon"); getglobal(hideCB:GetName().."Text"):SetTextColor(0.7, 0.7, 0.7)
local statsCB = CreateFrame("CheckButton", "RR_StatsCheck", frame, "UICheckButtonTemplate"); statsCB:SetPoint("BOTTOMLEFT", 195, 58); getglobal(statsCB:GetName().."Text"):SetText("Stats Panel"); getglobal(statsCB:GetName().."Text"):SetTextColor(0.7, 0.7, 0.7)
local pushBtn = CreateFrame("Button", "RR_PushBtn", frame, "UIPanelButtonTemplate"); pushBtn:SetWidth(130); pushBtn:SetHeight(26); pushBtn:SetPoint("BOTTOMLEFT", 35, 18); pushBtn:SetText("Push to Raid")
local announceBtn = CreateFrame("Button", "RR_AnnounceBtn", frame, "UIPanelButtonTemplate"); announceBtn:SetWidth(130); announceBtn:SetHeight(26); announceBtn:SetPoint("BOTTOMRIGHT", -35, 18); announceBtn:SetText("Announce")

-- 3. CORE LOGIC
function RecordStat(won)
    RaidReserve_Data.stats.total = RaidReserve_Data.stats.total + 1
    if won then RaidReserve_Data.stats.won = RaidReserve_Data.stats.won + 1 end
    UpdateUI()
end

function UpdateUI()
    for i=1, 30 do if rows[i] then rows[i]:Hide() end end
    local count, myResCount = 0, 0
    local myName = UnitName("player") or "Unknown"
    addonUsers[myName] = true

    for link, player in pairs(RaidReserve_Data.reserves) do
        count = count + 1
        if player == myName then myResCount = myResCount + 1 end
        if rows[count] then local row = rows[count]; row.link = link; row.player = player; row.isRequest = false; row.text:SetText(link .. "  |cff888888→|r  |cff00ff00" .. player .. "|r"); rows[count]:Show() end
    end
    goblinText:SetText((myResCount == 0 and "|cff888888No treasures claimed yet...|r") or (myResCount == 1 and "|cff00ff00A humble request. Good luck!|r") or (myResCount == 2 and "|cff00ccffDouble the chances!|r") or (myResCount == 3 and "|cffffff00Aiming high!|r") or (myResCount == 4 and "|cffff9900Bags looking empty?|r") or "|cffff0000YOU GREEDY LOOT GOBLIN!|r")
    
    local isL = IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)
    hideCB:SetChecked(RaidReserve_Data.hideBtn); statsCB:SetChecked(RaidReserve_Data.showStats)
    if RaidReserve_Data.showStats then sFrame:Show() else sFrame:Hide() end
    if isL then pushBtn:Enable(); announceBtn:Enable(); recruitEB:Show(); recruitLabel:Show(); dropdown:Show(); chanLabel:Show(); legDropdown:Show(); legLabel:Show()
    else pushBtn:Disable(); announceBtn:Disable(); recruitEB:Hide(); recruitLabel:Hide(); dropdown:Hide(); chanLabel:Hide(); legDropdown:Hide(); legLabel:Hide() end
    
    local totalU = 0; for _ in pairs(addonUsers) do totalU = totalU + 1 end
    userCount.text:SetText("Users: " .. totalU)
    UIDropDownMenu_SetSelectedValue(dropdown, RaidReserve_Data.selectedChannel or "RAID")
    
    if isL then
        for link, player in pairs(requests) do
            count = count + 1; if rows[count] then local row = rows[count]; row.link = link; row.player = player; row.isRequest = true; row.text:SetText("|cffffff00[REQ]|r " .. link .. "  |cff888888→|r  " .. player); rows[count]:Show() end
        end
    end
    if count == 0 and rows[1] then rows[1].text:SetText("|cff666666No reserves active.|r"); rows[1].link = nil; rows[1]:Show() end

    local s = RaidReserve_Data.stats; sTotalVal:SetText(s.total); sWonVal:SetText(s.won); local rate = (s.total > 0) and math.floor((s.won / s.total) * 100) or 0; sBar:SetValue(rate); sPercentText:SetText(rate .. "%")
    if rate == 0 then sBanterText:SetText("Absolute Zero. Total loot desert."); sBanterText:SetTextColor(0.5, 0.5, 0.5) elseif rate < 20 then sBanterText:SetText("Cursed? RNG is your mortal enemy."); sBanterText:SetTextColor(1, 0, 0) elseif rate < 40 then sBanterText:SetText("Meh. Just enough to stay quiet."); sBanterText:SetTextColor(1, 0.5, 0) elseif rate < 60 then sBanterText:SetText("Solid. You're actually winning!"); sBanterText:SetTextColor(1, 1, 0) elseif rate < 80 then sBanterText:SetText("Loot Magnet! Calm down a bit."); sBanterText:SetTextColor(0, 1, 0) elseif rate < 100 then sBanterText:SetText("RNG GOD. Is your dad a GM?"); sBanterText:SetTextColor(0, 1, 1) else sBanterText:SetText("ILLEGAL. Stop stealing everything!"); sBanterText:SetTextColor(1, 0, 1) end
    if rate < 25 then sBar:SetStatusBarColor(1, 0, 0) elseif rate < 50 then sBar:SetStatusBarColor(1, 1, 0) else sBar:SetStatusBarColor(0, 1, 0) end
end

-- 4. INTERACTION HELPERS
StaticPopupDialogs["RR_CONFIRM_RESET"] = { text = "Are you Sure?", button1 = "Clean Stats", button2 = "don't clean", OnAccept = function() RaidReserve_Data.stats = {won = 0, total = 0}; UpdateUI() end, timeout = 0, whileDead = 1, hideOnEscape = 1 }

local function Choice_Resolve(action)
    if activePopupData then
        local l, p = activePopupData.l, activePopupData.p; syncQueue = {}
        if action == "WON" then if p == UnitName("player") then RecordStat(true) end; table.insert(syncQueue, "NOTIF:STAT#!#" .. string.gsub(l,"|","*") .. "#!#WON#!#" .. p)
        elseif action == "LOST" then if p == UnitName("player") then RecordStat(false) end; table.insert(syncQueue, "NOTIF:STAT#!#" .. string.gsub(l,"|","*") .. "#!#LOST#!#" .. p) end
        RaidReserve_Data.reserves[l] = nil; activePopupData = nil; choiceFrame:Hide(); UpdateUI()
        table.insert(syncQueue, "START"); for link, player in pairs(RaidReserve_Data.reserves) do table.insert(syncQueue, "ADD:" .. string.gsub(link, "|", "*") .. ":" .. player) end; table.insert(syncQueue, "END")
    end
end

function AnnounceCustom()
    local val = RaidReserve_Data.selectedChannel or "RAID"; local chan = (tonumber(val) and "CHANNEL") or val; local num = tonumber(val); local intro = recruitEB:GetText()
    if intro and intro ~= "" then SendChatMessage(intro, chan, nil, num) end
    SendChatMessage("--- Reserved Items: ---", chan, nil, num)
    local upStr = ""; for _, n in pairs(upgradeList) do if RaidReserve_Data.legUpgrades[n] then upStr = (upStr == "" and n) or (upStr .. ", " .. n) end end
    if upStr ~= "" then SendChatMessage("|cffffff00Legendary Upgrades: " .. upStr .. "|r", chan, nil, num) end
    local cur = ""; for link in pairs(RaidReserve_Data.reserves) do if string.len(cur .. "  " .. link) > 200 then SendChatMessage(cur, chan, nil, num); cur = link else cur = (cur == "" and link) or (cur .. "  " .. link) end end
    if cur ~= "" then SendChatMessage(cur, chan, nil, num) end
end

for i=1, 30 do
    local f = CreateFrame("Button", "RR_Row"..i, frame); f:SetHeight(18); f:SetPoint("TOPLEFT", 15, -35 - (i * 20)); f:SetPoint("RIGHT", -15, 0); f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.text:SetPoint("LEFT", 5, 0)
    f:SetScript("OnEnter", function() SetSafeTooltip(this, f.link) end); f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function()
        if not (IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)) then return end
        if f.isRequest then
            local safe = string.gsub(f.link, "|", "*")
            syncQueue = {}
            if arg1 == "LeftButton" then RaidReserve_Data.reserves[f.link] = f.player; requests[f.link] = nil; table.insert(syncQueue, "NOTIF:ACC#!#" .. safe .. "#!#" .. f.player)
            else table.insert(syncQueue, "NOTIF:DNY#!#" .. safe .. "#!#" .. f.player); requests[f.link] = nil end
            table.insert(syncQueue, "START"); for link, player in pairs(RaidReserve_Data.reserves) do table.insert(syncQueue, "ADD:" .. string.gsub(link, "|", "*") .. ":" .. player) end; table.insert(syncQueue, "END")
        else if arg1 == "RightButton" and f.link then activePopupData = {l = f.link, p = f.player}; choiceTitle:SetText("Did " .. f.link .. " drop for " .. f.player .. "?"); choiceFrame:Show() end end
        UpdateUI()
    end); f:Hide(); rows[i] = f
end

-- 5. ATTACH SCRIPTS
btnWon:SetScript("OnClick", function() Choice_Resolve("WON") end); btnLost:SetScript("OnClick", function() Choice_Resolve("LOST") end); btnRem:SetScript("OnClick", function() Choice_Resolve("REMOVE") end)
sResetBtn:SetScript("OnClick", function() StaticPopup_Show("RR_CONFIRM_RESET") end)
pushBtn:SetScript("OnClick", function() if not (IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)) then return end; DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR:|r Syncing list..."); syncQueue = {}; table.insert(syncQueue, "START"); for link, player in pairs(RaidReserve_Data.reserves) do table.insert(syncQueue, "ADD:" .. string.gsub(link, "|", "*") .. ":" .. player) end; table.insert(syncQueue, "END") end)
announceBtn:SetScript("OnClick", function() AnnounceCustom() end)
hideCB:SetScript("OnClick", function() RaidReserve_Data.hideBtn = (this:GetChecked() == 1); if RaidReserve_Data.hideBtn then RR_MinimapButton:Hide() else RR_MinimapButton:Show() end end)
statsCB:SetScript("OnClick", function() RaidReserve_Data.showStats = (this:GetChecked() == 1); if RaidReserve_Data.showStats then sFrame:Show() else sFrame:Hide() end end)
local resHandle = CreateFrame("Button", "RR_ResizeHandle", frame)
resHandle:SetWidth(18)
resHandle:SetHeight(18)
resHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
resHandle:SetFrameLevel(frame:GetFrameLevel() + 10)
local gTex = resHandle:CreateTexture(nil, "OVERLAY")
gTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Corner")
gTex:SetAllPoints(resHandle)
gTex:SetVertexColor(0.8, 0.8, 0.8, 1)
resHandle:SetScript("OnEnter", function() gTex:SetVertexColor(1, 0.82, 0, 1) end)
resHandle:SetScript("OnLeave", function() gTex:SetVertexColor(0.8, 0.8, 0.8, 1) end)
resHandle:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
resHandle:SetScript("OnMouseUp", function() 
    frame:StopMovingOrSizing()
    RaidReserve_Data.width = frame:GetWidth()
    RaidReserve_Data.height = frame:GetHeight()
end)

-- 6. DROPDOWNS & EVENTS
local function Chan_OnClick() UIDropDownMenu_SetSelectedID(RR_ChannelDropdown, this:GetID()); RaidReserve_Data.selectedChannel = this.value end
local function Leg_OnClick() RaidReserve_Data.legUpgrades[this.value] = not RaidReserve_Data.legUpgrades[this.value] end
local function Chan_Init() local info = {}; local channels = { { text = "Say", value = "SAY" }, { text = "Party", value = "PARTY" }, { text = "Raid", value = "RAID" }, { text = "Guild", value = "GUILD" }, { text = "/1", value = "1" }, { text = "/2", value = "2" }, { text = "/3", value = "3" }, { text = "/4", value = "4" } }; for i, entry in pairs(channels) do info.text = entry.text; info.value = entry.value; info.func = Chan_OnClick; info.checked = (RaidReserve_Data.selectedChannel == entry.value); UIDropDownMenu_AddButton(info) end end
local function Leg_Init() local info = {}; for _, name in pairs(upgradeList) do info.text = name; info.value = name; info.func = Leg_OnClick; info.checked = RaidReserve_Data.legUpgrades[name]; info.keepShownOnClick = 1; UIDropDownMenu_AddButton(info) end end
UIDropDownMenu_Initialize(dropdown, Chan_Init); UIDropDownMenu_SetWidth(125, dropdown)
UIDropDownMenu_Initialize(legDropdown, Leg_Init); UIDropDownMenu_SetWidth(125, legDropdown); UIDropDownMenu_SetText("Select Upgrades", legDropdown)

frame:RegisterEvent("CHAT_MSG_ADDON"); frame:RegisterEvent("VARIABLES_LOADED"); frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:SetScript("OnUpdate", function() if table.getn(syncQueue) > 0 then syncTimer = (syncTimer or 0) + (arg1 or 0.1); if syncTimer > 0.4 then local msg = table.remove(syncQueue, 1); if msg then SendComm(msg); if string.sub(msg, 1, 4) == "ADD:" then DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaRR: Syncing...|r") elseif msg == "END" then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR: Sync Complete!|r") end end; syncTimer = 0 end end end)
frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(prefix) end
        if RaidReserve_Data.hideBtn then RR_MinimapButton:Hide() end
        frame:SetWidth(RaidReserve_Data.width or 360); frame:SetHeight(RaidReserve_Data.height or 520); UpdateUI()
    elseif event == "CHAT_MSG_ADDON" and arg1 == prefix then
        local msg = arg2; local sender = arg4; if sender == UnitName("player") then return end
        if msg == "PING" then SendComm("PONG")
        elseif msg == "PONG" then addonUsers[sender] = true; UpdateUI()
        elseif msg == "START" then tempReserves = {}
        elseif string.sub(msg, 1, 4) == "ADD:" then local lastColon = 0; for i = string.len(msg), 5, -1 do if string.sub(msg, i, i) == ":" then lastColon = i; break end end; if lastColon > 4 then tempReserves[string.gsub(string.sub(msg, 5, lastColon - 1), "*", "|")] = string.sub(msg, lastColon + 1) end
        elseif msg == "END" then RaidReserve_Data.reserves = {}; for k, v in pairs(tempReserves) do RaidReserve_Data.reserves[k] = v end; UpdateUI()
        elseif string.sub(msg, 1, 4) == "REQ:" then requests[string.gsub(string.sub(msg, 5), "*", "|")] = sender; UpdateUI(); DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RR Request:|r " .. string.gsub(string.sub(msg, 5), "*", "|") .. " from " .. sender)
        elseif string.sub(msg, 1, 6) == "NOTIF:" then
            local p = string.sub(msg, 7); local s1 = string.find(p, "#!#")
            if s1 then
                local cmd, rest = string.sub(p, 1, s1-1), string.sub(p, s1+3)
                local s2 = string.find(rest, "#!#")
                if s2 then
                    local l = string.gsub(string.sub(rest, 1, s2-1), "*", "|"); local rest2 = string.sub(rest, s2+3)
                    local s3 = string.find(rest2, "#!#")
                    if s3 then
                        local dec, target = string.sub(rest2, 1, s3-1), string.sub(rest2, s3+3)
                        if target == UnitName("player") and cmd == "STAT" then RecordStat(dec == "WON") end
                    else if rest2 == UnitName("player") then
                            if cmd == "ACC" then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Your reserve for " .. l .. " was ACCEPTED!|r")
                            elseif cmd == "DNY" then DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Your reserve for " .. l .. " was denied.|r") end
                        end
                    end
                end
            end
        end
    end
end)
frame:SetScript("OnShow", function() addonUsers = {}; addonUsers[UnitName("player")] = true; SendComm("PING"); UpdateUI() end)
SLASH_RAIDRESERVE1 = "/rr"; SlashCmdList["RAIDRESERVE"] = function(msg)
    if not msg or msg == "" then if frame:IsShown() then frame:Hide() else frame:Show() end return end
    if msg == "reset" then RaidReserve_Data.width = 360; RaidReserve_Data.height = 520; frame:SetWidth(360); frame:SetHeight(520); return end
    if msg == "clear" then RaidReserve_Data.reserves = {}; requests = {}; UpdateUI(); return end
    if msg == "clearstats" then RaidReserve_Data.stats = {won=0, total=0}; UpdateUI(); return end
    local _, _, link = string.find(msg, "(|c%x+|Hitem:[%-?%d:]+|h%[.-%]|h|r)")
    if link then
        if IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0) then
            local r = string.gsub(msg, ".*|h|r%s*", ""); RaidReserve_Data.reserves[link] = (r ~= "" and r) or UnitName("target") or UnitName("player"); UpdateUI()
        else SendComm("REQ:" .. string.gsub(link, "|", "*")); DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR:|r Request sent for " .. link) end
    end
end
local mBtn = CreateFrame("Button", "RR_MinimapButton", UIParent); mBtn:SetWidth(34); mBtn:SetHeight(34); mBtn:SetPoint("CENTER", 0, 0); mBtn:SetMovable(true); mBtn:EnableMouse(true); local bt = mBtn:CreateTexture(nil, "BACKGROUND"); bt:SetTexture("Interface\\Icons\\INV_Misc_Coin_01"); bt:SetWidth(20); bt:SetHeight(20); bt:SetPoint("CENTER", 0, 0); local bb = mBtn:CreateTexture(nil, "OVERLAY"); bb:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); bb:SetWidth(52); bb:SetHeight(52); bb:SetPoint("TOPLEFT", 0, 0); mBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"); mBtn:RegisterForClicks("LeftButtonUp"); mBtn:SetScript("OnMouseDown", function() if IsShiftKeyDown() then mBtn:StartMoving() end end); mBtn:SetScript("OnMouseUp", function() mBtn:StopMovingOrSizing(); local p, _, _, x, y = mBtn:GetPoint(); RaidReserve_Data.pos = {p, x, y} end); mBtn:SetScript("OnClick", function() if not IsShiftKeyDown() then if frame:IsShown() then frame:Hide() else frame:Show() end end end)