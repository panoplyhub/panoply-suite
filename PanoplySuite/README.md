# Panoply Suite 0.9.9.3

A personal leveling and professions guide for **WoW Forever**, for Alliance and Horde.
Since 0.9.7 Panoply Suite is for WoW Forever only.

## Install
**Easiest:** download `PanoplySuite-0.9.9.3-Setup.zip`, unzip it, quit WoW and
double-click **Install Panoply Suite (Windows).bat** or **Install Panoply Suite (Mac).command** (on a Mac
right-click > Open the first time). It installs or updates all three folders, `PanoplySuite`,
`PanoplySuite_QuestData` and `PanoplySuite_RouteData`. It finds WoW, backs up your old Panoply Suite folders and WTF folder to
Documents > Panoply Suite Backups, installs into `_forever_` only, and keeps your
settings and progress. Any other game folder is left exactly as it is. `READ ME FIRST.txt` in the zip has the details. To do it by hand instead:

1. Quit WoW.
2. Copy the `PanoplySuite` folder into the AddOns folder of your WoW Forever game.
   - Windows: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
   - Mac: `/Applications/World of Warcraft/_forever_/Interface/AddOns/`
   - If your Forever folder has another name, use whichever folder holds your Forever game.
     See LAUNCH-DAY-CHECKLIST.md.
   - If the `Interface/AddOns` folder doesn't exist yet, create it.
   - Keep the folder name exactly `PanoplySuite`.
3. Copy the **PanoplySuite_QuestData** folder next to it (same `Interface/AddOns` folder, folder name
   exactly `PanoplySuite_QuestData`). It is Panoply Suite's own quest, NPC, profession and gathering
   database, built from the open VMaNGOS server data. It is the only quest data Panoply Suite reads.
   Without it, Panoply Suite still loads, tells you the quest data is missing and follows your quest
   log only.
4. Start the game. On the character screen click **AddOns**. Make sure Panoply Suite is ticked. If it
   says "out of date", tick **Load out of date AddOns**.
5. Type `/panoply selftest`. The first line names the game Panoply Suite detected, for example
   `detected game: WoW Forever`.

## First run
The first time any character logs in on your account, a one-page **thank-you** opens and leads straight into the
**setup**. Every new character gets the same short setup (about 30 seconds, four steps, each already answered with the
usual choice): which **settings** (the same profile as your other characters, a saved profile, or a fresh one), a
**class plan** (the ready-made plans for your class, or "I will build my own later"), **group quests** (Ask me each
time, Always include them, or Leave them out), and **solo or partner**. **Skip, use my usual** is on every step and the line above it says exactly what it will use. It
never asks for your professions (Panoply Suite reads them from your skills, see below) and no longer asks about
automation (auto accept, hand in and fly stay in the Guide page's gear, "At quest givers"). Nothing changes until you
click **Start guiding**. Run it again any time with `/panoply setup` or from Help (**Run setup again**).

## Use
- **Minimap button** (the gold crest): left-click shows or hides the guide window. Right-click
  opens the menu. Drag it to move it around the minimap.
- `/panoply` (or `/ps` for short) opens the menu. It has four tabs:
  - **Leveling** shows your route, with Replan now, Skip step and Reset plan buttons.
  - **Professions**: lists the professions Panoply Suite found on this character. For the
    selected one you get your skill and a bar to the next trainer cap, a **Your next step** card
    (Guide me / arrow / Later), and four pages:
    - **Shopping**: every material for the plan with *have / need* counted from bags, bank and
      mail, then where to buy or gather each one, each with an arrow button. Enchanters also get
      a disenchanting list that points at their own (or their partner's) Tailoring greens.
    - **Steps**: the plan as "Make N x Item (skill A-B)" segments plus trainer visits, with the
      one you are on highlighted.
    - **Trainers & recipes**: each rank's trainer, place and fee; recipes to learn or buy; tools;
      the Blacksmithing Armorsmith/Weaponsmith choice at 200 (optional, never forced).
    - **Together**: your partner's professions and next profession step, and how your professions
      help each other.
    Buttons on the left switch between Cheapest and Fastest, From my skill and From scratch,
    and how profession steps join your guide.
  - **Partner** (Level together): turn levelling together on or off, see how your partner is
    doing, and sync the two of you to the same step. See "Playing together" below.
  - **Settings**: grouped sections (Quests and automation, Levelling together, Arrow and window,
    Professions, Tools), each with a one-line explanation.
  The same settings are also listed under Esc > Options > AddOns > Panoply Suite.
- The **guide window** shows one step at a time in plain words, with a line explaining why, your
  progress, the distance, and an arrow. "What now?" tells you exactly what to do next. A small
  banner appears at the top of the screen when a step is done.
- **Profession steps** show in the same guide window with the arrow, for example "Mine Copper
  Veins in Dun Morogh (Copper Ore: 12/60)", "Buy 20 x Coarse Thread from ...", "Train Journeyman
  Blacksmithing ... (4s 50c)" or "Make 15 x Rough Sharpening Stone (skill 1-16) at an anvil".
  They tick off on skill-ups, item counts and learning from the trainer. If you are short of a
  material, a gather or buy step is put in first. Pick how they show with the guide switch
  below: **Both** (only when the place is close by), **Professions**, or **Leveling** (they wait
  in the small profession tracker under the guide). On a profession step,
  **Later** hides it for 15 minutes.
- **Leveling | Professions | Both**: a switch at the top of the guide window (and on the menu's
  Leveling tab) picks which guide you follow. **Leveling** is your route; **Professions** is your
  profession plan, step by step; **Both** is the mixed mode (profession steps join the route when
  the place is close by). The button next to it shows the profession being followed; click it for
  the next one. Each guide keeps its own place: while you are on Professions the route waits on its
  step, and when you switch back it carries on there (ticking off anything you already did). The
  arrow and auto-advance always follow the guide you picked. The choice is saved per character.
- **Professions are found by themselves.** On login, and whenever you learn, unlearn or skill up a
  profession, Panoply Suite reads your skills and adds or removes its plan, starting from your current
  skill. Chat and a banner say "Panoply Suite: Blacksmithing detected, plan ready." A new alt is
  scanned on its first login. To plan one you have not learned yet, or to hide one, use Settings >
  Professions > **Found: ...** (Automatic / Always plan / Never plan for each profession).
- Steps tick off by themselves. Auto accept and auto turn-in are on by default. Hold **Shift**
  when talking to an NPC to stop the automation once.

### Group quests
The levelling styles are gone (0.9.7). One setting decides what the guide does with quests that need a
group. It is in the Guide page's gear and in the setup's **Group quests** step.
- **Ask me each time** (the default): when the guide reaches a group quest, it asks you. Your answer
  for that quest is remembered.
- **Always include them**: group quests stay in your guide.
- **Leave them out**: the guide skips group quests.

Your old levelling style carries over once, and only if you have not chosen a Group quests setting
yet: **Safe & steady** becomes Ask me each time, **Safe** becomes Leave them out, **Fastest** and
**Ultimate** become Always include them. Nothing in your saved settings is deleted.

### Picking your guide
The Guide page has a guide picker. It lists the guides that fit your character, with the one you
are on ticked. **Pick for me (recommended)** lets Panoply Suite choose. Switching guides keeps your
progress: the guide starts from what you have done and what is in your quest log, not from its
first step. A pick made during a fight waits until the fight is over.

### Commands
| Command | What it does |
|---|---|
| `/panoply` or `/ps` | Open or close the menu. Every command below also works with `/ps`, e.g. `/ps noguide` |
| `/panoply guide` | Show or hide the guide window |
| `/panoply guide leveling` / `professions [name]` / `both` | Pick which guide the window follows, e.g. `/panoply guide professions mining` |
| `/panoply switch` | Flip between the levelling and the profession guide |
| `/panoply setup` | Run the setup again |
| `/panoply replan` | Build a fresh route from where you are |
| `/panoply skip` | Skip the current step |
| `/panoply reset` | Throw away the plan (you'll need to Replan) |
| `/panoply prof tailoring` | Plan a profession (no name opens the Professions tab) |
| `/panoply prof track blacksmithing` | Guide that profession's steps |
| `/panoply prof mode interleave` / `only` / `off` | Same as `/panoply guide both` / `professions` / `leveling` |
| `/panoply prof cheapest` / `fastest` | How profession plans pick recipes |
| `/panoply prof now` / `later` | Show the profession step in the guide now / hide it for 15 minutes |
| `/panoply prof tracker` | Show or hide the profession tracker |
| `/panoply price "Item" 15` | Set your own Auction House price in copper for profession plans |
| `/panoply minimap` | Show or hide the minimap button |
| `/panoply scale 1.2` | Make the windows bigger or smaller |
| `/panoply options` | Open the Settings tab |
| `/panoply selftest` | Check the game functions Panoply Suite needs. Run it after every patch |
| `/panoply help` | List every command |

### Playing together
Level together on WoW Forever: both of you install Panoply Suite and join a party.
You see each other's progress, the guide waits for each other at turn-ins, and you can sync to the
same step.
- **The partner line** in the guide shows where your partner is. **Sync to my step** asks your
  partner to come to your step; they answer Accept or Decline. Nobody is moved without saying yes.
- **Turn-ins wait.** Automatic hand-in holds a quest your partner still needs and says who it is
  waiting for. **Go on without them** lets you carry on.
- **Class quests hold the guide.** While one of you does a class quest the other cannot take, the
  other's guide holds and offers to help: the arrow points at your partner. The arrow only points;
  it never moves your character.
- **What is shared, and with whom:** your guide, step, level, XP %, class, race and Panoply Suite
  version, plus quest progress, with your party only. Never with a raid, your guild or by whisper.
  Turn it off with the Level together switch; then nothing is sent or shown.
- The game can block add-on messages inside dungeons; sharing catches up when it can send again.

### Location notes
Under a step Panoply Suite can show where the NPC or object is, for example "Inside the Lion's Pride
Inn, upstairs". The facts come from PanoplySuite_QuestData (inns, floors, nearby buildings in the
server data) and from our own small table `Data/LocationNotes.lua` (faction leaders' halls). When
the data is not sure, no note is shown. If the target is indoors and you are outside, the arrow first
points to the entrance once one is known: from `Data/LocationNotes.lua`, or learned the first time
you walk in (Panoply Suite remembers the last outdoor spot). On WoW Forever, notes in the re-drawn
zones (Stormwind City, Redridge, Mulgore, Eastern Plaguelands) stay hidden until checked there.

### No quest data?
Panoply Suite still loads. The guide window then shows a **Turn on quest data** panel with the steps
(tick Panoply Suite Quest Data in the AddOns list), and follows your quest log only.

## WoW Forever only (since 0.9.7)
- Panoply Suite 0.9.7 and later installs and runs on WoW Forever only.
- If you have an older Panoply Suite in another game folder, the installer leaves that folder and
  its saved settings exactly as they are. Nothing there is changed or deleted.
- Your WoW Forever settings and progress are kept. No saved setting was renamed or wiped.

## If the game updates and the addon says "out of date"
Type `/dump GetBuildInfo()` in the game. The 4th value is the new Interface number.
Open `PanoplySuite_Forever.toc`, `PanoplySuite_Camelot.toc` and `PanoplySuite.toc`.

Add the new number with a comma to the line that starts `## Interface:`. For example,
`## Interface: 16001, 16002` becomes `## Interface: 16001, 16002, 16003`. Save, then `/reload`.

## Older releases
The sections below are the notes of older releases, kept as a record. Some describe parts that have
since changed (the levelling styles, the route planner, the old partner sync). Where an old note and
the sections above differ, the sections above are right.

## 0.7.x: what is new since 0.6.0
Each release's full list is in `INSTALL-STEPS-<version>.txt` next to the download. In short:
- **0.7.3.1:** the minimap trail runs through you and along your road; Trail dot size setting (Settings >
  Travel and route); the Auctions Selling tab prices the deposit and posts the way the game's own auction
  window does; Make in the profession window always passes your click to the game (a tester's enchanting).
- **0.7.3:** an Auctions trading window (a Trade button at the auction house: shopping lists, selling,
  undercut checks, price history) and Hearth Hall, one window with all your characters (`/panoply hall`).
- **0.7.2 / 0.7.2.1:** faster levelling routes that stay in a zone longer, much faster bag sorting, and calmer
  automatic re-plans when you level with a partner.
- **0.7.0 / 0.7.1:** Spec & Trainer, Report a problem, and a play-along questing mode that keeps the route off.

## The 0.5.0 suite
Each module can be switched off in Settings > Modules or on the menu's Modules tab.

| Module | What it does |
|---|---|
| Merchant | Repairs at vendors, sells grey items with a chat summary, Alt-click never-sell list, optional sale of soulbound gear you can't use (off) |
| Item quality glow | Crisp border in the game's quality colour on green, blue, purple, orange (and artifact/heirloom) items only; nothing on white, grey or empty slots; Subtle (default)/Normal/Strong nudge thickness and brightness; optional on the game's own windows |
| Bags | One bag window (B key), combined bank, search, sort, bag bar, gold, other characters' items, tooltip counts |
| Gathering | Herb, ore, fishing and chest nodes on the world map and minimap, partner sharing, "Mine Copper" steps point at the nearest node |
| Profession window | Search, favourites, colour filters, Can make counts from bags + bank, Guide me, optional auction cost |
| Waypoints | `/panoply way x y [zone] [note]`, `/way`, Ctrl-right-click the world map, waypoint list |
| Auctions | A Scan button on the auction house window, prices remembered per realm and faction for 30 days, prices on item tooltips |

Guide window: right-click the arrow to lock it (clicks then go through), choose 1-5 steps shown,
drag the bottom-right corner to resize, and set background and arrow opacity, fade,
"Hide guide window in combat" and "Hide arrow in combat" in Settings > Guide window.

## 0.6.0: Route planner, trail, skin v3 and release polish
- **Route planner and trail:** flight paths, boats, zeppelins, the tram and roads (PanoplySuite_RouteData,
  our own data), "Fly to" steps when they save time, trip time and time to level, a trail on the world
  map and minimap. Guide > Fastest way there.
- **Skin v3:** dark slate, gold headings, the accent colour; no glow and no parchment.
- **Progress bars:** the labels ("Route: 5 of 23 steps", "Level 4 (55%)") now sit above their bars and
  never cross the fill. The layout checker reports any text straddling a bar or its fill edge.
- **Route page:** the heading is "Route: level 1–4" and the line under it uses the full width.
- **Guide window:** no lone "No professions" pill when you have no profession.
- **Profession window:** the current skill and maximum under the title ("Blacksmithing 142 / 225 - 17
  recipes", a temporary bonus as "142 (+10)") and a thin skill bar; updates on every skill-up.
  Drag it by the title bar to move it; the spot is kept for each character (Settings > Profession
  window: "Lock the window position" and "Reset position"). By default it opens to the right of the
  character screen, spell book or any other left-side game panel that is open, never on top of it.
  The game's categories (Armor, Weapons, Materials ...) are a tab row above the search box ("All"
  first; it scrolls sideways with the mouse wheel or the small < > buttons when they do not fit; for
  Enchanting the categories come from the recipe names). "Show all" lists every recipe whatever your
  materials and the colour filters; "Have mats" is still its own filter.
- **Gathering:** with Find Minerals or Find Herbs on, ore and herb spots inside the minimap are thin
  hollow rings, so the game's gold dot shows inside. An empty ring means the node is not up right now.
  Map page > gear > Look of the map > Gathering > Minimap > Style: Ring (on; Icon draws pins instead). Rim pins, world map
  pins, chests and fishing spots are unchanged.
- **Quest data:** Panoply Suite reads only PanoplySuite_QuestData. The fallback to another add-on's quest data is gone.
- **Quest icons (new module):** quest givers, turn-ins and objectives on the world map and minimap,
  and quest lines in mob, object and item tooltips, from our own quest data, so no other quest add-on
  is needed. Click an icon to set a waypoint: the arrow and the route take you there, from another
  zone too.
- **Quest tracker (new module):** your quests grouped by zone (current zone first), objectives,
  timers, "Ready to turn in", item buttons beside their quests, right-click menu. Each row is exactly
  as tall as its text; tags such as Dungeon or Elite are a small pill after the quest name.
  Settings > Quest tracker.
- **Enchanting from the Panoply Suite profession window fixed (tester report):** after "Make" on an enchant you
  could not click the item to enchant, and "Panoply Suite has been blocked from an action only available
  to the Blizzard UI" kept coming back until /reload. Panoply Suite no longer replaces the game's own bag
  functions (it follows them instead), and nothing in Panoply Suite touches a bag item while a spell is
  waiting for its target. Click the item in the Panoply Suite bags or on the character screen as usual.
  Dragging items and the tooltips work as in 0.5.9.1 and 0.5.9.2.
- **Arrow fix:** the arrow keeps its direction after a zone change, a loading screen, a boat or a
  zeppelin (Arathi Highlands and every zone past the low-level ones), and points to the next leg of
  the route (a flight master, a boat) when the target is in another zone. New, sharper arrow art.

## 0.5.9.1: Drag and drop in bags fixed, profession window scrolls
- **Bags:** press, hold and drag an item onto another slot, an empty slot or a bag in the bag bar
  works again (0.5.9 redrew the bag under the drag, which cancelled it). Click to pick up, click
  to drop and right-click to use are unchanged.
- **Profession window:** long recipe lists scroll in their own area above the recipe box instead
  of running under it; the box grows to fit three materials, and the window is shorter on short
  screens. Also: every waypoint is listed (0.5.9 showed 8), and long toasts fit their banner.

## 0.5.9: Our own quest database, one profession window, drag and drop in bags
- **PanoplySuite_QuestData** now ships with Panoply Suite: its own quest, NPC, object, item, profession
  and gathering database, built from the open VMaNGOS server data
  and the game's map tables (wago.tools). You no longer need another quest add-on. (In 0.5.9 a missing
  PanoplySuite_QuestData still fell back to another add-on's quest data; that fallback is gone since 0.6.0.)
- **Location notes** under the step headline, e.g. "Inside the Lion's Pride Inn" for an innkeeper,
  for inns and the capital leaders only. When we are not sure, there is no note.
- **One profession window:** when you open a profession (or Enchanting), only the Panoply Suite
  window shows. The game's own window stays open and working underneath but is hidden, so one
  click crafts and closing our window ends the session. The "Blizzard" button in our window, or
  Settings > Profession window > "Use Blizzard profession window too", shows the game's window
  as well (off by default). Nothing is changed during combat; it catches up afterwards.
- **Drag and drop in bags:** drag an item in the Panoply Suite bag window to another slot or onto a
  bag in the bag bar. Click-to-pick and right-click to use work as before. Settings > Bags >
  "Drag and drop items in bags" (on by default).
- Works with everything from 0.5.8: the "[level] Quest Name" title in its difficulty colour sits
  above the headline, the note below it, and the difficulty guard uses our own quest levels.
- The one-click installer installs and updates both folders with the same rules (backup of add-ons
  and WTF first, saved variables never touched, Hearthpath_Data kept, everything put back on error).
- Memory: PanoplySuite_QuestData used about 4.9 MB of Lua memory (4,927 KB on WoW Forever) and
  2.2 MB on disk in 0.5.9.

## 0.5.8: Safer quest routing, quest levels in colour, one-click installer
- **No more quests that are too hard.** Panoply Suite never routes a red quest (5 or more levels
  above you) and never an orange elite quest. While you are partnered it uses the lower of your
  two levels. A too-hard quest that is already in your log is **kept for later**, not dropped:
  chat says "Later: <quest> (needs level N)", Replan won't offer to drop it, and when you (or your
  partner) reach that level it is put back on your route ("Back on your route: ..."). A finished
  quest can still be handed in.
- **Elite quests stay off by default.** With "Include elite quests" on, an elite quest is only
  routed when it is at most 2 levels above you (or your partner, if lower). The setup page and the
  setting now say plainly: "Elite quests need a group of 3-5. Not recommended for a duo."
- **Quest levels in the game's colours.** The guide step, the Up next list and the Leveling tab
  show quests as **[34] Quest Name** in the same red / orange / yellow / green / grey the game uses
  for that quest. The colours update when you level up and are brightened where needed so they stay
  readable on the dark panel.
- **One-click installer and updater** for Windows and Mac (`Hearthpath-0.5.8-Setup.zip`):
  - finds WoW (Windows: registry, Battle.net settings, Program Files, other drives; Mac:
    Applications and other disks) and installs into `_forever_` (since 0.9.7, only there). It never
    touches `_retail_`, `_classic_` or other game versions, or your other add-ons;
  - asks you to quit WoW if it is running;
  - backs up the old Panoply Suite folders and your WTF folder to Documents > Panoply Suite Backups
    (the last 5 are kept), replaces only the Panoply Suite folder, never changes WTF or saved
    variables, and checks the result. If anything fails it puts everything back;
  - keeps the **Hearthpath_Data** folder written by the HearthpathPrices app as it is;
  - needs no admin rights, except when WoW is in Program Files (Windows asks once) or a protected
    Mac folder (asks for your password).
  The plain `Hearthpath-0.5.8.zip` (add-on folder only) is still there for installing by hand.

## 0.5.7: Partner sync fix, quest clean-up on Replan, fading gathering pins, corpse arrow
- **Fixed: "Waiting for <partner> to finish this step too" could stay up for good** even after
  you both finished the step. Panoply Suite sent "not ready" at the moment you finished, so each of
  you waited on the other. Now it tells your partner you are ready as soon as your step is done,
  and repeats it every 15 seconds while you wait, so a lost message can't hold you both up.
- **Drop unneeded quests on Replan** (Settings > General, "Offer to drop unneeded quests on
  Replan", on by default): after Replan, a window lists the quests in your log that the new route
  doesn't use, ticked, each with the quest items that would be destroyed under it. Untick to keep
  one. **Confirm** abandons the ticked quests and deletes their quest items; **Keep all** does
  nothing. Only items the game marks as quest items for that quest are ever touched, never gear
  or items that sell. While you are partnered, quests your partner's route still needs are never
  listed. Not in combat. If the game won't let Panoply Suite delete an item, the quest is still
  dropped and chat tells you which items to delete by hand.
- **Gathering pins fade when you are close** (Settings > Gathering, "Fade pins when close" and
  "Fade distance"): minimap pins are fully visible from the fade distance (60 yards) and fade to
  about 15% within 15 yards, so the game's gold Find Minerals / Find Herbs dot shows through. On
  the world map only a pin under your own arrow fades.
- **The arrow stays in fights.** "Hide in combat" is now two separate settings in Settings > Guide
  window: **Hide guide window in combat** (on by default; fades the guide window, its menu and the
  profession tracker) and **Hide arrow in combat** (off by default). With the arrow setting off,
  the arrow stays at its own opacity and lock and keeps pointing and counting yards through the
  fight. Your 0.5.6 "Hide in combat" choice carries over to the window setting; the arrow stays
  visible unless you had also ticked "Also hide the arrow in combat". Fades only, so nothing is
  blocked in combat.
- **Corpse arrow** (Settings > Guide window, "Corpse arrow when dead", on by default): while you are
  a ghost a separate lavender arrow with a skull points to your corpse with the yards left. The
  quest arrow waits and comes back when you are alive again (at your corpse, at the spirit healer
  or resurrected by another player). If your body is on another continent it says
  "Corpse in <zone>".

## 0.5.6: A tour for new players, and a quieter screen in fights
- **First login:** the setup wizard now opens a couple of seconds after you log in, and it still
  opens even if some other part of Panoply Suite fails to start. With no route yet, chat says
  "Panoply Suite: type /panoply setup to get started".
- **After an update:** a small card says "Panoply Suite updated" with **Setup**, **Tour** and **Not now**.
  It shows once per account and never on top of the setup wizard.
- **The tour ("How to use Panoply Suite"):** it starts once after your first setup. Replay it with
  `/panoply tour`, the **Take the tour** button in Settings > General (Tools), the Help tab, or the
  Leveling page when there is no route yet. The screen dims, the real window lights up and a card
  beside it explains it. Use Back / Next / Skip tour (Esc also closes it). Steps for modules you
  switched off are skipped, and a fight closes the tour.
- **Help tab:** the main slash commands and the same tips as the tour.
- **Hide in combat** (Settings > Guide window, on by default): the guide window and the profession
  tracker fade out when a fight starts and fade back in when it ends. The arrow stays unless you
  tick **Also hide the arrow in combat**. This uses fades only, so nothing is blocked in combat.

## 0.5.5: Everything fits

- Modules cards: the description no longer hides behind the buttons. Cards grow to fit their text and the buttons sit underneath.
- New tabs: rounded, evenly spaced, with a clear gold "you are here" tab and a gap above the page.
- Every window was re-laid out to measure its own text, so nothing overlaps, clips or runs out of its box, even with larger game fonts: guide window, route switch, profession tracker, Leveling, Partner, Professions, Settings, the setup wizard (now scrolls if needed), waypoint list, profession window and the Auction House scan bar.

## 0.5.4: WoW icons everywhere (or Panoply Suite icons, your choice)
- **Icon style** (Settings > General > Appearance): "WoW icons" (default) uses the game's own
  icons for everything Panoply Suite draws: bag window buttons, menu tabs, guide steps, map pins,
  wizard, module list, profession window and the auction scanner. "Panoply Suite icons" switches to
  the addon's own icon set. Click to switch; no `/reload` needed.
- **Items always look like themselves.** In both styles a bag slot shows the item's own game icon.
  The quest marker appears only when the game says the item is a quest item (border) or starts a
  quest (!), and the junk coin only on grey items. Items the game hasn't loaded yet show the
  game's "?" icon until it arrives. Tooltips are the game's own, with our prices added underneath.

## 0.5.3: rounded look, game icons, prices on tooltips
- Everything is rounded now (windows, buttons, tabs, search box, bars, toasts, bag slots and the
  quality marker). Icons are the game's own built-in icons; if one is missing in your client the
  addon's own icon is used instead. Want the old Panoply Suite crest back? Settings > Guide window >
  "Show the Panoply Suite crest", then `/reload`.
- **Tooltip prices** (Settings > Bags > Tooltips): vendor price (per stack) and auction price
  (each + stack), with where it came from and how old it is. Hold **Shift** for the 30-day
  average, highest recent price and market/historical values. Items not up for sale in the last
  scan show "Last seen" and "Highest recent". Price source: Auto (newest wins), Panoply Suite scan,
  Blizzard prices or Companion file.
- **Auctions**: open the auction house and press **Scan**. Where the game allows a full scan only
  about every 15 minutes, the label counts down and it scans page by page meanwhile. Prices are kept
  per realm and faction (Alliance, Horde and the neutral goblin auction houses are separate).
  Auto-scan on open is off by default; browsing records prices as you go.
- **Hearthpath_Data** (optional companion addon): if installed, its prices for your realm and
  faction are used, with the date shown and "old" after 3 days; a fresher own scan wins in Auto.
  Failing that, the US region average ("US avg") is shown.

## Licenses and data
- **Licence:** the whole of Panoply Suite is free software under the GNU General Public License
  version 3 only (GPL-3.0-only): this add-on, PanoplySuite_QuestData, PanoplySuite_RouteData,
  PanoplySuite_Plans and the Hearthpath stand-in. Each folder has the licence in its `LICENSE`;
  credits are in each `NOTICE.md`.
- All code, step texts, profession recipes and every image in `Media/` (crest, panels, brass trim
  and corner caps, the J line icons, map pins, arrow) were drawn for this addon; the v3 look comes
  from our own final-v3 pack. Where the game has a matching built-in texture, Panoply Suite uses it
  and falls back to its own art if the file is missing.
- Fonts in `Media/Fonts/`: Spectral SC and Lato, both under the SIL Open Font License 1.1
  (`SpectralSC-OFL.txt`, `Lato-OFL.txt`). See `NOTICE.md`.
  No outside guide material was used, and no Blizzard website art is included.
- Quest, NPC, object, item, profession and gathering data lives in the separate add-on
  **PanoplySuite_QuestData** (GNU GPL v3, see its LICENSE, README and NOTICE). It is generated at build
  time by our own scripts (`tools/vmangos_world.py`, `tools/build_questdata.py`,
  `tools/build_profdata.py`, `tools/build_gatherdata.py`; not shipped) from the **VMaNGOS** world
  database (GPL version 2 or later, used here under version 3; 1.12.1 build 5875) and from map rectangles in the game client's own tables.
  Panoply Suite reads it only through its adapter (`Engine/QuestData.lua`, `Data/Professions/Common.lua`).
  No other quest add-on's code or data is used, and since 0.6.0 no other add-on's
  quest database is read at runtime either.
- Location notes: `Data/LocationNotes.lua` is our own hand-written table (checked against spawn
  positions, in-game checks pending); the generated facts are in `PanoplySuite_QuestData/Data/Locations.lua`
  (VMaNGOS). The note wording is Panoply Suite's own and is not taken from any guide, add-on or site.
- Profession data (recipes, reagents, colour thresholds, trainers and fees, vendor prices and
  places, disenchant results, rank quests, mining nodes) is in `PanoplySuite_QuestData/Professions/`.
  All values are Classic 1.12 values and UNVERIFIED for WoW Forever;
  values worked out by rule (green colour thresholds, guessed prices, fishing skill, time
  estimates) are marked derived/guess/unverified in the files. Panoply Suite corrects recipe colours
  from your open profession window. Auction House prices are guesses (twice the vendor sell
  price); set real ones with `/panoply price "Linen Cloth" 15` (copper).
- Gathering spawn points in `PanoplySuite_QuestData/Gathering/Nodes.lua` come
  from the **VMaNGOS** world database (1.12 data), with zone coordinates from the client's map tables.
  No data from any other add-on or site was used. That list is not shown on WoW Forever: there the
  node list starts empty and fills as you gather.
- The 0.5.0 modules were written from a plain feature list. No code, art or data from any other
  add-on was used.
