# Sage

![WoW 3.3.5a (WotLK)](https://img.shields.io/badge/WoW-3.3.5a%20WotLK-a335ee?style=flat-square)
![Version](https://img.shields.io/badge/version-0.1.0-6f42c1?style=flat-square)

[Features](#features) • [Installation](#installation) • [Usage](#usage) • [How it works](#how-it-works) • [FAQ](#faq)

The next talent to learn, always in sight.

**Sage** is a tiny World of Warcraft (WotLK 3.3.5) addon. With the talent window open, out of combat and with unspent talent points, a small frame below the window shows which talent to learn next. Hover it for the talent tooltip.

## Features

- 🎯 **Next talent at a glance**: icon, name and the rank you are about to learn
- 🔮 **Glyph recommendations**: once your talent points are spent and a glyph socket is empty, a second card shows the next glyph from your spec's priority list (Retribution and Holy paladin so far)
- 🔔 **Chat message when the suggestion changes**, which you can turn off with `/sage log`
- 🪟 **Out of the way**: it only appears below the talent window, and never in combat
- 🧭 **Asks which build you want** at level 10 and after a talent reset
- 🪶 **Featherweight**: one Lua file, no dependencies

## Installation

Sage targets the WoW 3.3.5a client (interface `30300`).

1. Put the addon files inside a `Sage` folder in `Interface/AddOns`.
2. Start the client and enable **Sage** in the AddOns list on the character selection screen (use `/reload` if you're already logged in).

## Usage

| Command | Description |
| --- | --- |
| `/sage on` / `off` / `toggle` | Enable or disable the suggestion |
| `/sage build [name]` | List the builds for your class, or pick one |
| `/sage log` | Toggle the chat message when the suggestion changes |
| `/sage status` | Show whether it is on and what it suggests now |

## How it works

1. It stays in the talent tree where you have spent the most points (the first tree on a fresh character).
2. In that tree it takes the first talent that is not maxed, has its prerequisite learned and its tier unlocked (5 points per tier above it), top tier and leftmost column first.
3. It re-checks on level-up and whenever your talents change.

> [!NOTE]
> This fills the tree in order. It does not know which talents are good for your spec yet.

## FAQ

**Are settings shared between characters?**
No, they are saved per character in `SageDB`.
