# Changes Panoply Suite made to Polestar

This folder holds Polestar v0.4.2.1 (revision 4e1cd84), a guide engine by the Polestar authors, licensed under the
GNU General Public License, version 3 (GPL-3.0-only). Its licence texts are in `PanoplySuite/Licenses/Polestar/`
(`LICENSE`, `LICENSE-EXCEPTION.md`, `THIRD_PARTY.md`) and in the folders here that carry their own.

Panoply Suite (Ostrowski Holdings LLC) ships Polestar repackaged inside its own folders and, since the date below,
with the files listed below modified. This file is the notice of those modifications that section 5(a) of the GPL-3.0 asks for. The
modified files stay under the GPL-3.0, as does the rest of Polestar.

## Modified files

### 2026-11-18, Panoply Suite 0.9.7: `Polestar/Quests/Party.lua` (party sync trimmed)

Polestar's party sync sends hidden add-on messages to the other members of your party who run it. Panoply Suite
now shares less through it. Two kinds of message are no longer sent, and are no longer kept or shown when a party
member sends them:

- `2D|` "what you did": the quests you handed in on the guide steps around your current step.
- `2B|` Boosted Rest: how much Boosted Rest time you have left.

What changed in the code:

- `sendDone`, `sendRest` and `onRest` return at once, so neither message is ever sent or put on a timer.
- In `onAddonMessage`, a `2D|` or `2B|` message from a party member is still recognised as a valid Polestar
  message (the member counts as running Polestar, and a party member on an unmodified Polestar causes no error),
  and then nothing of it is stored. So the party panel shows no Boosted Rest for a member, and "already done" is
  no longer given as the reason a member lacks a quest on the strength of that message.
- A short comment under the file's header says the copy is modified.

Everything else in the party sync is as Polestar released it: the hello (Polestar version), quest IDs and counts,
the guide and step you are on (with the guide pack and its version), the sync request and its answer, and your
level, XP percent, class, race and Polestar version.

Why: Panoply Suite's owner approved sharing only guide, step, level, XP percent, class, race and version (plus the
quest IDs and counts the sync needs) with the party.

Every changed place is between two marker lines, so the change can be read, or taken out again, exactly:

    -- PANOPLY PATCH BEGIN (party-trim, 0.9.7): <why>
    ...
    -- PANOPLY PATCH END

Deleting every line from a `PANOPLY PATCH BEGIN` line to its `PANOPLY PATCH END` line gives back Polestar's file.
No Polestar licence notice, copyright line or credit was changed or removed.

### 2026-11-18, Panoply Suite 0.9.7: `Polestar/Core/Update.lua` (no version hello to the guild or by whisper)

Polestar tells other players which version it is, so that it can say when a newer release is out. It does that in
three ways: with your party through the party sync, with your guild (a hidden add-on message at login, and an
answer to a guild member on an older release), and with strangers (a hidden add-on whisper to a player of your
faction you target or mouse over, and an answer to such a whisper). Panoply Suite keeps the first and has taken out
the other two. These messages are no longer sent, and are no longer listened to when someone else sends them:

- `1H|<version>` on the guild channel: the guild hello.
- `1Y|<version>` on the guild channel: the answer to a guild member's hello.
- `PSV1?<version>` by whisper: the version probe.
- `PSV1=<version>` by whisper: the answer to a probe.

What changed in the code:

- `guildOn` and `probeOn` answer no at once, so the hello, its answer, the probe and its answer are never due,
  whatever the settings `party.share` and `update.probe` say.
- `sendTo`, the one function in the file that sends (it sends only to the guild or by whisper), returns at once
  without sending.
- `Update.Probe` returns at once: the game is not asked whether a player can be whispered, and no player's name
  is written to the saved data.
- `Update.Listen` returns at once, so nothing is registered: not the guild channel, not whispers, not the target
  or mouseover events. `onGuild` and `onWhisper` also return at once, so a hello, an answer or a probe from
  someone else is dropped unread: no version heard that way is kept or believed.
- A short comment under the file's header says the copy is modified.

Everything else in the file is as Polestar released it. In particular the version exchange with your party is
untouched: `Quests/Party.lua` still sends your Polestar version to your party and still passes a party member's
version to `Update.NotePeer`, so the notice that a newer release is out still works from a party member (and from
Polestar Client's file). The setting `update.probe` is still there and now changes nothing.

Why: Panoply Suite's owner decided that the version may be shared with your party only. Switching the setting
`update.probe` off stopped the whisper to strangers but not the guild hello and its answer, which went out whenever
party sharing was on and the player was in a guild.

The changed places are marked the same way, with their own name:

    -- PANOPLY PATCH BEGIN (no-guild-hello, 0.9.7): <why>
    ...
    -- PANOPLY PATCH END

Deleting every line from a `PANOPLY PATCH BEGIN` line to its `PANOPLY PATCH END` line gives back Polestar's file.
No Polestar licence notice, copyright line or credit was changed or removed.

### 2026-11-18, Panoply Suite 0.9.7 in-game hotfix: no text that names another add-on (11 files)

Polestar's settings named another quest add-on in three places a player can see: the help line of "Hide the
game's quest tracker", and the title, label and help of the Integrations section that shows Polestar's turn-in steps in
that add-on's tracker (that section is there only while the add-on is installed). Panoply Suite now words them without
the name, in English and in the nine languages:

| Was | Now |
|---|---|
| "...professions, as [add-on name] can. Not with the gamepad interface." | "...professions, as some quest add-ons can. Not with the gamepad interface." |
| section title "[add-on name]" | "Quest tracker add-on" |
| "Show planned turn-ins in [add-on name]" | "Show planned turn-ins in its tracker" |
| "Completed quests in [add-on name]'s tracker show their Polestar turn-in step. ..." | "Completed quests in that add-on's tracker show their Polestar turn-in step. ..." |

What changed in the code, file by file:

- `Polestar_Options/QoL/Options.lua` (in Polestar 0.3.7.2 this was `Polestar/QoL/Options.lua`; 0.4.2 moved the settings into
  the `Polestar_Options` folder): after Polestar's `C.hideQuestTracker`, a block wraps it so the setting it returns
  carries the reworded help. The setting itself (key `qol.hideQuestTracker`, what it does) is unchanged.
- `Polestar_Options/UI/GuideOptions.lua` (in Polestar 0.3.7.2 this was `Polestar/UI/QuestieTurnIns.lua`; 0.4.2 moved the
  Integrations section's registration here): just before Polestar's own `register` call for the Integrations section,
  a block wraps `ns.RegisterOptions` (which `register` calls) for that one call: it puts Polestar's function back at once, swaps the section
  title, label and help for the reworded ones and registers through Polestar's function. The setting
  (`routePlan.questie`, off by default), the check that the add-on is installed, and every hook on its tracker are
  unchanged.
- `Polestar_deDE/Interface.lua`, `Polestar_esES/Interface.lua`, `Polestar_esMX/Interface.lua`,
  `Polestar_frFR/Interface.lua`, `Polestar_koKR/Interface.lua`, `Polestar_ptBR/Interface.lua`,
  `Polestar_ruRU/Interface.lua`, `Polestar_zhCN/Interface.lua`, `Polestar_zhTW/Interface.lua` (in
  `PanoplySuite_Languages/`): two blocks each. After the old lines, a block clears the three old entries (`= nil`)
  and adds the four reworded ones in that language.
- A short comment at the top of each block says why.

Polestar's code that only looks for the add-on and is never shown is kept as written: the file and module names
(`UI/QuestieTurnIns.lua`, `ns.QuestieTurnIns`), the setting key `routePlan.questie`, `ns.Compat.AddOnPresent("Questie")`,
the `ADDON_LOADED` check for it, `QuestieLoader` and its modules, the data-source letter `q = "questie"` in
`Polestar/Lookup/Codex.lua` (never shown), and comments. Credits and licence files that name it (`LICENSE-DATA.txt`,
`CREDITS.md`) are not shown in the game and are not changed.

Why: Panoply Suite's owner wants no player-visible text that names another add-on (0.9.7 in-game check).

These blocks are marked with their own name:

    -- PANOPLY CHANGE BEGIN (0.9.7 hotfix: no Questie text)
    ...
    -- PANOPLY CHANGE END

As with the blocks above, deleting every line from a `PANOPLY CHANGE BEGIN` line to its `PANOPLY CHANGE END` line gives
back Polestar's file byte for byte. No Polestar licence notice, copyright line or credit was changed or removed.

<!-- polestar_update.py: generated section begin (do not edit by hand) -->
## Marked changes in this copy, file by file

Polestar v0.4.2.1 (revision 4e1cd84). 34 marked changes in 13 files (written by `tools/polestar_update.py` on 2026-11-21; the bundle check counts the same):

| File | Marked changes |
|---|---|
| `Polestar/Core/Update.lua` | 8 |
| `Polestar/Quests/Party.lua` | 6 |
| `Polestar_Options/QoL/Options.lua` | 1 |
| `Polestar_Options/UI/GuideOptions.lua` | 1 |
| `Polestar_deDE/Interface.lua` | 2 |
| `Polestar_esES/Interface.lua` | 2 |
| `Polestar_esMX/Interface.lua` | 2 |
| `Polestar_frFR/Interface.lua` | 2 |
| `Polestar_koKR/Interface.lua` | 2 |
| `Polestar_ptBR/Interface.lua` | 2 |
| `Polestar_ruRU/Interface.lua` | 2 |
| `Polestar_zhCN/Interface.lua` | 2 |
| `Polestar_zhTW/Interface.lua` | 2 |
<!-- polestar_update.py: generated section end -->

## Folders of Polestar's release that are not included (Panoply Suite 0.9.9)

Panoply Suite carries Polestar 0.4.2 without these folders of its release: `Polestar_Arcade`, `Polestar_Experimental`,
`Polestar_Looks`, `Polestar_SkinAPI` and the ten `Polestar_Skin_*` folders. No file of Polestar's code was edited to leave
them out: Polestar looks for these folders when it needs them and runs without them (the list is in
`tools/update_polestar_engine.py`, `EXCLUDED_FOLDERS`). Every other folder of the release is included.

## Everything else is unchanged

Apart from the files above, every file here is Polestar's v0.4.2.1 release unchanged, except for the packaging that
lets it load from inside Panoply Suite's folders. That packaging is described at the top of
`tools/update_polestar_engine.py` in Panoply Suite's source: each Lua file is wrapped on its first and last line,
and the paths to Polestar's pictures, fonts and sounds point at their new folder.

Polestar's own source: see `PanoplySuite/Licenses/Polestar/` and the credits Panoply Suite prints with
`/panoply polestar`.
