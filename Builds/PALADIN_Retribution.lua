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
        { "Crusade", 30, 32 },
        { "Sanctity of Battle", 33, 35 },
        { "Sanctified Retribution", 36, 36 },
        { "Two-Handed Weapon Specialization", 37, 39 },
        { "Vengeance", 40, 42 },
        { "The Art of War", 43, 44 },
        { "Repentance", 45, 45 },
        { "Judgements of the Wise", 46, 48 },
        { "Fanaticism", 49, 51 },
        { "Sanctified Wrath", 52, 53 },
        { "Swift Retribution", 54, 56 },
        { "Crusader Strike", 57, 57 },
        { "Sheath of Light", 58, 60 },
        { "Righteous Vengeance", 61, 63 },
        { "Divine Storm", 64, 64 },
        { "Divine Strength", 65, 69 },
        { "Seals of the Pure", 70, 74 },
        { "Divine Intellect", 75, 79 },
        { "Aura Mastery", 80, 80 },
    },
})
