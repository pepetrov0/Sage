# Sage

![WoW 3.3.5a (WotLK)](https://img.shields.io/badge/WoW-3.3.5a%20WotLK-a335ee?style=flat-square)
![Version](https://img.shields.io/badge/version-0.1.0-6f42c1?style=flat-square)

[Features](#features) • [Installation](#installation) • [Usage](#usage) • [How it works](#how-it-works) • [Todo](#todo) • [FAQ](#faq)

The next talent to learn, always in sight.

**Sage** is a tiny World of Warcraft (WotLK 3.3.5) addon. With the talent window open, out of combat and with unspent talent points, a small frame below the window shows which talent to learn next. Hover it for the talent tooltip.

## Features

- 🎯 **Next talent at a glance**: icon, name and the rank you are about to learn
- 🔮 **Glyph recommendations**: once your talent points are spent and a glyph socket is empty, a second card shows the next glyph from your spec's priority list (Retribution, Holy and Protection paladin so far)
- 🪟 **Out of the way**: it only appears below the talent window, and never in combat
- 🧭 **Asks which build you want** at level 10 and after a talent reset, and remembers it per talent group (dual spec). Close it without picking and it asks again the next time you open the talent window, up to 3 times. Until you pick one, you go your own way (no suggestions)
- 🪶 **Featherweight**: a few small Lua files (the core, an optional ElvUI skin and the build data), no dependencies

## Installation

Sage targets the WoW 3.3.5a client (interface `30300`).

1. Put the addon files inside a `Sage` folder in `Interface/AddOns`.
2. Start the client and enable **Sage** in the AddOns list on the character selection screen (use `/reload` if you're already logged in).

## Usage

| Command | Description |
| --- | --- |
| `/sage` | Open the build dialog, if it did not come up by itself |

`/sg` is a short alias for `/sage`.

## How it works

1. It follows the leveling build you picked (in `Builds/`). It suggests the first step of the build you have not learned yet, skipping any step that cannot be learned right now.
2. Without a pick you go your own way: no suggestions. If you spend a point in a talent your build never takes (or more ranks than it takes), Sage switches you to your own way and tells you in a dialog. To follow a build again, reset your talents and Sage asks you again.
3. Without a build for your class, or once the build is done, it stays in the tree where you have spent the most points and takes the first talent that is not maxed, has its prerequisite learned and its tier unlocked (5 points per tier above it), top tier and leftmost column first.
4. It re-checks on level-up and whenever your talents change.

> [!NOTE]
> Builds exist only for paladins so far (see [Todo](#todo)). Other classes get the tree filled in order, which does not know which talents are good for your spec.

## Todo

Leveling builds and glyphs, by class and spec:

- [ ] Death Knight
  - [ ] Blood
  - [ ] Frost
  - [ ] Unholy
- [ ] Druid
  - [ ] Balance
  - [ ] Feral Combat
  - [ ] Restoration
- [ ] Hunter
  - [ ] Beast Mastery
  - [ ] Marksmanship
  - [ ] Survival
- [ ] Mage
  - [ ] Arcane
  - [ ] Fire
  - [ ] Frost
- [x] Paladin
  - [x] Holy
  - [x] Protection
  - [x] Retribution
- [ ] Priest
  - [ ] Discipline
  - [ ] Holy
  - [ ] Shadow
- [ ] Rogue
  - [ ] Assassination
  - [ ] Combat
  - [ ] Subtlety
- [ ] Shaman
  - [ ] Elemental
  - [ ] Enhancement
  - [ ] Restoration
- [ ] Warlock
  - [ ] Affliction
  - [ ] Demonology
  - [ ] Destruction
- [ ] Warrior
  - [ ] Arms
  - [ ] Fury
  - [ ] Protection

## FAQ

**Are settings shared between characters?**
No, they are saved per character in `SageDB`.
