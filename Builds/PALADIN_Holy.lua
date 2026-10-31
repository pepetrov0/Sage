local ADDON_NAME, ns = ...

-- Holy paladin leveling build and glyphs. The talent steps run from level 10 (the first talent
-- point) to 80; the Protection talents are found by name, so that is fine.

ns.builds.PALADIN = ns.builds.PALADIN or {}
table.insert(ns.builds.PALADIN, {
    name = "Holy",
    tab = 1,
    -- most wanted first
    glyphs = {
        major = { "Glyph of Holy Light", "Glyph of Seal of Wisdom", "Glyph of Beacon of Light" },
        minor = { "Glyph of Blessing of Kings", "Glyph of Sense Undead", "Glyph of Lay on Hands" },
    },
    steps = {
        { "Spiritual Focus", 10, 14 },
        { "Healing Light", 15, 17 },
        { "Divine Intellect", 18, 22 },
        { "Illumination", 23, 27 },
        { "Aura Mastery", 28, 28 },
        { "Improved Lay on Hands", 29, 29 },
        { "Blessed Hands", 30, 31 },
        { "Sanctified Light", 32, 34 },
        { "Divine Favor", 35, 35 },
        { "Holy Power", 36, 40 },
        { "Holy Shock", 41, 41 },
        { "Light's Grace", 42, 44 },
        { "Holy Guidance", 45, 49 },
        { "Judgements of the Pure", 50, 54 },
        { "Divine Illumination", 55, 55 },
        { "Infusion of Light", 56, 57 },
        { "Enlightened Judgements", 58, 59 },
        { "Beacon of Light", 60, 60 },
        { "Divinity", 61, 65 },
        { "Anticipation", 66, 68 },
        { "Guardian's Favor", 69, 70 },
        { "Toughness", 71, 71 },
        { "Divine Sacrifice", 72, 72 },
        { "Benediction", 73, 75 },
        { "Anticipation", 76, 77 },
        { "Toughness", 78, 78 },
        { "Divine Guardian", 79, 80 },
    },
})
