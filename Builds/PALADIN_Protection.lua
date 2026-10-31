local ADDON_NAME, ns = ...

-- Protection paladin leveling build and glyphs. The talent steps run from level 10 (the first talent
-- point) to 80; the first seven are Retribution talents, which are found by name, so that is fine.

ns.builds.PALADIN = ns.builds.PALADIN or {}
table.insert(ns.builds.PALADIN, {
    name = "Protection",
    tab = 2,
    -- most wanted first
    glyphs = {
        major = { "Glyph of Righteous Defense", "Glyph of Seal of Vengeance", "Glyph of Divine Plea" },
        minor = { "Glyph of Blessing of Kings", "Glyph of Sense Undead", "Glyph of Lay on Hands" },
    },
    steps = {
        { "Deflection", 10, 14 },
        { "Improved Judgements", 15, 16 },
        { "Heart of the Crusader", 17, 19 },
        { "Vindication", 20, 21 },
        { "Seal of Command", 22, 22 },
        { "Pursuit of Justice", 23, 24 },
        { "Crusade", 25, 25 },
        { "Divine Strength", 26, 30 },
        { "Anticipation", 31, 35 },
        { "Toughness", 36, 40 },
        { "Improved Righteous Fury", 41, 43 },
        { "Divine Sacrifice", 44, 44 },
        { "Divine Guardian", 45, 46 },
        { "Improved Devotion Aura", 47, 49 },
        { "Improved Hammer of Justice", 50, 51 },
        { "Blessing of Sanctuary", 52, 52 },
        { "One-Handed Weapon Specialization", 53, 55 },
        { "Sacred Duty", 56, 57 },
        { "Holy Shield", 58, 58 },
        { "Spiritual Attunement", 59, 59 },
        { "Ardent Defender", 60, 62 },
        { "Combat Expertise", 63, 65 },
        { "Redoubt", 66, 68 },
        { "Touched by the Light", 69, 71 },
        { "Avenger's Shield", 72, 72 },
        { "Guarded by the Light", 73, 74 },
        { "Judgements of the Just", 75, 76 },
        { "Shield of the Templar", 77, 79 },
        { "Hammer of the Righteous", 80, 80 },
    },
})
