<img width="1496" height="1007" alt="{40D71B7B-A69F-4280-B040-76FE4AF16678}" src="https://github.com/user-attachments/assets/3b60f512-3fa2-4c89-beda-5b9f1931d67e" />

A small companion add-on for **EllesmereUI** on **WoW Forever**. It fixes the account-wide gold tracking so characters that share a first name stop overwriting each other.

## The problem

On WoW Forever every character has a first name **and** a surname. EllesmereUI's gold ledger, which drives the gold tooltip in **Bags** and the **Gold** block on the Data Bars, stores each character under `FirstName-Realm`. Two characters with the same first name on one realm, for example *Aria Stone* and *Aria Vale*, end up in the same slot. Each time one of them logs in, it overwrites the other's gold, so the tooltip and the total are wrong.

## What this add-on does

- Stores each character under `FirstName LastName-Realm` on WoW Forever, so every character keeps its own entry.
- Removes the old first-name-only entry when the character next logs in. That entry can't be trusted, because it may hold another character's gold.
- Lets you choose how names are shown in **both** gold tooltips (Bags and Data Bars): first name, last name, or full name.
- Changes no EllesmereUI file. It patches the shared gold ledger at runtime, so **EllesmereUI updates do not undo the fix**.

On retail (no surnames) the add-on changes nothing.

## Installation

1. Download this repository and put the `EllesmereUI_GoldNames` folder into your add-ons folder:
   `World of Warcraft\_classic_beta_\Interface\AddOns\`
   (or the `Interface\AddOns` folder of whichever client you play).
2. **Fully restart the game.** A `/reload` isn't enough for a newly added add-on folder.
3. Make sure **EllesmereUI Gold Names** is enabled in the add-on list on the character screen.

Requires **EllesmereUI** (the add-on declares it as a dependency).

## Usage

| Command | Effect |
|---|---|
| `/goldnames` | Shows whether the fix is active and the key the current character is stored under |
| `/goldnames first` | Show first names in the gold tooltips (default) |
| `/goldnames last` | Show last names |
| `/goldnames full` | Show first and last names |

The setting is account-wide and saved in `EllesmereUI_GoldNamesDB`.

**After installing:** log in with each character once so it's saved under its full-name key. Until then, a character keeps its old first-name entry, and if two characters share a first name only one of them shows up.

## Compatibility

- Built for **EllesmereUI 9.5.4** on WoW Forever (interface 16001). The `.toc` also lists the retail interface versions EllesmereUI supports.
- It depends on EllesmereUI's shared gold ledger (`EllesmereUI.GetGoldLedger()`). If a future EllesmereUI version renames or removes it, this add-on does nothing and prints one notice in chat after login, without causing errors.
- If you turn off **Gold Tracking and History** (EllesmereUI options: Bags), nothing is recorded, with or without this add-on.

## Files

```
EllesmereUI_GoldNames/
├── EllesmereUI_GoldNames.toc
├── GoldNames.lua
└── README.md
```

## How it works (for developers)

EllesmereUI 9.5.4 keeps all gold data in one shared table returned by `EllesmereUI.GetGoldLedger()`. Bags and the Data Bars look up its functions every time they call them, so replacing a function on that table takes effect everywhere:

- `GL.CharKey()` returns `"First Last-Realm"` when the client is WoW Forever (`EllesmereUI.IS_FOREVER`) and `UnitNameUnmodified("player")` returns a surname.
- `GL.RecordCharacter()` is wrapped. After the original write, the entry also gets `firstName`, `surname` and a display `name` in the chosen format, and the legacy `First-Realm` entry is deleted.
- The Data Bars tooltip already prints `entry.name`. The Bags tooltip prints the key without the realm, so its name lines are rewritten after it lays out, and the frame is narrowed to fit.

## Disclaimer

This is an unofficial fan-made add-on. It isn't affiliated with or supported by the EllesmereUI author. Please report problems with it here, not to EllesmereUI.
