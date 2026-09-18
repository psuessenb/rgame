# Prior art

Checked against the sources in September 2026, not written from memory. Each
claim below has a link.

## Everyone separates measuring from painting

| Engine | Measure | Needs a frame, a context or a widget? |
|---|---|---|
| Godot 4 | `Font.get_string_size(text, alignment, width, font_size, …)` | No. A `Font` is a Resource. |
| LÖVE 11 | `Font:getWrap(text, wraplimit)` | No. |
| SDL_ttf 3 | `TTF_MeasureString(font, text, length, max_width, &w, &fit)` | No. |
| Unity (TMP) | `TMP_Text.GetPreferredValues(…)`, `textInfo` | **Yes** — it hangs off the text component. |
| rgame today | `Core::Font#text_width` | No, but the type is unreachable from the engine layer. |

The agreement is near-total, and rgame already agrees with it: `font_ext.c` says
`text_width` is "deliberately usable outside `draw`: measuring touches no GL, and
laying out a menu happens while updating, not while drawing". The problem this
plan solves is not that rgame measures at the wrong time. It is that the object
that measures lives on the wrong side of a layering rule.

Unity is the outlier and it is instructive: tying measurement to the component
is what forces the "instantiate a hidden text object to measure with" pattern
that TMP users write. That is the shape option A of `possible-todos.md` would
have produced here — a measurer handed down at runtime — and it is worth not
copying.

## Line breaking: two API shapes

**LÖVE returns the lines.** [`Font:getWrap(text, wraplimit)`](https://love2d.org/wiki/Font:getWrap)
returns the maximum width reached and a sequence of strings, one per wrapped
line. That is the shape `Util::Typeface#wrap` takes, almost verbatim, and
`love.graphics.printf(text, x, y, limit, align)` is the draw-time equivalent.

**SDL_ttf returns how much fits.**
[`TTF_MeasureString(font, text, length, max_width, &measured_width, &measured_length)`](https://wiki.libsdl.org/SDL3_ttf/TTF_MeasureString)
"reports the number of characters that can be rendered before reaching
max_width", and does not render to work it out. The caller loops, advancing
through the string.

**Take SDL_ttf's shape for the C and LÖVE's for the Ruby.** The fit call is what
makes the walk linear overall: each call walks only the text that fits, so the
lengths sum to the length of the paragraph however many lines it breaks into. A
call that instead wrote out every break offset in one pass would need a buffer
sized to the worst case, for no gain. Above it, Ruby slices once per line and
hands back an Array of Strings, which is what a caller wants and what LÖVE
returns.

Godot's [`get_string_size`](https://docs.godotengine.org/en/stable/classes/class_font.html)
takes a `width` and a `justification_flags`, and has a separate
`get_multiline_string_size` with `max_lines` and break flags. Useful as
confirmation that width belongs in the measure call, and as a warning: the flag
surface is large, and none of it is needed until a game ships a script that
breaks between characters.

## Pagination is a real feature, and it belongs below the widget

Unity's TextMeshPro has an
[overflow mode of `Page`](https://docs.unity3d.com/Packages/com.unity.textmeshpro@4.0/manual/RichTextPageBreak.html),
with `pageToDisplay` selecting which page is drawn and `textInfo.pageCount`
answering how many there are. A `<page>` tag forces a break.

That is the feature this plan's requirement asks for — "possibly even multiple
messages" — and TMP puts it exactly where this plan does: the layout object
computes the pages, and the caller sets which one is shown. What TMP puts on the
component and this plan does not is the *advancing*: incrementing
`pageToDisplay` on a click is the caller's loop in Unity too.

## What none of them gives us

- **A measurement type a scene graph may hold.** No engine here has rgame's
  rule that one layer may not name another's classes, so none of them has had to
  make measuring reachable without the graphics half. Godot comes closest —
  a `Font` is a Resource with no context behind it — but a Godot `Font` still
  draws.
- **Measurement with no graphics library in the process.** This is the property
  `spec/rgame/no_graphics_spec.rb` guards and the reason `rake spec` can run a
  simulated hour in milliseconds. It is also what makes the wrapped output of a
  real font assertable headlessly, which no engine above offers because none of
  them needs it.
- **A wrapped paragraph that re-wraps when the language changes.** Every engine
  here re-wraps when the string changes; none ties invalidation to a translation
  generation, because none of them owns the translation table. `Engine::Text`
  does, and `Paragraph` inherits that.

## What was considered and rejected

**Wrapping at draw time, with no cache.** The UI buttons already measure this
way, and it is the smallest possible change — `UI::TextButton#centred_x` calls
`renderer.text_width` every frame and nobody minds. It fails at paragraph scale:
naive wrapping builds a substring per candidate line per frame, which is what
`Game/NoNeedlessAllocation` exists to refuse, and a 60 fps frame that allocates
is a GC pause waiting to happen. `docs/plans/research/roadmap-complexity-estimate-v0.5.0.md`
reached this conclusion independently before this plan existed.

**A measurer handed to the engine layer at runtime** — option A of
`possible-todos.md`. `RGame::Game` exposes a measuring method and nodes call it
by name through `context`, the way they already call `root.context.assets`. It
is allowed by the layering rules and needs no C work at all. It fails on
testing: a headless spec would substitute a fake measurer with invented widths,
so the suite would assert that a paragraph breaks where the *fake* says it does.
That is the fake-drifts-from-real failure the two-suite split exists to catch,
and it would be baked into the design rather than guarded against. It also
cannot measure until a node is in the tree.

**Moving `rgame_rect` to Util so `font.c` can keep using it.** Rects are values
and the project's own rule puts values in Util, so this is defensible on
principle. It is 30 files and 88 call sites to serve one caller that only ever
passes `(0, 0, w, h)`. Splitting the glyph struct costs one small header.
Recorded here because "a rect is a value, why is it in Core" is a reasonable
question that will be asked again.

**Routing `UI::TextButton`'s label through a `Paragraph`.** The two answer a
similar question — put this text in this rectangle — which is the
parallel-vocabulary smell worth checking. It is a false match: a button draws
one line in a fixed slot by an explicit decision, so it would gain a cache with
nothing to cache and an invalidation rule with nothing to invalidate.

**Sources:**
[Font:getWrap — LÖVE](https://love2d.org/wiki/Font:getWrap) ·
[TTF_MeasureString — SDL3_ttf](https://wiki.libsdl.org/SDL3_ttf/TTF_MeasureString) ·
[Font — Godot Engine](https://docs.godotengine.org/en/stable/classes/class_font.html) ·
[Page Break — TextMeshPro](https://docs.unity3d.com/Packages/com.unity.textmeshpro@4.0/manual/RichTextPageBreak.html)
