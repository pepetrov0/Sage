--[[ Sage - next talent suggestion for WotLK 3.3.5
     While the talent window is open and you are out of combat, shows the
     talent to learn next in a card below it (name, rank, description), as
     long as you have unspent talent points. It follows the preset build for your class
     (Builds\CLASS_Spec.lua). Without one, or once the build is done, it stays
     in the tree where you have spent the most points and takes the first
     unlocked talent that is not maxed, top tier and leftmost column first.

     Once no talent point is left to spend, and a glyph socket is empty, it also shows a card for the next glyph
     from the active build's priority list (glyphs in Builds\CLASS_Spec.lua).

     At level 10 and above, with the talent window open and out of combat, it
     asks which build you want if you have not picked one, and asks again
     after you reset your talents. Dual spec: each talent group has its own pick, so switching
     groups follows that group's build, or asks (with the talent window open) if it has none.

     /sage status   show what it is doing
     /sage on|off   enable or disable
     /sage build    list the builds for your class, /sage build <name> picks one
     /sage log      toggle the chat message when the suggestion changes

     File layout: Logging > Data > Builds > Suggestion > UI > Glyphs > Choice > Events > Slash.
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

-- Stored as the build pick when the player wants no guidance at all.
local OWN_WAY = "own"
local function OwnWay() return db.builds[Group()] == OWN_WAY end

-- The chosen build, else the one whose tree has the most points (the first on a fresh character).
local function ActiveBuild()
    local list = ns.builds[MY_CLASS]
    if not list or OwnWay() then return nil end
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
    if (UnitCharacterPoints("player") or 0) <= 0 or OwnWay() then return nil end

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

-- The cards sit below the talent window, see PlaceCard.
local PADDING = 8
local ICON_SIZE = 36

local function NewCard(name)
    local card = CreateFrame("Frame", name, UIParent)
    card:SetSize(300, 100)
    card:SetPoint("TOP", UIParent, "TOP", 0, -120)
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0, 0, 0, 0.8)
    card:Hide()

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON_SIZE, ICON_SIZE)
    card.icon:SetPoint("TOPLEFT", PADDING, -PADDING)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, -2)
    card.title:SetPoint("RIGHT", -PADDING, 0)
    card.title:SetJustifyH("LEFT")

    card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.sub:SetPoint("RIGHT", -PADDING, 0)
    card.sub:SetJustifyH("LEFT")

    card.description = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.description:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -6)
    card.description:SetJustifyH("LEFT")
    card.description:SetJustifyV("TOP")

    card.footer = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.footer:SetPoint("TOPLEFT", card.description, "BOTTOMLEFT", 0, -6)
    card.footer:SetJustifyH("LEFT")
    return card
end

-- Fills a card and sizes it to fit; the width is set by PlaceCard.
local function FillCard(card, texture, titleText, subText, descriptionText, footerText)
    local width = card:GetWidth() - 2 * PADDING
    card.icon:SetTexture(texture)
    card.title:SetText(titleText)
    card.sub:SetText(subText)
    card.description:SetWidth(width)
    card.description:SetText(descriptionText)
    card.footer:SetWidth(width)
    card.footer:SetText(footerText)
    card:SetHeight(PADDING + ICON_SIZE + 6 + card.description:GetStringHeight() + 6 + card.footer:GetStringHeight() + PADDING)
    card:Show()
end

local frame = NewCard("SageFrame") -- the talent card
local icon = frame.icon
local glyphFrame = NewCard("SageGlyphFrame") -- the glyph card

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
-- a card hangs under the first tab (or under the card above it) and is as wide as the panel (the
-- frame minus those insets).
local function PlaceCard(card, above)
    local left, right = talentFrame:GetHitRectInsets()
    card:ClearAllPoints()
    if above then
        card:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -4)
    else
        local tab = _G["PlayerTalentFrameTab1"]
        if tab and tab:GetLeft() then
            card:SetPoint("TOPLEFT", tab, "BOTTOMLEFT", 0, -6)
        else
            card:SetPoint("TOPLEFT", talentFrame, "BOTTOMLEFT", left or 0, -6)
        end
    end
    card:SetWidth(max(talentFrame:GetWidth() - (left or 0) - (right or 0), 240))
end

---------------------------------------------------------------------------
-- Glyphs
---------------------------------------------------------------------------
-- A build can carry glyphs = { major = { names... }, minor = { names... } }, most wanted first, so
-- they follow the spec. A glyph is recommended whenever a socket of its kind is empty: the first one
-- on the list that is not socketed yet. Glyphs already socketed are never replaced.
local GLYPH_MAJOR, GLYPH_MINOR = GLYPHTYPE_MAJOR or 1, GLYPHTYPE_MINOR or 2
local glyphSuggestion
local lastLoggedGlyph

local function FindNextGlyph()
    local build = ActiveBuild()
    local list = build and build.glyphs
    if not list then return nil end

    local socketed, emptyKinds = {}, {}
    for socket = 1, GetNumGlyphSockets() do
        local enabled, kind, spellID = GetGlyphSocketInfo(socket, Group())
        if enabled then
            local name = spellID and GetSpellInfo(spellID) -- the glyph's spell is named like the glyph
            if name then socketed[name] = true elseif not spellID then emptyKinds[kind] = true end
        end
    end

    for _, kind in ipairs({ GLYPH_MAJOR, GLYPH_MINOR }) do
        local names = list[kind == GLYPH_MAJOR and "major" or "minor"] or {}
        if emptyKinds[kind] then
            for priority, name in ipairs(names) do
                if not socketed[name] then
                    return { name = name, major = (kind == GLYPH_MAJOR), priority = priority, total = #names }
                end
            end
        end
    end
end

-- The glyph's item link when it is in the bags, so the card can say whether it is at hand.
local function FindInBags(name)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and link:find("[" .. name .. "]", 1, true) then return link end
        end
    end
end

local function DescribeItem(link)
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:SetHyperlink(link)
    local lines = {}
    for i = 2, scanner:NumLines() do -- line 1 is the name
        local line = _G["SageScannerTextLeft" .. i]
        local text = line and line:GetText()
        if text and text ~= "" and not text:find("^Requires") then lines[#lines + 1] = text end
    end
    return table.concat(lines, "\n")
end

local function RefreshGlyphs()
    -- talents come first: glyphs are only offered once there is no talent point left to spend
    glyphSuggestion = Available() and (UnitCharacterPoints("player") or 0) <= 0 and FindNextGlyph() or nil
    if not glyphSuggestion then
        glyphFrame:Hide()
        return
    end
    local g = glyphSuggestion
    local kind = g.major and "Major" or "Minor"
    local link = FindInBags(g.name)
    local texture = link and select(10, GetItemInfo(link))
        or ("Interface\\Icons\\INV_Glyph_" .. kind .. strupper(MY_CLASS:sub(1, 1)) .. strlower(MY_CLASS:sub(2)))

    PlaceCard(glyphFrame, frame:IsShown() and frame or nil)
    FillCard(glyphFrame, texture,
        "|cff33ff99Next glyph:|r |cffffd100" .. g.name .. "|r",
        kind .. " glyph  |cff888888empty slot|r",
        link and DescribeItem(link) or "",
        "|cff888888Priority " .. g.priority .. " of " .. g.total .. "|r\n"
            .. (link and "|cff00ff00In your bags|r" or "|cffff4040Not in your bags|r"))

    if g.name ~= lastLoggedGlyph then
        lastLoggedGlyph = g.name
        Log("Next glyph: |cffffd100" .. g.name .. "|r (" .. strlower(kind) .. ")")
    end
end

local function Refresh()
    suggestion = Available() and FindNextTalent() or nil
    if not suggestion then
        frame:Hide()
    else
        PlaceCard(frame)
        FillCard(frame, suggestion.icon,
            "|cff33ff99Next to learn:|r |cffffd100" .. suggestion.name .. "|r",
            format("Rank %d/%d  |cff888888%s, tier %d|r", suggestion.rank + 1, suggestion.maxRank, GetTalentTabInfo(suggestion.tab), suggestion.tier),
            Describe(suggestion.tab, suggestion.index),
            (suggestion.build and ("|cff888888Build: " .. suggestion.build .. ", learned at level " .. suggestion.level .. "|r\n") or "")
                .. "|cff00ff00Click to learn|r")

        local key = suggestion.tab .. ":" .. suggestion.index
        if key ~= lastLogged then
            lastLogged = key
            Log("Next talent: |cffffd100" .. suggestion.name .. "|r (rank " .. (suggestion.rank + 1) .. "/" .. suggestion.maxRank .. ")")
        end
    end
    RefreshGlyphs() -- after the talent card, as it hangs under it
end

---------------------------------------------------------------------------
-- Choice: asks which build to follow
---------------------------------------------------------------------------
local MIN_LEVEL = 10 -- the first talent point
local dismissed = {} -- per talent group: closed without choosing; asked again after a talent reset or the next login
local hidingAuto -- the dialog is being closed by us (combat, window closed), which is not a dismissal
local lastSpent = {} -- points spent per talent group at the last check, to spot a reset
local lastGroup -- the talent group seen at the last check, to spot a dual spec switch
local askedGroup -- the talent group the open dialog is asking for

local CHOICE_PADDING = 14
local OPTION_W, OPTION_H, OPTION_GAP = 90, 90, 10
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
choice:SetScript("OnHide", function() if not hidingAuto and askedGroup then dismissed[askedGroup] = true end end)

local title = choice:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -CHOICE_PADDING)
title:SetText("|cff33ff99Sage|r")

local subtitle = choice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
subtitle:SetText("Choose your specialization and I will guide your talents, or go your own way.")

choice.close = CreateFrame("Button", nil, choice, "UIPanelCloseButton")
choice.close:SetPoint("TOPRIGHT", -2, -2)

local function OnChoose(self)
    db.builds[askedGroup or Group()] = self.value
    choice:Hide()
    Refresh()
    Print(self.value == OWN_WAY and "no suggestions, you go your own way." or ("build set to " .. self.build .. "."))
end

-- One option per build: a button with the tree's icon and the build name under it.
local function CreateOption()
    local option = CreateFrame("Button", nil, choice, "UIPanelButtonTemplate")
    option:SetSize(OPTION_W, OPTION_H)
    option:SetScript("OnClick", OnChoose)

    option.icon = option:CreateTexture(nil, "OVERLAY")
    option.icon:SetSize(OPTION_ICON, OPTION_ICON)
    option.icon:SetPoint("CENTER", 0, 10) -- icon and label together are centered in the button
    option.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    option.label = option:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    option.label:SetPoint("TOP", option.icon, "BOTTOM", 0, -6)
    option.label:SetJustifyH("CENTER")
    option.label:SetWidth(OPTION_W - 8)
    return option
end

local function ShowChoice()
    local list = {}
    for _, b in ipairs(ns.builds[MY_CLASS]) do
        list[#list + 1] = { name = b.name, value = strlower(b.name), texture = select(2, GetTalentTabInfo(b.tab)) }
    end
    list[#list + 1] = { name = "My own way", value = OWN_WAY, texture = "Interface\\Icons\\INV_Misc_Map_01" }
    local width = #list * OPTION_W + (#list - 1) * OPTION_GAP
    for i, b in ipairs(list) do
        local option = choice.options[i]
        if not option then
            option = CreateOption()
            Skin("button", option)
            choice.options[i] = option
        end
        option.build = b.name
        option.value = b.value
        option.icon:SetTexture(b.texture)
        option.label:SetText(b.name)
        option:ClearAllPoints()
        option:SetPoint("TOPLEFT", choice, "TOP", -width / 2 + (i - 1) * (OPTION_W + OPTION_GAP), -80)
        option:Show()
    end
    for i = #list + 1, #choice.options do choice.options[i]:Hide() end
    local dialogWidth = max(width, 340) + 2 * CHOICE_PADDING
    subtitle:SetWidth(dialogWidth - 2 * CHOICE_PADDING)
    choice:SetSize(dialogWidth, 80 + OPTION_H + CHOICE_PADDING)
    askedGroup = Group()
    choice:Show()
end

local function HideChoice()
    if not choice:IsShown() then return end
    hidingAuto = true
    choice:Hide()
    hidingAuto = false
end

local function MaybeAsk()
    if dismissed[Group()] or choice:IsShown() or not Available() then return end
    if not ns.builds[MY_CLASS] or UnitLevel("player") < MIN_LEVEL or db.builds[Group()] then return end
    ShowChoice()
end

-- A talent group that had points and now has none was reset: forget its build so the player is
-- asked again. Talent data can read as empty for a moment (zoning, a dual spec switch), so it only
-- counts when every point the character has earned (one per level from 10) is unspent again.
local function CheckReset()
    local group, total = Group(), 0
    for i = 1, GetNumTalentTabs() do
        local _, _, points = GetTalentTabInfo(i, false, false, group)
        total = total + (points or 0)
    end
    local allUnspent = (UnitCharacterPoints("player") or 0) >= UnitLevel("player") - 9
    if lastSpent[group] and lastSpent[group] > 0 and total == 0 and allUnspent then
        db.builds[group] = nil
        dismissed[group] = false
    end
    if total > 0 or allUnspent then lastSpent[group] = total end
end

-- A dual spec switch: the dialog asked for the other group, so it goes; the new group's build is
-- announced, or it is asked for (MaybeAsk, after this).
local function CheckGroup()
    local group = Group()
    if group == lastGroup then return end
    local first = lastGroup == nil
    lastGroup = group
    if first then return end -- login, nothing was switched
    HideChoice()
    local pick = db.builds[group]
    local build = pick and pick ~= OWN_WAY and FindBuild(pick)
    Log("talent group " .. group .. ": " .. (pick == OWN_WAY and "your own way, no suggestions"
        or build and ("build " .. build.name) or "no build chosen yet"))
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
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("GLYPH_ADDED")
frame:RegisterEvent("GLYPH_REMOVED")
frame:RegisterEvent("GLYPH_UPDATED")
frame:RegisterEvent("BAG_UPDATE")
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
        Skin("panel", glyphFrame)
        Skin("icon", glyphFrame.icon)
        Skin("panel", choice)
        Skin("close", choice.close)
        CheckGroup()
        CheckReset()
        Refresh()
        MaybeAsk()
        LogLoad("Open the talent window (N) for suggestions. /sage for commands.")
    elseif event == "BAG_UPDATE" or event:find("^GLYPH_") then
        Refresh()
    else
        if event == "PLAYER_REGEN_DISABLED" then inCombat = true end
        if event == "PLAYER_REGEN_ENABLED" then inCombat = false end
        CheckGroup()
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
    Print(OnOff(db.enabled) .. "  |  chat log " .. OnOff(db.chatLog) .. "  |  build: " .. (OwnWay() and "your own way, no suggestions" or build and build.name or "none for your class"))
    local talent = FindNextTalent()
    if talent then
        Print("next talent: |cffffd100" .. talent.name .. "|r (rank " .. (talent.rank + 1) .. "/" .. talent.maxRank .. "), shown below the talent window out of combat.")
    else
        Print("no talent to suggest right now.")
    end
    local glyph = (UnitCharacterPoints("player") or 0) <= 0 and FindNextGlyph()
    if glyph then
        Print("next glyph: |cffffd100" .. glyph.name .. "|r (" .. (glyph.major and "major" or "minor") .. ").")
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
            Print("builds: " .. table.concat(names, ", ") .. ", own. Using " .. (ActiveBuild() and ActiveBuild().name or "none (own way)") .. ". /sage build <name> to pick one.")
        elseif arg == OWN_WAY then
            db.builds[Group()] = OWN_WAY
            Refresh()
            Print("no suggestions, you go your own way.")
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
