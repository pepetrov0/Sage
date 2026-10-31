--[[ Sage - next talent suggestion for WotLK 3.3.5
     While the talent window is open and you are out of combat, shows the
     talent to learn next in a card below it (name, rank, description), as
     long as you have unspent talent points. It follows the preset build for your class
     (Builds\CLASS_Spec.lua). Without one, or once the build is done, it stays
     in the tree where you have spent the most points and takes the first
     unlocked talent that is not maxed, top tier and leftmost column first.

     At level 10 and above, with the talent window open and out of combat, it
     asks which build you want if you have not picked one, and asks again
     after you reset your talents. Dual spec: each talent group has its own pick.

     /sage status   show what it is doing
     /sage on|off   enable or disable
     /sage build    list the builds for your class, /sage build <name> picks one
     /sage log      toggle the chat message when the suggestion changes

     File layout: Logging > Data > Builds > Suggestion > UI > Choice > Events > Slash.
     The ElvUI skin is in Skin.lua.
]]

local ADDON_NAME, ns = ...
local _, MY_CLASS = UnitClass("player") -- never changes, so looked up once
local db
local suggestion -- the talent currently suggested, nil when there is none
local lastLogged -- "tab:index" of the suggestion last reported in chat, so reopening the window stays quiet
local talentFrame -- PlayerTalentFrame, once the client has loaded the talent UI
local inCombat

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
local TAG = "|cff33ff99Sage|r"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version") or "?"
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage(TAG .. " " .. tostring(msg)) end
local function LogLoad(hint) Print("v" .. ADDON_VERSION .. " loaded." .. (hint and (" " .. hint) or "")) end
-- For changes the addon makes on its own; replies to commands use Print and are always shown.
local function Log(msg) if db.chatLog then Print(msg) end end

local function OnOff(v) return v and "|cff00ff00ON|r" or "|cffff0000OFF|r" end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local defaults = {
    enabled = true,
    chatLog = true, -- report a changed suggestion in chat, see Log
    builds = {}, -- the chosen build name per talent group (dual spec)
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Builds
---------------------------------------------------------------------------
-- The files in Builds\ add to ns.builds[CLASS], each { name = "Retribution", tab = 3, steps = {...} }.
-- A step is { "Talent name", firstLevel, lastLevel }: one point per level, so it is lastLevel -
-- firstLevel + 1 ranks. Talents are found by name in every tree, as builds may dip into another.
ns.builds = {}

local function FindBuild(name)
    for _, b in ipairs(ns.builds[MY_CLASS] or {}) do
        if strlower(b.name) == name then return b end
    end
end

local function Group() return GetActiveTalentGroup() or 1 end

-- The chosen build, else the one whose tree has the most points (the first on a fresh character).
local function ActiveBuild()
    local list = ns.builds[MY_CLASS]
    if not list then return nil end
    if db.builds[Group()] then
        local chosen = FindBuild(db.builds[Group()])
        if chosen then return chosen end
    end
    local best, bestPoints = list[1], -1
    for _, b in ipairs(list) do
        local _, _, points = GetTalentTabInfo(b.tab)
        if points > bestPoints then best, bestPoints = b, points end
    end
    return best
end

-- The first step of the build whose talent is below the rank the build wants by then.
local function FindBuildTalent(build)
    local byName = {}
    for tab = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(tab) do
            local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, i)
            if name then
                byName[name] = { tab = tab, index = i, name = name, icon = icon, tier = tier, column = column, rank = rank, maxRank = maxRank }
            end
        end
    end
    local wanted = {}
    for _, step in ipairs(build.steps) do
        local name, from, to = step[1], step[2], step[3]
        local talent = byName[name]
        if talent then -- a name the client does not know (other locale) is skipped, not an error
            local before = wanted[name] or 0
            wanted[name] = before + (to - from + 1)
            if talent.rank < wanted[name] then
                talent.build = build.name
                talent.level = from + max(talent.rank - before, 0) -- the level the build learns this rank at
                return talent
            end
        end
    end
end

---------------------------------------------------------------------------
-- Suggestion
---------------------------------------------------------------------------

-- Returns a table for the talent to learn next, or nil when there is nothing to spend or learn.
local function FindNextTalent()
    if (UnitCharacterPoints("player") or 0) <= 0 then return nil end

    local build = ActiveBuild()
    local fromBuild = build and FindBuildTalent(build)
    if fromBuild then return fromBuild end

    local tab, spent = 1, -1
    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        if points > spent then tab, spent = i, points end
    end

    local pick
    for i = 1, GetNumTalents(tab) do
        local name, icon, tier, column, rank, maxRank, _, meetsPrereq = GetTalentInfo(tab, i)
        -- a tier unlocks after 5 points in its tree per tier above it
        if name and rank < maxRank and meetsPrereq and spent >= (tier - 1) * 5
            and (not pick or tier < pick.tier or (tier == pick.tier and column < pick.column)) then
            pick = { tab = tab, index = i, name = name, icon = icon, tier = tier, column = column, rank = rank, maxRank = maxRank }
        end
    end
    return pick
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
-- The ElvUI skin lives in Skin.lua and is a no-op without ElvUI. A skin error must not break the addon.
local skinFailed
local function Skin(kind, ...)
    if not ns.Skin or skinFailed then return end
    local ok, err = pcall(ns.Skin, kind, ...)
    if not ok then
        skinFailed = true
        Print("skin failed: " .. tostring(err))
    end
end

-- The card sits below the talent window, see Place.
local PADDING = 8
local ICON_SIZE = 36
local frame = CreateFrame("Frame", "SageFrame", UIParent)
frame:SetSize(300, 100)
frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0, 0, 0, 0.8)
frame:Hide()

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetSize(ICON_SIZE, ICON_SIZE)
icon:SetPoint("TOPLEFT", PADDING, -PADDING)
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
title:SetPoint("RIGHT", -PADDING, 0)
title:SetJustifyH("LEFT")

local rankText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rankText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
rankText:SetPoint("RIGHT", -PADDING, 0)
rankText:SetJustifyH("LEFT")

local description = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -6)
description:SetJustifyH("LEFT")
description:SetJustifyV("TOP")

local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
footer:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -6)
footer:SetJustifyH("LEFT")

-- The description is not returned by GetTalentInfo, so it is read off the talent's tooltip.
local scanner = CreateFrame("GameTooltip", "SageScanner", nil, "GameTooltipTemplate")

local function Describe(tab, index)
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:SetTalent(tab, index)
    local lines = {}
    for i = 3, scanner:NumLines() do -- line 1 is the name, line 2 the rank
        local line = _G["SageScannerTextLeft" .. i]
        local text = line and line:GetText()
        if text == (TOOLTIP_TALENT_NEXT_RANK or "Next rank:") then
            lines = {} -- keep only what describes the rank about to be learned
        elseif text and text ~= "" and text ~= TOOLTIP_TALENT_LEARN and not text:find("^Requires") then
            lines[#lines + 1] = text
        end
    end
    return table.concat(lines, "\n")
end

-- Guidance is only offered with the talent window open and out of combat.
local function Available()
    return db.enabled and talentFrame and talentFrame:IsShown() and not inCombat
end

-- Clicking the card learns the suggested talent; the client's talent update event refreshes it.
frame:EnableMouse(true)
frame:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and suggestion and Available() then
        LearnTalent(suggestion.tab, suggestion.index)
    end
end)

-- The window's own frame is bigger than its visible panel: it reaches below it and past its right
-- edge, which the client marks with hit rect insets. The tab buttons sit right under the panel, so
-- the card hangs under the first tab and is as wide as the panel (the frame minus those insets).
local function Place()
    local left, right = talentFrame:GetHitRectInsets()
    local width = max(talentFrame:GetWidth() - (left or 0) - (right or 0), 240)
    local tab = _G["PlayerTalentFrameTab1"]
    frame:ClearAllPoints()
    if tab and tab:GetLeft() then
        frame:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, -6)
    else
        frame:SetPoint("TOPLEFT", talentFrame, "BOTTOMLEFT", left or 0, -6)
    end
    frame:SetWidth(width)
end

local function Refresh()
    suggestion = Available() and FindNextTalent() or nil
    if not suggestion then
        frame:Hide()
        return
    end
    Place()
    local width = frame:GetWidth() - 2 * PADDING
    local treeName = GetTalentTabInfo(suggestion.tab)

    icon:SetTexture(suggestion.icon)
    title:SetFormattedText("|cff33ff99Next to learn:|r |cffffd100%s|r", suggestion.name)
    rankText:SetFormattedText("Rank %d/%d  |cff888888%s, tier %d|r", suggestion.rank + 1, suggestion.maxRank, treeName, suggestion.tier)
    description:SetWidth(width)
    description:SetText(Describe(suggestion.tab, suggestion.index))
    footer:SetWidth(width)
    footer:SetText((suggestion.build and ("|cff888888Build: " .. suggestion.build .. ", learned at level " .. suggestion.level .. "|r\n") or "")
        .. "|cff00ff00Click to learn|r")

    local height = PADDING + ICON_SIZE + 6 + description:GetStringHeight() + 6 + footer:GetStringHeight() + PADDING
    frame:SetHeight(height)
    frame:Show()

    local key = suggestion.tab .. ":" .. suggestion.index
    if key ~= lastLogged then
        lastLogged = key
        Log("Next talent: |cffffd100" .. suggestion.name .. "|r (rank " .. (suggestion.rank + 1) .. "/" .. suggestion.maxRank .. ")")
    end
end

---------------------------------------------------------------------------
-- Choice: asks which build to follow
---------------------------------------------------------------------------
local MIN_LEVEL = 10 -- the first talent point
local dismissed -- closed without choosing; asked again after a talent reset or the next login
local hidingAuto -- the dialog is being closed by us (combat, window closed), which is not a dismissal
local lastSpent = {} -- points spent per talent group at the last check, to spot a reset

local CHOICE_PADDING = 14
local OPTION_W, OPTION_H, OPTION_GAP = 110, 78, 10
local OPTION_ICON = 40

local choice = CreateFrame("Frame", "SageChoice", UIParent)
choice:SetSize(260, 160)
choice:SetPoint("CENTER", 0, 150)
choice:SetFrameStrata("DIALOG")
choice:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
choice:SetBackdropColor(0, 0, 0, 0.9)
choice:Hide()
choice.options = {}
tinsert(UISpecialFrames, "SageChoice") -- Escape closes it
choice:SetScript("OnHide", function() if not hidingAuto then dismissed = true end end)

local title = choice:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -CHOICE_PADDING)
title:SetText("|cff33ff99Sage|r")

local subtitle = choice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
subtitle:SetText("Choose your specialization and I will guide your talents.")

choice.close = CreateFrame("Button", nil, choice, "UIPanelCloseButton")
choice.close:SetPoint("TOPRIGHT", -2, -2)

local function OnChoose(self)
    db.builds[Group()] = strlower(self.build)
    choice:Hide()
    Refresh()
    Print("build set to " .. self.build .. ".")
end

-- One option per build: a button with the tree's icon and the build name under it.
local function CreateOption()
    local option = CreateFrame("Button", nil, choice, "UIPanelButtonTemplate")
    option:SetSize(OPTION_W, OPTION_H)
    option:SetScript("OnClick", OnChoose)

    option.icon = option:CreateTexture(nil, "OVERLAY")
    option.icon:SetSize(OPTION_ICON, OPTION_ICON)
    option.icon:SetPoint("TOP", 0, -10)
    option.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    option.label = option:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    option.label:SetPoint("TOP", option.icon, "BOTTOM", 0, -8)
    option.label:SetWidth(OPTION_W - 8)
    return option
end

local function ShowChoice()
    local list = ns.builds[MY_CLASS]
    local width = #list * OPTION_W + (#list - 1) * OPTION_GAP
    for i, b in ipairs(list) do
        local option = choice.options[i]
        if not option then
            option = CreateOption()
            Skin("button", option)
            choice.options[i] = option
        end
        option.build = b.name
        option.icon:SetTexture(select(2, GetTalentTabInfo(b.tab)))
        option.label:SetText(b.name)
        option:ClearAllPoints()
        option:SetPoint("TOPLEFT", choice, "TOP", -width / 2 + (i - 1) * (OPTION_W + OPTION_GAP), -80)
        option:Show()
    end
    for i = #list + 1, #choice.options do choice.options[i]:Hide() end
    local dialogWidth = max(width, 340) + 2 * CHOICE_PADDING
    subtitle:SetWidth(dialogWidth - 2 * CHOICE_PADDING)
    choice:SetSize(dialogWidth, 80 + OPTION_H + CHOICE_PADDING)
    choice:Show()
end

local function HideChoice()
    if not choice:IsShown() then return end
    hidingAuto = true
    choice:Hide()
    hidingAuto = false
end

local function MaybeAsk()
    if dismissed or choice:IsShown() or not Available() then return end
    if not ns.builds[MY_CLASS] or UnitLevel("player") < MIN_LEVEL or db.builds[Group()] then return end
    ShowChoice()
end

-- A talent group that had points and now has none was reset (or swapped for an empty one):
-- forget its build so the player is asked again.
local function CheckReset()
    local group, total = Group(), 0
    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i)
        total = total + points
    end
    if lastSpent[group] and lastSpent[group] > 0 and total == 0 then
        db.builds[group] = nil
        dismissed = false
    end
    lastSpent[group] = total
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- The talent UI is load-on-demand: the client loads it the first time the window is opened.
local function Attach()
    if talentFrame or not PlayerTalentFrame then return end
    talentFrame = PlayerTalentFrame
    frame:SetParent(talentFrame)
    talentFrame:HookScript("OnShow", function()
        Refresh()
        MaybeAsk()
    end)
    talentFrame:HookScript("OnHide", function()
        Refresh()
        HideChoice()
    end)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            SageDB = SageDB or {}
            db = SageDB
            CopyDefaults(defaults, db)
        elseif arg1 == "Blizzard_TalentUI" then
            Attach()
        end
    elseif event == "PLAYER_LOGIN" then
        inCombat = UnitAffectingCombat("player")
        Attach()
        -- skinned at login, not at load: ElvUI finishes setting itself up first
        Skin("panel", frame)
        Skin("icon", icon)
        Skin("panel", choice)
        Skin("close", choice.close)
        CheckReset()
        Refresh()
        MaybeAsk()
        LogLoad("Open the talent window (N) for suggestions. /sage for commands.")
    else
        if event == "PLAYER_REGEN_DISABLED" then inCombat = true end
        if event == "PLAYER_REGEN_ENABLED" then inCombat = false end
        CheckReset()
        Refresh()
        if inCombat then HideChoice() else MaybeAsk() end
    end
end)

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
local function PrintStatus()
    local build = ActiveBuild()
    Print(OnOff(db.enabled) .. "  |  chat log " .. OnOff(db.chatLog) .. "  |  build: " .. (build and build.name or "none for your class"))
    local talent = FindNextTalent()
    if talent then
        Print("next talent: |cffffd100" .. talent.name .. "|r (rank " .. (talent.rank + 1) .. "/" .. talent.maxRank .. "), shown below the talent window out of combat.")
    else
        Print("no talent to suggest right now.")
    end
end

SLASH_SAGE1 = "/sage"
SlashCmdList["SAGE"] = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "on" or msg == "off" or msg == "toggle" then
        if msg == "toggle" then db.enabled = not db.enabled else db.enabled = (msg == "on") end
        Refresh()
        Print(db.enabled and "enabled." or "disabled.")
    elseif msg == "log" then
        db.chatLog = not db.chatLog
        Print("chat log " .. (db.chatLog and "on." or "off."))
    elseif msg == "build" or msg:find("^build ") then
        local list = ns.builds[MY_CLASS]
        local arg = strtrim(msg:sub(6))
        if not list then
            Print("no builds for your class yet.")
        elseif arg == "" then
            local names = {}
            for _, b in ipairs(list) do names[#names + 1] = b.name end
            Print("builds: " .. table.concat(names, ", ") .. ". Using " .. ActiveBuild().name .. ". /sage build <name> to pick one.")
        elseif FindBuild(arg) then
            db.builds[Group()] = arg
            Refresh()
            Print("build set to " .. FindBuild(arg).name .. ".")
        else
            Print("unknown build '" .. arg .. "'.")
        end
    elseif msg == "status" or msg == "" then
        PrintStatus()
        if msg == "" then Print("Usage: /sage on | off | build | log | status") end
    else
        Print("Usage: /sage on | off | build | log | status")
    end
end
