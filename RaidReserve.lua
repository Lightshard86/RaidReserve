-- Initialize global storage
RaidReserve_Data = RaidReserve_Data or { reserves = {}, pos = {"CENTER", 0, 0} }
local prefix = "RAIDRES"
local requests = {} 
local rows = {}
local syncQueue = {} 
local tempReserves = {} 

-- 1. MAIN WINDOW
local frame = CreateFrame("Frame", "RaidReserveFrame", UIParent)
frame:SetWidth(350); frame:SetHeight(480); frame:SetPoint("CENTER", 0, 0)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() frame:StartMoving() end)
frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -15); title:SetText("Raid Reserve List")

-- 2. DYNAMIC ROW SYSTEM
local function CreateRow(id)
    local f = CreateFrame("Button", "RR_Row"..id, frame)
    f:SetWidth(320); f:SetHeight(20); f:SetPoint("TOPLEFT", 15, -40 - (id * 22))
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", 5, 0)
    
    f:SetScript("OnEnter", function()
        if f.link then
            local _, _, rawLink = string.find(f.link, "|H(item:[%-?%d:]+)|h")
            if rawLink then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(rawLink)
                GameTooltip:Show()
            end
        end
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", function()
        if not (IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)) then return end
        
        if f.isRequest then
            local safeLink = string.gsub(f.link, "|", "*")
            if arg1 == "LeftButton" then
                -- ACCEPTED
                RaidReserve_Data.reserves[f.link] = f.player
                requests[f.link] = nil
                SendComm("NOTIF:ACC#!#" .. safeLink .. "#!#" .. f.player)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Accepted:|r " .. f.link .. " for " .. f.player)
            else 
                -- DENIED
                SendComm("NOTIF:DNY#!#" .. safeLink .. "#!#" .. f.player)
                requests[f.link] = nil 
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Declined:|r " .. f.link .. " for " .. f.player)
            end
        else
            if arg1 == "RightButton" and f.link then RaidReserve_Data.reserves[f.link] = nil end
        end
        UpdateUI()
    end)
    f:Hide()
    return f
end

for i=1, 20 do rows[i] = CreateRow(i) end

function UpdateUI()
    for i=1, 20 do rows[i]:Hide() end
    local count = 0
    for itemLink, player in pairs(RaidReserve_Data.reserves) do
        count = count + 1
        if count <= 20 then
            local row = rows[count]
            row.link = itemLink; row.player = player; row.isRequest = false
            row.text:SetText(itemLink .. "  ->  |cff00ff00" .. player .. "|r")
            row:Show()
        end
    end

    local isLead = IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0)
    pushBtn:Show()
    if isLead then pushBtn:Enable() else pushBtn:Disable() end

    if isLead then
        for itemLink, player in pairs(requests) do
            count = count + 1
            if count <= 20 then
                local row = rows[count]
                row.link = itemLink; row.player = player; row.isRequest = true
                row.text:SetText("|cffffff00[REQ]|r " .. itemLink .. "  ->  " .. player)
                row:Show()
            end
        end
    end
    if count == 0 then
        rows[1].text:SetText("No reserves active."); rows[1].link = nil; rows[1]:Show()
    end
end

-- 3. THE SYNC ENGINE
function SendComm(msg)
    local chan = "RAID"
    if GetNumRaidMembers() == 0 then
        if GetNumPartyMembers() > 0 then chan = "PARTY" else return end
    end
    SendAddonMessage(prefix, msg, chan)
end

local syncTimer = 0
frame:SetScript("OnUpdate", function()
    if table.getn(syncQueue) > 0 then
        syncTimer = syncTimer + (arg1 or 0.1)
        if syncTimer > 0.4 then 
            local msg = table.remove(syncQueue, 1)
            if msg then 
                SendComm(msg) 
                if string.sub(msg, 1, 4) == "ADD:" then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaaRR: Sending item data...|r")
                elseif msg == "END" then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR: Push Complete!|r")
                end
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
        local safeLink = string.gsub(link, "|", "*")
        table.insert(syncQueue, "ADD:" .. safeLink .. ":" .. player)
    end
    table.insert(syncQueue, "END")
end

-- 4. PUSH BUTTON
pushBtn = CreateFrame("Button", "RR_PushBtn", frame, "UIPanelButtonTemplate")
pushBtn:SetWidth(120); pushBtn:SetHeight(25); pushBtn:SetPoint("BOTTOM", 0, 15)
pushBtn:SetText("Push to Raid")
pushBtn:SetScript("OnClick", function() PushListToRaid() end)

-- 5. EVENT HANDLER
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")

frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(prefix) end
        UpdateUI()
    elseif event == "RAID_ROSTER_UPDATE" then
        UpdateUI()
    elseif event == "CHAT_MSG_ADDON" and arg1 == prefix then
        local msg = arg2
        local sender = arg4
        if sender == UnitName("player") then return end

        if msg == "START" then
            tempReserves = {}
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR:|r Sync started by " .. sender .. "...")
        elseif string.sub(msg, 1, 4) == "ADD:" then
            local lastColon = 0
            for i = string.len(msg), 5, -1 do
                if string.sub(msg, i, i) == ":" then lastColon = i; break end
            end
            if lastColon > 4 then
                local encodedLink = string.sub(msg, 5, lastColon - 1)
                local player = string.sub(msg, lastColon + 1)
                tempReserves[string.gsub(encodedLink, "*", "|")] = player
            end
        elseif msg == "END" then
            RaidReserve_Data.reserves = {}
            for k, v in pairs(tempReserves) do RaidReserve_Data.reserves[k] = v end
            UpdateUI()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR:|r Sync Complete.")
        elseif string.sub(msg, 1, 4) == "REQ:" then
            local realLink = string.gsub(string.sub(msg, 5), "*", "|")
            requests[realLink] = sender
            UpdateUI()
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00RR Req:|r " .. realLink .. " from " .. sender)
        
        -- UPDATED NOTIFICATION HANDLER
        elseif string.sub(msg, 1, 6) == "NOTIF:" then
            local payload = string.sub(msg, 7)
            -- Use specific split on #!# to avoid link colons
            local s1 = string.find(payload, "#!#")
            if s1 then
                local cmd = string.sub(payload, 1, s1 - 1)
                local rest = string.sub(payload, s1 + 3)
                local s2 = string.find(rest, "#!#")
                if s2 then
                    local encodedLink = string.sub(rest, 1, s2 - 1)
                    local targetPlayer = string.sub(rest, s2 + 3)
                    
                    if targetPlayer == UnitName("player") then
                        local realLink = string.gsub(encodedLink, "*", "|")
                        if cmd == "ACC" then
                            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Your reserve request for " .. realLink .. " was ACCEPTED by " .. sender .. "!|r")
                        else
                            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Your reserve request for " .. realLink .. " was denied by " .. sender .. ".|r")
                        end
                    end
                end
            end
        end
    end
end)

-- 6. SLASH COMMANDS
SLASH_RAIDRESERVE1 = "/rr"
SlashCmdList["RAIDRESERVE"] = function(msg)
    if not msg or msg == "" then
        if frame:IsShown() then frame:Hide() else frame:Show() end
        return
    end
    if msg == "clear" then
        if IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0) then
            RaidReserve_Data.reserves = {}; requests = {}; UpdateUI()
        end
        return
    end
    if msg == "push" then PushListToRaid(); return end

    local itemLink = string.match(msg, "|c%x+|Hitem:[%-?%d:]+|h%[.-%]|h|r")
    if itemLink then
        if IsRaidLeader() or IsRaidOfficer() or (GetNumRaidMembers() == 0) then
            local remainder = string.gsub(msg, ".*|h|r%s*", "")
            local targetName = (remainder ~= "" and remainder) or UnitName("target") or UnitName("player")
            RaidReserve_Data.reserves[itemLink] = targetName; UpdateUI()
        else
            local safe = string.gsub(itemLink, "|", "*")
            SendComm("REQ:" .. safe)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00RR:|r Request sent for " .. itemLink)
        end
    end
end

-- 7. MINIMAP BUTTON
local btn = CreateFrame("Button", "RR_MinimapButton", UIParent)
btn:SetWidth(34); btn:SetHeight(34); btn:SetPoint("CENTER", 0, 0); btn:SetMovable(true); btn:EnableMouse(true)
local btnTex = btn:CreateTexture(nil, "BACKGROUND")
btnTex:SetTexture("Interface\\Icons\\INV_Misc_Coin_01"); btnTex:SetWidth(20); btnTex:SetHeight(20); btnTex:SetPoint("CENTER", 0, 0)
local btnBorder = btn:CreateTexture(nil, "OVERLAY")
btnBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); btnBorder:SetWidth(52); btnBorder:SetHeight(52); btnBorder:SetPoint("TOPLEFT", 0, 0)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"); btn:RegisterForClicks("LeftButtonUp")
btn:SetScript("OnMouseDown", function() if IsShiftKeyDown() then btn:StartMoving() end end)
btn:SetScript("OnMouseUp", function() btn:StopMovingOrSizing() end)
btn:SetScript("OnClick", function() if not IsShiftKeyDown() then if frame:IsShown() then frame:Hide() else frame:Show() end end end)