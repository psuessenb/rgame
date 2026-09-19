# Text measurement, wrapping and a label

**Status.** Step 0 is implemented. Steps 1–3 are detailed; 4–6 are deliberately
rough and get re-planned once the layer beneath them exists.

Read in order:

| | |
|---|---|
| [01-current-state.md](01-current-state.md) | what the text stack does today, and what blocks the goal |
| [02-prior-art.md](02-prior-art.md) | how other engines split measuring from painting |
| [03-design.md](03-design.md) | the proposed design |
| [04-roadmap.md](04-roadmap.md) | the implementation order |

## Verdict

**Move the pure typeface to `RGame::Util` and give it line breaking; build
`RGame::Core::Font` on top of it; add `Engine::Paragraph` to cache wrapped lines
and `UI::Label` to draw them.**

The cross-extension problem that stalled this is not a problem. `possible-todos.md`
framed it as a choice between compiling a copy in both extensions and reading one
extension's C struct from the other, and called it "the real design question".
There is a third answer and the project already uses it: **both extensions
compile the same source out of `ext/rgame_util/`, and nothing crosses the `.so`
boundary in C.** `Core::Font` asks a `Util::Typeface` for its font bytes through
Ruby and opens its own face from them — 0.014 ms and 400 KB per font, measured,
against a font already copied once per size today. `ext/rgame_util/color.h` took
the same decision at header scale and says so in its own comment.

The second thing that falls out is worth as much as the feature: **the headless
suite stops inventing text widths.** `FakeRenderer` returns `length * 8.0`
because `spec/` has no font. With the typeface in Util it measures with the real
shipped face, no SDL, no window — so a spec can assert the actual lines a
paragraph breaks into, in every language the game ships.

## The goal

A game passes a paragraph to a node and gets lines. It does not pre-format the
text, because the paragraph is a different length in every language and its
variables change while the game runs.

## Hard constraints

1. **`RGame::Engine` may not name `RGame::Core`** — no require, no constant, no
   attribute, not in its specs. It may hold `RGame::Util` types outright.
2. **`RGame::Core` may not name `RGame::Engine`.** `RGame::Game` is the only
   class allowed to name both.
3. **`require "rgame"` loads no graphics library.** `spec/rgame/no_graphics_spec.rb`
   asserts it. Everything this plan adds to Util must hold that.
4. **Measured and drawn must agree to the pixel.** `text/font.h` states it: one
   walk, used by measuring and by drawing, because two loops drift the moment one
   forgets kerning.
5. **Nothing on a draw path reads a clock, and nothing allocates per frame.**
   `Game/NoNeedlessAllocation` and `Game/NoInterpolationInHotPath` are the guards.
6. **`spec.files` stays a glob.** Anything new that the installed gem compiles
   from or reads at runtime ships because it is in the tree, not because someone
   listed it.

## Decisions already taken

Settled in the question round with the user. **Not up for re-litigation inside
this plan.**

- **Line breaking runs in C, next to the cursor.** Summing word widths and
  adding a space is a second loop that agrees with the first only until someone
  touches either — constraint 4. The Ruby alternative also measured 20× slower
  and allocated a String per candidate rather than per line.
- **`Engine::Paragraph` is a second class holding a `Text`**, not `Text` grown a
  `lines` method. `Text` keeps its single job; every label in the game would
  otherwise carry wrapping state it never uses.
- **`Core::Font` is always built from a `Util::Typeface`.** The documented
  `Font.new(app, 18)` and `Font.new(app, 18, path:)` stay, as sugar that builds
  one first. Additive was the alternative, and it leaves "wrap with the face you
  draw with" as a rule someone remembers.
- **This plan ships `UI::Label`, not a paging text box.** `Paragraph` breaks
  text into lines *and* groups lines into pages; `Label` draws one page.
  Deciding which page and what advances it belongs to the dialogue plan, next to
  the beat queue and the branching choices. A box built here would be built
  twice.
- **The Util type is `Util::Typeface`.** The C already calls it that, and
  `Util::Font` beside `Core::Font` is two classes one `require` apart.
- **Buttons keep their fixed sizes.** The user's call: menus in a game are not
  generated the way a web page is. No existing UI class changes shape.

## What this does not deliver

- **No typewriter reveal, no beat queue, no branching choices.** That is the
  dialogue plan, which this unblocks.
- **No content-sized buttons**, no `item_width: :content`, no menu that
  re-arranges itself when the language changes.
- **No general layout model** — no nesting, no scrolling, no text entry. The
  `docs/api/ui.md` "What this is not" list keeps three of its four items.
- **No breaking between characters**, so no CJK line breaking. The shipped font
  covers no script that needs it.
- **No rich text**: no colour spans, no inline icons, no per-run styling.

## Open questions

Each says what it waits on. None blocks step 0.

1. **Does a `Paragraph`'s width ever change after construction?** A resizing
   box would want it; nothing in the requirement does. Settle when `UI::Label`
   is built (step 5) — if the answer is no, the width is frozen and the cache
   loses an input.
2. **Should the renderer gain a multi-line draw call?** `UI::Label` will step by
   the line height in a loop. If a second caller wants the same loop, it belongs
   on the renderer, and then `FakeRenderer` and the `a_renderer` contract follow.
   Decide after step 5, with a real caller in hand.
3. **Where does the default typeface's size come from?** `Renderer::FONT_SIZE`
   is 18 and lives in Core, which Util may not name. Either Util carries its own
   default and Core reads it, or the number is duplicated with a spec that
   compares them, the way `Util::Controls` is checked against the C header.
   Blocks step 1's `Typeface.default`.
4. **Does `Util::Typeface` need an ascent or a descent on the Ruby side?**
   The C has both. Nothing asks yet; a caller aligning two faces on one line
   would. Leave out until something asks.
