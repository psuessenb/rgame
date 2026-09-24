# The rest of the README roadmap

**Status: steps 0 to 14 are implemented.** Steps 0–16 of
[the roadmap](04-roadmap.md) are detailed: 5–8 planned after step 4 landed,
9–12 after step 8, and 13–16 after step 12. Step 17 folds the plan back.

| File | What it holds |
|---|---|
| [01-current-state.md](01-current-state.md) | what each item builds on, measured |
| [02-prior-art.md](02-prior-art.md) | how Unreal, Unity, Godot and miniaudio answer the same questions |
| [03-design.md](03-design.md) | the classes, item by item |
| [04-roadmap.md](04-roadmap.md) | the order to build them in |

## Goal

Build the nine features left on [the README's roadmap](../../../README.md):
input that reads holds and combos, a scene manager with transitions, a debug
layer wired to collision, pushing and pulling, inventory and equipment screens,
collectables and interactables, audio transitions, visual effects, and
cutscenes. Tiled support is the tenth item and has
[a plan of its own](../tiled-format/README.md).

## Verdict

**Seven of the nine are engine-layer Ruby over parts that already exist.
Visual effects and audio need some C as well.** Nothing here needs a new
subsystem, and no item is a plan of its own the way dialogue was.

| Item | The shape it takes | Steps |
|---|---|---|
| Input | `hold:`, `tap:` and `all:` declared in the `InputMap`; `poll` takes `dt`; a node reads only the presses it saw start | 2 |
| Debug layer | an `Engine::Debug` system of named channels; shapes draw themselves | 1 |
| Collectables | `Interactor` extends `Targeting`; `Collectable` frees its node | 1 |
| Push and pull | `pushes:` on `Mover`, a `Pushable` mover, a `Grab` component | 2 |
| Inventory | `UI::Grid`, `Stepping` over a grid, `UI::FocusGroup`, `UI::Tabs` over a `Menu`, scrolling | 3 |
| Visual effects | a fade node, `Components::Particles`, a bolt — plus blend modes and opacity in C | 2 |
| Audio | fades, a crossfade, pause and resume, a volume per category a game names; music a room or an event claims | 2 |
| Scenes | `SceneStack` defers and names its scenes; transitions; `Scene::Rooms`, which players stand apart in; doors from a map | 3 |
| Cutscenes | a linear script over what already says when it is done, in a component that gives back what it stopped | 1 |

**Three things carry more than one item, and each is built once.**

1. **The tween**, which landed before this plan. A fade, a crossfade, a camera
   move, a sliding crate and a cutscene's wait are all one.
2. **The fade**, which is a tween, a rect the width of a view and the node's own
   opacity. A door uses it, a cutscene uses it, and a storm's flash is it with
   another colour. A lightning bolt's afterglow is the same opacity on the
   bolt.
3. **"What is nearest in range on this layer"**, which `Components::Targeting`
   already answers for a turret. Interacting asks the same question for another
   reason, so `Interactor` extends it rather than asking it again.

**Two steps change how existing code behaves: push and pull, and the press
gate.** Everything else is additive. Pushing reaches into
`CollisionSystem#move`, which is what gives every mover in the project its
feel. The gate changes what a node reads after it was paused, hidden or not yet
in the tree. In both cases the driven examples decide whether anything a
player feels changed.

**The C step is blend modes and opacity, and it stays inside OpenGL 1.1.**
`glBlendFunc(GL_SRC_ALPHA, GL_ONE)` is core 1.0, so additive drawing needs no
loader and no render target — see [01](01-current-state.md#f12). The work is in
the draw queue: a blend mode has to travel with each command, as the clip does,
because sorting reorders them. Opacity travels with each vertex, as the
transform does. Audio needs C too, for a volume per category and for resuming a
song, and none of it touches GL.

**The re-plan of steps 13–16 added one subsystem.** Players may now stand in
different rooms ([decision 34](#decisions-already-taken)), and a `SceneStack`
runs one scene. `Scene::Rooms` runs the rooms of one world side by side, and
draws each only into its own players' views. It shares the stack's curtain, and
lands a move in the sweep as the stack lands a switch.

**Where the features meet is a test project, not a spec.** Nine features each
verified alone is the failure CLAUDE.md names: two systems, both green, that
compose badly. So `test_projects/adventure` is built in step 0 and grown by
every step after it, and its drive script is what says a pickup reached the
inventory and a door faded the music with the picture.

## What was measured before planning

Taken at `9abd338`, on this checkout.

| | |
|---|---|
| `rake spec` | 3035 examples, 0 failures, 24.4 s |
| GL functions called in `ext/` and `src/` | 21 distinct, 56 call sites, every one GL 1.1 |
| `glBlendFunc` call sites | **1**, in `gl_backend.c` |
| `poll` call sites | 3 in `lib/`, 70 in `spec/` |
| Code in `lib/` that times a held button | **none** |
| Roots hand-writing a deferred scene switch | **2**, each with a comment saying why |
| Interaction patterns hand-written in `examples/quests_and_dialogue` | **3**: nearest on confirm, read on touch, pick up on touch |
| `renderer.debug_box` callers outside specs | **0** |
| Scenes mounting a `CollisionWorld` / a `TileWorld` | 6 / 5 |
| Examples with a `WorldView` | 5, plus `test_projects/tiled_world` |
| `Engine::Tween` consumers | 7 |
| Music tracks in `examples/assets/` | **1**, 93 KB of the directory's 124 KB |

## Hard constraints

1. **The engine layer may not name `RGame::Core`.** Everything here is
   `RGame::Engine`, with two exceptions: step 9's blend modes and opacity, which
   are Core and C, and step 11's audio entry points.
2. **One runtime gem dependency, `rexml`, and no more.**
3. **Text a player reads is a translation key**, drawn through `Engine::Text`.
   `Game/NoLiteralText` holds it for `lib/` and `examples/`.
4. **Nothing on a draw path allocates or reads a clock.** Every effect here
   accumulates in `update(dt)` and draws from state.
5. **A fake must refuse what the real thing refuses.** A renderer or audio
   method added in a step lands in its contract and its fake in the same
   commit.
6. **`Node2D` and `Component` subclasses obey the naming rules**: a signal is a
   past-tense verb, a hook takes `_`, and `rgame_` is sealed. See
   [write-ruby-code](../../../.claude/skills/write-ruby-code/SKILL.md).
7. **Every feature works with two players.** A step's specs include a second
   player where the feature is per player.
8. **An asset ships only if it is CC0 or drawn here**, because
   `examples/assets/` ships inside the gem.

## Decisions already taken

Settled in the question round before this plan was written. Not up for
re-litigation inside the plan.

1. **One plan, one roadmap.** The dependencies cross themes: fades feed scenes,
   audio, effects and cutscenes; interaction feeds the inventory and the
   cutscene. Each step still lands alone, so a release may follow any of them.
2. **A long press is declared, not counted by the caller.** `hold: 0.5` makes an
   action press once its buttons have been down that long; `tap: 0.3` makes one
   press on release, and only if released sooner. `held_for` answers the
   duration for a game that wants the number. This is what Unreal and Unity
   both do — see [02](02-prior-art.md#input-a-trigger-per-action-not-a-timer-per-caller).
3. **A combo is a chord.** Buttons down together, `all: [PAD_LB, PAD_RB]`. While
   a chord is held, the plain actions on its buttons read as not held.
   Sequences and double taps go to `possible-todos.md`.
4. **Time enters input through `poll`.** `Players#poll(backend, dt)` down to
   `ActionMapper#poll(backend, dt)`. The break is cheap now and gets no cheaper.
5. **`SceneStack` defers every switch itself** and can name its scenes. The
   deferral is required for correctness, so the engine makes it rather than
   asking each game to.
6. **A transition shows one scene at a time.** Fade out, switch while covered,
   fade in. A crossfade shows two and needs the offscreen render target, which
   stays a possible-todo — and nothing else in this plan needs it.
7. **The hero node crosses a room change.** The old scene hands it over and the
   new one places it at a named entrance. Its components leave the old scene's
   systems and join the new one's through `exit_tree` and `enter_tree`, which
   is what happens to any node that moves.
8. **The debug layer has named channels.** `:stats` and `:shapes` ship, a game
   adds its own, code switches any of them, and a release build turns the
   development keys off.
9. **Pushing is free, and a grid puzzle is an example.** A mover declares
   `pushes:`, and a crate is a mover that only moves when pushed. The
   Sokoban-style block that slides one cell is `OccupiesCell` plus a tween, with
   no engine change.
10. **The inventory ships screens, not items.** A grid, navigation across it,
    focus that crosses menus, tabs switched with the shoulder buttons, and
    scrolling. What an item *is* belongs to the game.
11. **Two inventory examples.** A short one that shows the parts, and one that
    shows a modern screen: tabs, an equipment screen that dresses a character,
    and a bag that says what is worn. The dialogue examples are the precedent.
12. **Interacting is a component; collecting is one too.** `Interactor` picks
    the nearest interactable and emits on the press. `Collectable` frees its
    node when touched, and plays a sound if given one.
13. **Audio gets four transitions**: a fade in and out, a crossfade, pause and
    resume, and a volume per category. Ducking goes to `possible-todos.md`.
14. **A fade is driven by `update`,** like every other tween, with miniaudio's
    own fade as the fallback if stepping the volume 60 times a second is
    audible. The step ships an example to judge that by ear.
15. **Lightning is both a bolt and a storm's flash**, sparkles come from an
    engine emitter, and **additive blending is in scope** because it stays
    inside GL 1.1.
16. **A cutscene is a linear script.** Each step ends after a duration, on a
    signal or on a press. It branches only through a conversation's responses,
    and skipping finishes every remaining step at once.
17. **Split-screen is in scope throughout.** Holds, chords, interacting,
    pushing and the inventory are per player; a scene change and a cutscene are
    for everyone. ~~Two players in two rooms at once is out: the engine has one
    shared world.~~ **Revised when steps 13–16 were re-planned:** the world is
    shared, but two players may stand in two rooms of it at once. See
    [decision 34](#decisions-already-taken).
18. **`examples/equipment` draws its clothes in code.** Taken when steps 5–7
    were re-planned. A hat, a cloak and boots drawn as shapes over `hero.png` add
    nothing to the gem, and constraint 8 allows art drawn here.
19. **A node reads only the presses it saw start, and that is a step of its
    own.** Taken when the re-plan of steps 5–7 was reviewed. A tap of E begun in
    a hero's bag and ended after it closes opened the chest in reach, because
    the mapper computes edges whether a paused hero reads them or not. `Menu`
    already refuses such a press for itself, and steps 5 and 6 each add a clause
    of the same kind. So `Node2D#control` gates it once, for every node, as
    [step 7](04-roadmap.md#step-7--a-node-reads-only-the-presses-it-saw-start),
    before the screens that first pause a hero.

Decisions 20 to 24 were taken in a question round when steps 9–12 were
re-planned. See [what that re-plan found](04-roadmap.md#re-planning-steps-912).

20. **Steps 9–12 are detailed together, and 13 and 14 stay rough.** Step 12's
    transition is sketched on step 10's fade before the fade exists, as step 8
    was sketched on steps 5–7.
21. **No second music track ships.** A second loop would add about 6.5% to a
    1.64 MB gem. `examples/music` shows fades, pause and resume, and category
    volumes on its one track. The adventure, which does not ship, carries a
    second track under `test_projects/adventure/`, and its door crossfades
    between the rooms' music. So no shipped example shows a crossfade, and
    `docs/api/audio.md` does.
22. **A colour that changes every tick has two answers.** A `Color` is frozen,
    and building one a tick is 60 objects a second, the whole default budget.
    `Util::ColorRamp` builds a colour's steps once, for a particle whose hue
    moves over its life. `renderer.faded` multiplies the alpha of everything
    drawn inside it, and `Node2D#opacity` fades a node and its whole subtree
    with it. The second is C, so it lands in step 9 beside the blend mode,
    before the fade built on it.
23. **No scene reads input during a transition.** The scene leaving stands
    still under the cover, and the scene arriving runs under the reveal. A hero
    keeps its last intent until something sets another, so a scene that ran
    without input would walk its hero on into the dark. The press gate refuses
    any press begun during the transition.
24. **A game names its own volume categories.** A song plays under `:music` and
    a sample under `:effects`, unless registered under another name. The device
    holds a group per name in C, sixteen at most, and a name nothing was
    registered under raises rather than changing nothing.

Decisions 25 to 36 were taken in three question rounds when steps 13–16 were
re-planned. See [what that re-plan found](04-roadmap.md#re-planning-steps-1316).

25. **A room is built anew each time it is entered, and what changed in it
    lives in `Facts`.** A return trip and a loaded save then take one path, as
    `Components::Identity`'s header argues: a scene is a recipe and a save file
    is state. Keeping a built room would keep its timers mid-way and its
    connections alive out of the tree, and a save would still need `Facts`.
26. **A connection that outlives its node is disconnected by hand, for now.**
    A scene that listens to a root system in `_enter_tree` ends that in
    `_exit_tree`. The possible-todo "A connection that ends with its node" gets
    a closer look once this roadmap is done, and step 17 records that.
27. **A `CharacterBody` stands still as its node enters the tree.** A carried
    hero otherwise walks on under the reveal, where no scene is controlled. A
    game that wants a walk-in sets an intent after placing the hero.
28. **A game starts a door's music at the request,** itself or on
    `on_requested`, which the stack and the rooms both emit. `on_changed` fires
    after the cover, too late for a crossfade over it.
29. **The adventure's second song lives in `media/`, and the garden plays it
    only when it is there.** `media/` is gitignored and never shipped, so its
    licence need not be CC0: *8BitBattleLoop* found again, or any loop licensed
    for use. The adventure's `main.rb` never names `media/`, so CI keeps
    driving it. Settles [open question 5](#open-questions).
30. **Doors come from the map.** `town.tmx` gains an object layer and
    `garden.tmx` ships beside it, and both examples and the adventure use them.
    A door draws itself, so no tile changes.
31. **Skipping ends a conversation where it stands.** Nobody picks a response,
    so no response's `then:` runs. A script whose outcome must hold either way
    puts it in a `run` after the `talk`, which the skip runs.
32. **A cutscene takes what it stops and gives it back:** the solo, the joins
    and each node it pauses, when it ends, is skipped or leaves the tree. A
    script's closing `run` could be cut off, and `Viewports` sits on the root,
    so a lost one would leave the game solo for good.
33. **A cutscene reads its node's player**, the primary one unless the game
    sets `input_owner`, through the press gate. The game declares the skip
    action with `hold:` and hands the cutscene its name. No default binding
    ships: Escape is `ui_cancel`, and the pad's Start opens the adventure's bag.
34. **Players may stand in different rooms of one world.** `Scene::Rooms` runs
    every room a player stands in, and draws each into its own players' views.
    A move takes the hero who triggered it, or every hero, and one that stays in
    its room only places the hero, so a warp pad and a door are one call. The
    direction is rooms loaded by nearness, and big maps in chunks loaded in the
    background, for open worlds. It is not in this plan: `Rooms#hold` is the
    seam, and step 17 records the rest as a possible-todo.
35. **Music is claimed.** A claim has a key, a song and a priority, and the
    highest priority plays. A room claims its song, and a game claims for an
    event, such as a battle over every room. A game that wants the primary
    player's room claims one key of its own as that player moves.
36. **A cutscene with a camera is for everybody.** It solos the window onto its
    room and stops the other rooms. Without a camera, the same parts make a
    small scene for the one player who walked into it.

## Open questions

1. ~~**Which second music track, and is it worth 90 KB in the gem?** The
   crossfade example needs two loops, and `examples/assets/` has one.
   `examples/assets/README.md` already measured four candidates from the same
   CC0 pack for seam and tail silence. Waits on step 11. Blocks nothing before
   it.~~ **Settled — none in the gem.** See
   [decision 21](#decisions-already-taken). Which track the adventure carries is
   open question 5.
2. ~~**Which keyboard keys stand in for the shoulder buttons?** A tab bar is
   built for LB and RB, and a keyboard needs an answer: `Q`/`E`, which games
   use for shoulder buttons, or `Tab`/`Shift+Tab`, which desktop software uses.
   The universal UI set gains two actions either way. Waits on step 6.~~
   **Settled — Q and E**, beside the shoulder buttons, as `ui_tab_prev` and
   `ui_tab_next`. `E` is also `:interact` in `DEFAULT_ACTIONS`. That is safe
   because a hero pauses while their bag is open, so the two never act at once,
   and step 8's adventure run checks it against a lever in reach. A tap that
   starts in the bag and ends after it closes did reach `:interact`, and
   [decision 19](#decisions-already-taken) is the answer. Tab and Shift+Tab
   lost on two counts:
   Shift is `:grab`, and three examples already bind Tab. See
   [step 6](04-roadmap.md#step-6--tabs-and-scrolling).
3. **Does `Interactor` stay a subclass of `Targeting`?** ~~They answer the same
   question, so the design makes them one class. A facing-aware policy — "what
   am I looking at", not "what is nearest" — may not fit a turret. Waits on
   step 3's landing.~~ **Resolved in step 3: yes.** Nothing the step built
   wanted a facing-aware policy, and the subclass costs one documented
   consequence — `get_component(Targeting)` matches an `Interactor` too, so a
   node holding both is asked by name. A policy that does not fit a turret is
   still a policy, and `POLICIES` is where it would go.
4. **Why does `examples/pathfinding` draw no help lines?** ~~It draws them from
   the scene that holds its `WorldView`, in the `:world` band, and the map covers
   them — a frame captured on `main` shows none. Step 4 found it while
   `examples/block_puzzle` had the same bug, and moved that HUD into the `:hud`
   band. Whether any other example with a map does the same is unchecked, and a
   guard that a HUD is not under the map is the question. Blocks nothing.~~
   **Fixed in all five, and in `block_puzzle`.** `collision_tiles`,
   `jump_topdown`, `scroll_map` and `split_screen` drew their text the same way,
   and captured frames of two of them showed none of it. Each scene now declares
   `band: :overlay` — content drawn once across the window, which `docs/api`
   gives that band — and `block_puzzle`'s strip moved there from `:hud`, which is
   `PlayerLayer`'s. The `WorldView` and each `PlayerLayer` declare their own
   bands, so in every driven report exactly one layer a frame moved, and nothing
   else changed. No check catches a HUD under the map: a driven report counts the
   text calls either way.
5. ~~**Which second track does the adventure carry?** It needs a loop for its
   second room. `examples/assets/README.md` measured three more from the CC0
   pack `music.ogg` came from, and each has a flaw: 0.79 s or 1.48 s of silence
   at the end, or a seam of 34.9%. *8BitBattleLoop* measured clean, but its
   source and licence were not recorded. Waits on step 13. Blocks nothing
   before it.~~ **Settled — a loop in `media/`, played only when it is there.**
   See [decision 29](#decisions-already-taken).
6. **Can a subclass be kept from overwriting `Node2D`'s instance variables?**
   Step 11's `examples/music` kept its own pause flag in `@paused`, which is
   the ivar `Node2D#paused` reads. Pausing the music paused the scene, and its
   next press never arrived. Nothing raised: `SealedPrivates` checks method
   names when they are defined, and an ivar is set, not defined. The
   write-example skill lists the names `Node2D` uses. A guard would need to
   see an assignment in a subclass body, which a RuboCop cop could, given the
   list. Found in step 11. Blocks nothing.
7. **Should a test project's drive script keep its comments?** The pre-commit
   hook leaves alone any path with an `examples/` directory in it, so every
   script under `tools/drive/examples/` keeps the header the write-example
   skill calls the assertion. Scripts under `tools/drive/test_projects/` get no
   such exemption. All ten hold no comment at all. Step 12 wrote one into the
   adventure's script, saying why its tracks wait 32 ticks longer, and the hook
   deleted it. The landed note keeps the reason. Adding `tools/drive` to the
   stripper's exclusions would keep them, and whether a test project's script
   owes a header is the question. Found in step 12. Blocks nothing.
