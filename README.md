# ![logo](https://raw.githubusercontent.com/azerothcore/azerothcore.github.io/master/images/logo-github.png) AzerothCore Module: mod-eluna-racial-swap

[![AzerothCore Module](https://img.shields.io/badge/AzerothCore-Module-red?style=flat-square&logo=github)](https://github.com/azerothcore/azerothcore-wotlk)
[![Eluna Lua](https://img.shields.io/badge/Language-Eluna_Lua-000080?style=flat-square&logo=lua)](https://github.com/ElunaLuaEngine/Eluna)
[![Branch 3.3.5a](https://img.shields.io/badge/Branch-3.3.5a-orange?style=flat-square)](https://github.com/azerothcore/azerothcore-wotlk)
[![License MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/AlsoNotMehh/mod-eluna-racial-swap?style=flat-square&color=yellow&logo=github)](https://github.com/AlsoNotMehh/mod-eluna-racial-swap/stargazers)

An interactive, in-game racial trait selection system for **AzerothCore (WotLK 3.3.5a)** built with **Eluna + AIO**.

### 💡 Why this module?
In vanilla WotLK, players are forced to pick specific races solely for competitive racial perks (such as Every Man for Himself or Berserking), even if they prefer the visual aesthetics of a different race. Traditional custom racial systems required players to download and install custom client MPQ patches.

**`mod-eluna-racial-swap`** solves this without requiring any client MPQ patches. Using AIO, the server dynamically transmits a rich Blizzard-style interface to the client, allowing players to freely customize their racial setup across balanced categories.

## 📊 Feature Comparison

| Feature | MPQ Patch Systems | mod-eluna-racial-swap |
| :--- | :---: | :---: |
| **Client Patch Requirement** | ❌ Players must download and patch MPQ files | ✅ **Zero client patches required (served dynamically via AIO)** |
| **Interface Appearance** | ⚠️ Often custom or mismatched frames | ✅ **100% Authentic Blizzard UI frames and spellbook icons** |
| **Category Balance Gates** | ❌ Free-for-all trait stacking | ✅ **Structured slots: 1 Utility, 2 Passives, 1 Weapon, 1 Profession** |
| **Combat Protection** | ❌ Exploit swapping in combat | ✅ **Strict combat checks prevent in-fight modification** |
| **Database Persistence** | ⚠️ Fragile or custom core hooks | ✅ **Persisted into `character_racial_selection` and core spell tables** |

## ⚙️ Racial Categories & Allocation

Players can customize their racial loadout within strict balanced limits:
- **Active Utility (Select 1):** Every Man for Himself, Blood Fury, Stoneform, Shadowmeld, War Stomp, Will of the Forsaken, Arcane Torrent, Gift of the Naaru, Escape Artist, Berserking.
- **Passives (Select 2):** Quickness, Toughness, Hardiness, Endurance, The Human Spirit, Arcane Resistance, Shadow Resistance, Frost Resistance, Nature Resistance, Arcane Acuity, Diplomacy, etc.
- **Weapon Specializations (Select 1):** Sword/Mace Specialization, Axe Specialization, Bow/Gun Specialization, etc.
- **Profession Bonuses (Select 1):** Cultivation, Engineering Specialization, Gemcutting.

## 💬 In-Game Commands

- `/raciales` or `/rs` or `/racialswitch` - Opens the racial customization interface.

## 🛠️ Installation

1. Ensure your server has **Eluna** (or `mod-eluna`) and **AIO** installed.
2. Place `RacialSwapUI.lua` in your server's `lua_scripts/` folder.
3. Import `data/sql/db-characters/character_racial_selection.sql` into your `acore_characters` database.
4. Restart or reload Eluna scripts (`.eluna reload`).

## ⭐ Show your support

If you find this module helpful for your server, please consider giving it a star on GitHub! It helps more developers in the AzerothCore community discover the project.

## 🤝 Credits

- **Author:** [AlsoNotMehh](https://github.com/AlsoNotMehh) ([Discord](https://discord.com/users/1063304041419001966) / [Email](mailto:itsbrayanrodriguez@gmail.com))
- **Framework:** [AzerothCore](https://www.azerothcore.org) & [Eluna Lua Engine](https://github.com/ElunaLuaEngine/Eluna)

## 📜 License

This project is licensed under the [MIT License](LICENSE).
