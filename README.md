# Footsteps

Footsteps keeps a journal of your character's journey through World of Warcraft: Forever. Each milestone gets an entry with its date, place, level and time played. Most milestones also get a screenshot, with a caption saying what happened, who, where and when. Type `/footsteps` to open the journal.

## What it records

- **Levels**, and how long you spent on the one before
- **Achievements**, including the Legacy points they earned
- **The first kill of each boss**, and the dungeon it was in
- **First visits** to zones and dungeons
- **Duels**, won or lost, and who they were against
- **Battlegrounds**, and whether you won, lost or drew
- **New pets and new mounts**, with your first mount marked
- **Deaths**

Everything is recorded by default. Each milestone is also said in one line in chat.

## Screenshots

Each kind of milestone takes a screenshot a moment after it happens, except deaths, which take one only if you turn that on.

Most screenshots hide the interface to show your character and the world. It's kept for level-ups, achievements and battlegrounds, so the picture shows the new level, the achievement or the scoreboard. The interface always comes back afterwards, even if the screenshot fails or a fight starts.

Footsteps doesn't hide the interface while you're typing, while a window such as a vendor, the mailbox, the bank, the auction house, a trade or the flight map is open, or while a group or guild invite is waiting. Hiding it then would close the window or decline the invite, so that picture keeps the interface.

A caption in the bottom-right corner says what the picture shows: the milestone, your character's name and level, the place and the date. The game names screenshot files itself and an addon can't rename them, so the caption is how you tell your screenshots apart. It's in the picture only, never on your screen afterwards, and a setting turns it off.

## The journal

`/footsteps`, the minimap button or the Footsteps entry in the addon menu by the minimap opens the journal: every entry, newest first, with a filter for which kinds are listed. Hover over an entry for more about it, or click it to see everything it holds:

- **The screenshot's file name**, to copy with Ctrl+C. An addon can't open files, so the journal doesn't show the picture itself. Find it in your Screenshots folder by that name. The time in the name is worked out from the clock, so it can be a second off.
- **A note** of your own, up to 500 characters, saved as you type.
- **Hide**, which takes an entry out of the list. Tick "Show hidden" to see hidden entries and restore them. Nothing is ever erased.

## Settings

In the game's Settings, Footsteps is under AddOns. Each character has its own:

- for each kind of milestone, whether it's recorded and whether it takes a screenshot
- whether screenshots hide the interface
- whether screenshots have a caption
- whether milestones are said in chat
- whether the minimap button shows

On the minimap button or the addon menu entry, a left-click opens or closes the journal and a right-click opens the settings. The minimap button can be dragged around the minimap.

## Commands

| Command | Does |
| --- | --- |
| `/footsteps` or `/steps` | Open or close the journal |
| `/footsteps list` | Your last 10 entries in chat |
| `/footsteps list 25` | Your last 25 entries, up to 50 |
| `/footsteps options` | Open the settings |
| `/footsteps record duel off` | Stop recording duels; `on` starts again |
| `/footsteps shots visit off` | No screenshots of first visits; `on` again |
| `/footsteps hideui off` | Keep the interface in screenshots |
| `/footsteps caption off` | No caption in screenshots |
| `/footsteps help` | List the commands |

In place of `duel` or `visit`, use any of `level`, `achievement`, `boss`, `visit`, `death`, `duel`, `battleground`, `pet` or `mount`. On their own, `/footsteps record` and `/footsteps shots` say what each kind is set to.

## An early release

Footsteps was built during Forever's beta. So far it has been seen in the game only taking a screenshot at a new level. Everything else, from the other milestones, the lines in chat, time played and the caption to the journal window, the settings, the minimap button and the addon menu's entry, has been tested only outside the game. If something doesn't work, please [open an issue](https://github.com/Coalition-Gaming/Footsteps/issues), or say so in the comments on [CurseForge](https://www.curseforge.com/wow/addons/footsteps).

## Install

Get Footsteps from [CurseForge](https://www.curseforge.com/wow/addons/footsteps), with the CurseForge app or by hand.

To run it from this repository instead, copy the repository's contents into a folder named `Footsteps` in your game's `Interface/AddOns` folder. The game then shows its version as `@project-version@`, which CurseForge's files replace with the real one.

## This repository

This is Footsteps' source as it ships, starting with 0.1.0. `Libs/ForeverKit` is a small library of Coalition's that Footsteps embeds. For now Footsteps is developed in Coalition's private workspace, where its tests live, and each release's source is published here.

## License

GPL-3.0. See [LICENSE](LICENSE).
