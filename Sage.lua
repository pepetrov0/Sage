--[[ Sage - next talent suggestion for WotLK 3.3.5
     While the talent window is open and you are out of combat, shows the
     talent to learn next in a card below it (name, rank, description), as
     long as you have unspent talent points. It follows the build you picked for your class
     (Builds\CLASS_Spec.lua). Without a pick you go your own way (no suggestions), and spending a
     point the build never takes switches you to your own way too. A class with no builds yet,
     or a finished build, gets the tree where you have spent the most points filled in order:
     the first unlocked talent that is not maxed, top tier and leftmost column first.

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
     /sage check    check the builds of your class against the talent trees

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
local talentsReady -- set on the first PLAYER_TALENT_UPDATE (or a while after login): before it, talent data can read wrong

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
        b.key = b.key or strlower(b.name) -- cached, as this runs several times per refresh
        if b.key == name then return b end
    end
end

local function Group() return GetActiveTalentGroup() or 1 end

-- Stored as the build pick when the player wants no guidance at all.
local OWN_WAY = "own"

-- The saved pick of the active group. A pick naming a build that no longer exists is forgotten, so
-- the player is asked again.
local function Pick()
    local group = Group()
    local pick = db.builds[group]
    if pick and pick ~= OWN_WAY and not FindBuild(pick) then
        db.builds[group] = nil
        return nil
    end
    return pick
end

-- No guidance: the player picked their own way, or has not picked a build of their class (the default).
local function OwnWay()
    local pick = Pick()
    return pick == OWN_WAY or (pick == nil and ns.builds[MY_CLASS] ~= nil)
end

-- The picked build, nil when there is none.
local function ActiveBuild()
    local pick = Pick()
    return pick and pick ~= OWN_WAY and FindBuild(pick) or nil
end

-- Talent name -> { tab, index, tier, column, maxRank, icon }. None of it changes for a class, so it
-- is built once. Talent data can read empty right after login: a partial index is returned but not
-- kept, so the next call tries again.
local talentIndex
local function TalentIndex()
    if talentIndex then return talentIndex end
    local index, complete = {}, GetNumTalentTabs() > 0
    for tab = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(tab) do
            local name, icon, tier, column, _, maxRank = GetTalentInfo(tab, i)
            if name then
                index[name] = { tab = tab, index = i, tier = tier, column = column, maxRank = maxRank, icon = icon }
            else
                complete = false
            end
        end
    end
    if complete then talentIndex = index end
    return index
end

-- The first step of the build whose talent is below the rank the build wants by then and can be
-- learned now (not maxed, prerequisite learned, tier unlocked). Others are skipped, so a step that
-- cannot be learned does not hold up the rest of the build.
local function FindBuildTalent(build)
    local group, index = Group(), TalentIndex()
    local spent = {}
    for tab = 1, GetNumTalentTabs() do
        spent[tab] = select(3, GetTalentTabInfo(tab, false, false, group)) or 0
    end
    local wanted = {}
    for _, step in ipairs(build.steps) do
        local name, from, to = step[1], step[2], step[3]
        local t = index[name]
        if t then -- a name the client does not know (other locale) is skipped, not an error
            local before = wanted[name] or 0
            wanted[name] = before + (to - from + 1)
            -- only the rank and prerequisite change, so only they are read live
            local _, _, _, _, rank, _, _, meetsPrereq = GetTalentInfo(t.tab, t.index, false, false, group)
            if rank and rank < wanted[name] and rank < t.maxRank and meetsPrereq
                and (spent[t.tab] or 0) >= (t.tier - 1) * 5 then
                -- a fresh table, so the cached index entry is never handed out or changed
                return { tab = t.tab, index = t.index, name = name, icon = t.icon, tier = t.tier, column = t.column,
                    rank = rank, maxRank = t.maxRank, meetsPrereq = meetsPrereq, build = build.name,
                    level = from + max(rank - before, 0) } -- the level the build learns this rank at
            end
        end
    end
end

-- The first talent with more points than the build ever takes, nil when there is none. When the
-- client knows none of the build's talent names (other locale), it cannot tell, so it says nil.
local function Deviation(build)
    local planned = build.planned -- name -> total ranks; build files load later, so it is made on first use
    if not planned then
        planned = {}
        for _, step in ipairs(build.steps) do planned[step[1]] = (planned[step[1]] or 0) + (step[3] - step[2] + 1) end
        build.planned = planned
    end
    local group, known, off = Group(), false, nil
    for tab = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(tab) do
            local name, _, _, _, rank = GetTalentInfo(tab, i, false, false, group)
            if name then
                if planned[name] then known = true end
                if not off and rank > (planned[name] or 0) then off = name end
            end
        end
    end
    return known and off or nil
end

-- A player who spends a point the picked build never takes goes their own way from then on.
local function CheckDeviation()
    local build = talentsReady and ActiveBuild()
    local off = build and Deviation(build)
    if not off then return end
    db.builds[Group()] = OWN_WAY
    Print(off .. " is not in the " .. build.name .. " build, so you go your own way now. /sage build <name> follows a build again.")
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
frame:SetScript("OnEnter", function(self)
    if not suggestion then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetTalent(suggestion.tab, suggestion.index, false, false, Group())
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

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

-- Bags change in bursts (one BAG_UPDATE per bag), and only the shown glyph card cares, so this
-- rescans them once, on the next frame, and then hides itself.
local bagTimer = CreateFrame("Frame")
bagTimer:Hide()
bagTimer:SetScript("OnUpdate", function(self)
    self:Hide()
    RefreshGlyphs()
end)

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
    if GameTooltip:IsOwned(frame) then -- the tooltip under the cursor follows the card
        if suggestion then frame:GetScript("OnEnter")(frame) else GameTooltip:Hide() end
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

local function HideChoice()
    if not choice:IsShown() then return end
    hidingAuto = true
    choice:Hide()
    hidingAuto = false
end

local function OnChoose(self)
    db.builds[askedGroup or Group()] = self.value
    HideChoice() -- a pick, not a dismissal
    Print(self.value == OWN_WAY and "no suggestions, you go your own way." or ("build set to " .. self.build .. "."))
    CheckDeviation()
    Refresh()
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

local function MaybeAsk()
    if dismissed[Group()] or choice:IsShown() or not Available() then return end
    if not ns.builds[MY_CLASS] or UnitLevel("player") < MIN_LEVEL or Pick() then return end
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
        or build and ("build " .. build.name) or "no build chosen yet, your own way"))
end

-- Run whenever talents may have changed, once talent data can be trusted.
local function CheckTalents()
    CheckGroup()
    CheckReset()
    CheckDeviation()
end

-- PLAYER_TALENT_UPDATE normally comes right after login. If it never does, the checks start anyway
-- this many seconds after login, so switches and resets are still noticed.
local READY_FALLBACK = 5
local readyTimer = CreateFrame("Frame")
readyTimer:Hide()
readyTimer:SetScript("OnUpdate", function(self, elapsed)
    self.left = self.left - elapsed
    if self.left > 0 then return end
    self:Hide()
    if talentsReady then return end
    talentsReady = true
    CheckTalents() -- the first run sets the baseline: lastGroup and lastSpent
    Refresh()
    if not inCombat then MaybeAsk() end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- The talent UI is load-on-demand: the client loads it the first time the window is opened.
local function Attach()
    if talentFrame or not PlayerTalentFrame then return end
    talentFrame = PlayerTalentFrame
    frame:SetParent(talentFrame)
    glyphFrame:SetParent(talentFrame) -- both cards take the window's strata and level and hide with it
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
local GLYPH_EVENTS = { GLYPH_ADDED = true, GLYPH_REMOVED = true, GLYPH_UPDATED = true }
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
        Refresh()
        MaybeAsk()
        readyTimer.left = READY_FALLBACK
        readyTimer:Show()
        LogLoad("Open the talent window (N) for suggestions. /sage for commands.")
    elseif event == "BAG_UPDATE" then
        if glyphFrame:IsShown() then bagTimer:Show() end -- see bagTimer
    elseif GLYPH_EVENTS[event] then
        Refresh()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        -- combat cannot change talents, so no talent scan here
        inCombat = (event == "PLAYER_REGEN_DISABLED")
        Refresh()
        if inCombat then HideChoice() else MaybeAsk() end
    else
        if event == "PLAYER_TALENT_UPDATE" then talentsReady = true end
        if talentsReady then CheckTalents() end -- the first run sets the baseline: lastGroup and lastSpent
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

-- Replays every build of the class one point per level, as the client would learn it, and reports
-- the steps it would refuse: unknown names, too many ranks, a locked tier or a missing prerequisite
-- (talents need their prerequisite maxed), and levels that do not run from 10 to 80 one point each.
local MAX_LEVEL = 80
local function CheckBuilds()
    local list = ns.builds[MY_CLASS]
    if not list then return Print("no builds for your class yet.") end
    local byName, byPos = {}, {}
    for name, entry in pairs(TalentIndex()) do
        -- copied, so the cached index entries are not changed
        local t = { tab = entry.tab, index = entry.index, tier = entry.tier, maxRank = entry.maxRank, name = name }
        byName[name], byPos[t.tab .. ":" .. t.tier .. ":" .. entry.column] = t, t
    end
    for _, build in ipairs(list) do
        local problems, rank, spent, level = {}, {}, {}, MIN_LEVEL
        for n, step in ipairs(build.steps) do
            local name, from, to = step[1], step[2], step[3]
            local problem
            if from ~= level or to < from then
                problem = format("levels %d-%d, expected to start at %d", from, to, level)
            end
            level = max(to, from) + 1
            local t = byName[name]
            if not t then
                problem = problem or "not a talent of your class (or another locale)"
            else
                local pTier, pColumn = GetTalentPrereqs(t.tab, t.index)
                local prereq = pTier and byPos[t.tab .. ":" .. pTier .. ":" .. pColumn]
                for lvl = from, to do
                    local r = rank[name] or 0
                    if r >= t.maxRank then
                        problem = problem or format("more than %d ranks at level %d", t.maxRank, lvl)
                    elseif (spent[t.tab] or 0) < (t.tier - 1) * 5 then
                        problem = problem or format("tier %d is still locked at level %d (%d points in its tree)", t.tier, lvl, spent[t.tab] or 0)
                    elseif prereq and (rank[prereq.name] or 0) < prereq.maxRank then
                        problem = problem or format("needs %s maxed first (level %d)", prereq.name, lvl)
                    end
                    rank[name] = r + 1 -- counted anyway, so one bad step does not flag every later one
                    spent[t.tab] = (spent[t.tab] or 0) + 1
                end
            end
            if problem then problems[#problems + 1] = format("  step %d, %s: %s", n, name, problem) end
        end
        if level - 1 ~= MAX_LEVEL then
            problems[#problems + 1] = format("  ends at level %d, expected %d", level - 1, MAX_LEVEL)
        end
        if #problems == 0 then
            Print(build.name .. ": |cff00ff00ok|r")
        else
            Print(build.name .. ": |cffff4040" .. #problems .. " problem" .. (#problems > 1 and "s" or "") .. "|r")
            for _, p in ipairs(problems) do Print(p) end
        end
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
            Print("build set to " .. FindBuild(arg).name .. ".")
            CheckDeviation()
            Refresh()
        else
            Print("unknown build '" .. arg .. "'.")
        end
    elseif msg == "check" then
        CheckBuilds()
    elseif msg == "status" or msg == "" then
        PrintStatus()
        if msg == "" then Print("Usage: /sage on | off | build | log | check | status") end
    else
        Print("Usage: /sage on | off | build | log | check | status")
    end
end
