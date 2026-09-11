---
name: write-example
description: How to write an example under examples/ — the file shape, the drive script that acceptance-tests it, the asset licence rule, and the traps that have actually bitten (a top-level proc pinning the window, a save key that also walks the player, paused not gating draw, a nine-slice id that resolves to nothing). Use when adding or changing anything under examples/ or tools/drive/examples/, when picking the next example off docs/plans/basic-examples.md, or when a driven example prints no report.
---

# Writing an rgame example

An example is a **single file a stranger reads top to bottom**. It is not a
game and not a test project: it makes one point, and everything in it is there
to make that point. `test_projects/` is where whole games live.

Examples ship inside the gem. `tools/` does not, so a drive script costs
nothing and an asset costs a redistribution licence.

---

## The shape of the file

Every example is `examples/<name>/main.rb`, and they all open the same way:

```ruby
# frozen_string_literal: true

# <Name> — <one line saying what it shows>.
#
# Run it:
#
#   ruby examples/<name>/main.rb
#
# <which keys do what>. It exercises:
#   - <Class> — <what it contributes, in a clause>;
#   - <Class> — <the same>.
#
# ## <the one thing to watch>
#
# <prose: the point of the example, and what it deliberately does not solve>

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'
```

`examples/walk/main.rb` is the shortest one filled in.

Four rules for the header:

- **Name the keys.** A reader who cannot make it do anything learns nothing.
- **"It exercises:"** lists the classes by name, so the file is findable from
  the class and the class is findable from the file.
- **Say what it does not solve.** `examples/game_menu` says its menu is at a
  fixed inset because centring needs a size that only exists at draw time.
  That sentence is what stops a reader copying a limitation as if it were a
  design.
- **No history.** Same rule as `docs/`: no "used to", no "now", no "still".
  Written for someone who has only the current code.

The end of the file is the wiring: `RGame::Game.new(...)`, any registration, and
`game.start`.

---

## The trap that costs a day: a top-level proc pins the window

**Symptom:** the driven run prints *no report at all* and exits 1. The example
is fine when run by hand. Sometimes `X connection to :97 broken` appears too,
sometimes not.

**Cause:** a block written at the **top level of the script** captures that
script's local variable scope — including `game`, further down the file, because
Ruby builds the scope's variable table at compile time. Assign that block to a
constant and it lives for the life of the process, so the `App` is never freed,
so it is torn down after the harness has already killed Xvfb, and the process
dies through a C-level `exit` that never flushes Ruby's buffered stdout. The
report is written and then thrown away.

```ruby
# Wrong — VOLUME_LABEL pins `game` for ever.
VOLUME_LABEL = ->(percent) { "#{percent}%" }
# ...
game = RGame::Game.new(...)
```

```ruby
# Right — a class body has no local scope to capture.
class Settings
  ROWS = { volume: { display: ->(percent) { "#{percent}%" } } }.freeze
end
```

It applies to any long-lived proc made at the top level, not just a lambda in a
constant. Anything a script needs a proc for belongs in a class.

**To confirm a leak of this kind**, count live apps at exit:

```ruby
at_exit do
  3.times { GC.start(full_mark: true, immediate_sweep: true) }
  warn "live Apps: #{ObjectSpace.each_object(RGame::Core::App).count}"
end
```

Zero is correct. One means something outlives the run — and the usual suspects
are a proc, a constant, or a process-global that was never let go of.
`RGame::Engine::AudioBus` was exactly that: it held the audio device, which held
the asset manager, which held the window, and nobody noticed until something
reached through it. `RGame::Game` owns the director for that reason.

---

## Input: a key already in the default map keeps its old job too

**Two actions may read one key, and both fire. Nothing warns.**

`move_y` is bound to W and S. A `save` action added on S saves *and* walks the
player downwards — which reads as "save does not work" because the movement is
the thing you see. Verified with synthetic keystrokes: the save happened every
time.

- **F1 and F2 are not free.** `RGame::Game` keeps them for the debug overlay and
  quit.
- **Escape is deliberately not bound by the engine**, because it is every game's
  natural back button.
- F5, F9 and Delete are free, and are what a player already expects.
- Sharing a key is fine when nothing reads the other action. `examples/save_load_ids`
  puts `shear` on Space, which the default map has on `fire` and `ui_confirm`,
  and nothing in that example reads either.

`ui_up` / `ui_down` / `ui_left` / `ui_right` / `ui_confirm` / `ui_cancel` all
come from the universal set every map is merged over, so a menu needs no
declaration at all.

---

## Scene graph and draw path

**`paused` gates `control` and `update`. It does not gate `draw`.** A paused
node and its whole subtree stop ticking and keep drawing. Hiding a subtree means
not descending into it:

```ruby
def draw_children(renderer, view)
  super if @open
end
```

**Draw from `view`, not from `WIDTH`/`HEIGHT`.** Those constants are what the
window *opens* at. Under fullscreen the view is the screen; under a scale mode
it is the logical size. `view.width` is the only honest answer to "how big is
the thing I am drawing in", and reading it is what makes a layout follow a
fullscreen switch with nothing listening for the change.

**No clock on a draw path, ever.** Cosmetic animation accumulates its own
elapsed seconds in `update(dt)` and hands the number to the renderer.

**No String built per frame.** `renderer.text("#{n} plays", ...)` allocates every
frame; `Game/NoInterpolationInHotPath` refuses it and is right. Build one frozen
string per state in a constant hash, or count in rectangles. `to_s` on an id is
the same bug without the interpolation — build the label in `initialize`.

**`[n, MAX].min` allocates nothing** despite the array literal: the VM compiles
it to a single `opt_newarray_send`. Measured at 0 objects over 200,000 calls.
Do not write around it — the cop knows, and `Style/MinMaxComparison` asks for
exactly this form.

**Colours are `RGame::Util::Color`.** A raw `0xFFFFFFFF` raises `TypeError`.

---

## Assets

**The test is not "may I use this" but "may I hand copies to everyone who
installs rgame".** `examples/assets/` ships inside the gem, so it is CC0 or
authored here, with nothing in between — a licence that merely permits use, or
asks for a credit line, attaches an obligation to rgame and to everyone
downstream. `media/` is gitignored precisely because its contents fail that
test, so **an example may never read from it**. Record provenance in
`examples/assets/README.md` even when the licence does not require it.

**Vet an audio loop for trailing silence.** A track that "loops" by ending in a
second of quiet sounds fine in a seam measurement and wrong to a player. Measure
the silence, not just the seam.

**Almost everything resolves by path. Nine-slices do not.**

| id | resolves how |
|---|---|
| `'hero.json'`, `'blip.ogg'`, `'town.tmx'` | a String is a path, resolved through the asset manager on first use and remembered |
| `:hit`, `:panel` | a Symbol is a name the game chose, and must be registered |

A nine-slice id names an **element of an atlas**, not a file, so there is nothing
for the manager to resolve it to. One line, and it is the only registration a
menu example needs:

```ruby
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))
```

This is worth checking against the plan before believing "this example needs no
assets" — `UI::MenuItem` draws nine-slices, which made `examples/game_menu`
asset-gated when the plan said it was not.

---

## The drive script is the acceptance test

Every example gets one, at the **mirrored path**: `examples/menu_navigation/main.rb`
is driven by `tools/drive/examples/menu_navigation.rb`.

```
ruby tools/drive_test_project.rb examples/<name>/main.rb --ticks 240
```

Booting is not driving. The report counts what the game actually asked for —
scenes entered, draw calls with first and last arguments, clips, translates,
sounds, ticks against frames — and a plain boot of a game whose menu answered
nothing reported "90 ticks, 90 frames" and looked perfectly healthy.

**The script's header comment says what the report should show.** That is the
assertion, and it is the part to get right:

- **Read it off a real run.** A plausible-sounding claim about coordinates is a
  claim about a sign convention. One about `scroll_map`'s translate range was
  wrong because a camera offset is negative while the rig's position is
  positive, and only a real report showed it.
- **Assert on structure**, not exact counts — scenes entered, sounds fired, clip
  and translate counts, a number changing between two stretches of the run.
  Exact draw counts are comparable only with `--seed N`.
- **Never activate Quit.** It closes the game, the run ends before its tick
  budget, and the report looks like a crash. Say so in the header.
- **Set `RGAME_SAVE_DIR`** for anything that saves, so a run neither writes into
  the home directory of whoever runs it nor reads a file an earlier run left —
  which would change what the script does. Do not override `XDG_DATA_HOME`
  instead: that breaks mise's Ruby.
- **Seed the example's own RNG** from `ENV.fetch('RGAME_SEED', DEFAULT_SEED)`, so
  a run with nothing saved is reproducible and `--seed N` can override it.
- **Leave the window windowed.** There is no window manager on Xvfb, so a
  fullscreen window left behind at the end of a run stays mapped and holding the
  display, and the *next* window's loop never receives the events that drive it —
  a hang with no failure and no output. A script that goes fullscreen switches
  back before it ends.

**Never measure allocations under the harness.** It records every draw call with
its arguments, and that recording is hundreds of times whatever the game itself
allocates — `examples/pooling` reads about 140 objects a second plainly and
85,000 under the harness, in both of the modes it exists to compare. Run the
example directly for any number about the game's own cost.

If the report does not show the thing you need, **extend the harness** rather
than eyeballing the window. `AudioProbe` did not record `stop_music`, so a game
stopping its music left no trace anywhere in any report.

---

## Debugging a driven run that produces nothing

In order, because each step is cheaper than the next:

1. **Run the example by hand** under a display (`DISPLAY=:N ruby examples/…`).
   If it survives, the example is fine and the problem is at shutdown — go to
   the live-App count above.
2. **Bisect in place.** Copying `main.rb` elsewhere breaks
   `ASSETS = File.expand_path('../assets', __dir__)`, so the copy fails for a
   different reason and the bisect means nothing. Keep the original safe and cut
   the real file down.
3. **`warn` markers**, not `puts`. stderr is unbuffered; stdout is not, and a
   process that dies through a C-level exit loses everything still buffered —
   which is the whole reason the report goes missing.
4. **Backtrace a hang** by launching the process under gdb rather than attaching
   to it. Check `/proc/sys/kernel/yama/ptrace_scope` first: at 1, which is the
   default on this machine, only a parent may attach and `gdb -p` simply fails.

---

## Finishing

```
bundle exec rubocop examples/<name>/main.rb <any lib file you touched>
bundle exec rake spec            # the engine layer, headless
ruby tools/drive_test_project.rb examples/<name>/main.rb --ticks 240
```

Plus `rake spec:core` and `make test` if the example needed engine or C work.

New engine code that an example needs is **still engine code**: a control goes
in `lib/rgame/engine/ui/` with its own spec in `spec/`, a section in the matching
`docs/api/` page, and — if the page has a "What this is not" list — that list
trimmed to what is still genuinely missing.

Then update `docs/plans/basic-examples.md`: mark the entry done, record what the
example decided about any open question it was carrying, and write down anything
learned that the next example would otherwise rediscover.
