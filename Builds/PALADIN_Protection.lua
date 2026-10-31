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
        { "Crusade", 25, 27 },
        { "Divine Strength", 28, 32 },
        { "Anticipation", 33, 37 },
        { "Toughness", 38, 42 },
        { "Improved Righteous Fury", 43, 45 },
        { "Divine Sacrifice", 46, 46 },
        { "Divine Guardian", 47, 48 },
        { "Improved Devotion Aura", 49, 51 },
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
