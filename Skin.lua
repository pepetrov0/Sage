-- ElvUI skin for Sage. Loaded after Sage.lua; does nothing without ElvUI.
if not ElvUI then return end

local _, ns = ...
local E = unpack(ElvUI)
local S = E and E:GetModule("Skins", true)
if not S then return end

-- kind is one of "panel", "icon", "button", "close"
function ns.Skin(kind, a)
    if kind == "panel" then -- a = frame
        a:SetTemplate("Transparent")
    elseif kind == "icon" then -- a = texture; crop the border ElvUI hides under its own
        a:SetTexCoord(unpack(E.TexCoords))
    elseif kind == "button" then -- a = UIPanelButtonTemplate button, with an optional .icon texture
        S:HandleButton(a)
        if a.icon then a.icon:SetTexCoord(unpack(E.TexCoords)) end
    elseif kind == "close" then -- a = UIPanelCloseButton
        S:HandleCloseButton(a)
    end
end
