local ADDON_NAME, ns = ...

-- Retribution paladin leveling build and glyphs. The talent steps run from level 10 (the first talent
-- point) to 80; the last four are Holy talents, which are found by name, so that is fine.

ns.builds.PALADIN = ns.builds.PALADIN or {}
table.insert(ns.builds.PALADIN, {
    name = "Retribution",
    tab = 3,
    -- most wanted first
    glyphs = {
        major = { "Glyph of Judgement", "Glyph of Exorcism", "Glyph of Seal of Vengeance" },
        minor = { "Glyph of Blessing of Kings", "Glyph of Sense Undead", "Glyph of Lay on Hands" },
    },
    steps = {
        { "Benediction", 10, 14 },
        { "Improved Blessing of Might", 15, 16 },
        { "Heart of the Crusader", 17, 19 },
        { "Improved Judgements", 20, 21 },
        { "Conviction", 22, 26 },
        { "Seal of Command", 27, 27 },
        { "Pursuit of Justice", 28, 29 },
        { "Vindication", 30, 31 },
        { "Crusade", 32, 34 },
        { "Sanctity of Battle", 35, 37 },
        { "Sanctified Retribution", 38, 38 },
        { "Two-Handed Weapon Specialization", 39, 41 },
        { "Vengeance", 42, 44 },
        { "The Art of War", 45, 46 },
        { "Repentance", 47, 47 },
        { "Judgements of the Wise", 48, 50 },
        { "Fanaticism", 51, 53 },
        { "Sanctified Wrath", 54, 55 },
        { "Crusader Strike", 56, 56 },
        { "Sheath of Light", 57, 59 },
        { "Righteous Vengeance", 60, 62 },
        { "Divine Storm", 63, 63 },
        { "Divine Strength", 64, 68 },
        { "Seals of the Pure", 69, 73 },
        { "Divine Intellect", 74, 78 },
        { "Aura Mastery", 79, 79 },
        { "Improved Lay on Hands", 80, 80 },
    },
})
