# Smooth art

**Steps 1–4 are implemented.** Step 5 is rough, and gets re-planned before it
starts.

## Verdict

rgame can draw anti-aliased art cleanly after three changes, none of which needs
more than OpenGL 1.1.

- **The engine premultiplies every image at load.** Filtering can then no longer
  pull a transparent pixel's black into an edge, so no exporter has to remember
  to bleed edge colours.
- **A game-wide `texture_filter: :linear` switches sheets to linear filtering.**
  A sprite sliced from a shared sheet samples half a texel inside its own edges,
  so its neighbour never leaks in.
- **`RGame::Game` first takes its settings as one `Game::Configuration`.**
  Otherwise the filter would be its fifteenth keyword.

Pixel-art games do not change. `:nearest` stays the default, and premultiplied
blending draws the same pixels as straight blending, within 1 per channel.

## Goal

A game whose art is drawn with anti-aliasing at 1280×720 looks clean in a
1920×1080 window under `:letterbox`. Lines keep an even thickness, edges have no
dark fringe, and no sprite shows a strip of its neighbour on the sheet.

The requirement, as it arrived:

> rgame's docs say images always use nearest-neighbour sampling, with no setting
> to change it. With anti-aliased art, any non-integer scaling (e.g. `:letterbox`
> from 1280×720 to 1920×1080) makes lines jaggy and uneven in thickness.
> Switching on linear filtering has its own trap: transparent pixels in PNGs are
> usually black, so edges get dark fringes. The exporter can prevent that by
> bleeding the edge colors into the transparent pixels (a cheap fix on the export
> side).

## Hard constraints

1. **OpenGL 1.1, and no loader.** Every call and enum this plan adds exists in
   1.1: `GL_LINEAR`, `GL_INTENSITY`, `GL_LUMINANCE`, and `glBlendFunc` with
   `GL_ONE`.
2. **A pixel-art game changes nothing in its code and nothing on screen.** The
   default stays `:nearest`. Premultiplied blending matches straight blending
   within 1 per channel.
3. **`require "rgame"` still loads no graphics.** `Game::Configuration` lives
   with `Game`, under `rgame/game`.
4. **Nothing new allocates on a per-frame path.** Premultiplying a vertex colour
   is C integer arithmetic on bytes the canvas already writes.

## Decisions already taken

These were settled in conversation and in one round of questions. They are not
up for re-litigation inside this plan.

1. **`root` and `caption` stay keywords on `Game`; everything else moves into
   `RGame::Game::Configuration`, passed as `configuration:`.** The keyword list
   is 14 long and grows with every setting. This refactor is step 1.
2. **`width` and `height` move too**, although 43 of the 44 games in the
   repository pass them. `scale_mode` decides what they mean (`game.rb:75`),
   so the size and its mode belong in one object.
3. **`input:` and `audio:` move too.** The drive harness writes
   `configuration.with(input: scripted)` rather than adding a keyword. Otherwise
   every future seam would grow the list again.
4. **`Configuration` is a `Data.define` with a default for every member.**
   `Configuration.new(width: 1280)` builds one, and `with` derives another. No
   builder is written, and there is no `Configuration.default`, since it would
   equal `Configuration.new`. It nests under `Game`, so `Game` stays the only
   class directly under `RGame`, as CLAUDE.md states.
5. **The engine premultiplies alpha at load, for every image.** Bleeding edge
   colours was the alternative; see [Considered and
   rejected](#considered-and-rejected).
6. **The setting is `texture_filter: :nearest | :linear`, defaulting to
   `:nearest`.** Godot, LÖVE, raylib and Unity use the same two words, and a
   third value fits if mipmaps arrive.
7. **One filter per game.** A per-image override waits for a game that mixes
   both styles.
8. **Shrinking art is out of scope.** Art drawn at under half its size needs
   mipmaps, and nothing asks for that yet.
9. **`Game` gets no `configuration` reader until a caller needs one.**
   `scale_mode` and `fullscreen?` already answer for the live state, and a
   stored configuration goes stale the moment `scale_mode=` runs.
10. **The filter cannot be switched while the game runs, until a game needs
    it.** A "crisp or smooth" setting is the trigger. After step 3 each sheet
    knows its filter, so a switch would set two parameters on every live sheet.
    Step 5 records this in `possible-todos.md`.
11. **Step 4's example draws the two figures alone.** Drawing a smooth tileset
    and a nine-slice panel would take far longer than the figures did. Neither
    would show anything the figures and the readbacks do not: both draw through
    `image_at`, as every image does. A readback on generated tiles pins the
    tile map instead. Taken when step 4 was re-planned, after step 3 landed.

## Open questions

1. ~~**Does `Game` expose its configuration?**~~ **Settled: no, not until a
   caller needs it.** See decision 9 under
   [Decisions already taken](#decisions-already-taken).
2. ~~**Where does step 4's art come from?**~~ **Settled for the figures: two
   drawn for rgame**, `examples/assets/older-man@1x.png` and `woman@1x.png`.
   See "Art" under [step 4](#step-4--examplessmooth_art-on-the-two-figures).
   The tileset and the nine-slice panel still need art; see question 5.
3. ~~**Should the filter be switchable while the game runs?**~~ **Settled: no,
   not until a game needs it.** See decision 10 under
   [Decisions already taken](#decisions-already-taken).
4. **Why did `ChildRuby`'s deadline not end a child that hung on Windows?**
   Blocks nothing in this plan. In step 3's first CI run, the Windows job hung
   for 15 minutes in `game_locales_spec.rb`'s "reads an absolute locales:
   directory as it stands", until the job was cancelled. The example is
   unchanged since step 1, and a re-run passed it in the usual time. Its child
   goes through `ChildRuby.capture`, which kills a child after 60 seconds.
   After the kill, it still waits on the process and on the child's output
   with no limit, so a child that Windows does not end, or whose pipes stay
   open, holds the suite regardless. It belongs on a branch of its own; step 5
   moves it to `possible-todos.md` if nobody has taken it by then.
5. ~~**Where do step 4's tileset and nine-slice panel come from?**~~
   **Settled: step 4 needs neither.** See decision 11 under
   [Decisions already taken](#decisions-already-taken).
6. **Does switching to fullscreen resize GL's drawable outside Xvfb?** Blocks
   nothing in this plan. Under Xvfb, after the switch only the window's old
   1280x720 of the back buffer draws, and leaving fullscreen keeps the screen's
   size; see step 4's landed note. Xvfb has no window manager, so a desktop may
   well behave. Running `examples/smooth_art` on one and pressing F twice
   answers it. If the desktop shows the same, it is a bug in `App#fullscreen=`
   and gets a branch of its own; if not, step 5 drops the question.

## What was measured before planning

Taken at `78e7e4f`.

| | |
|---|---|
| Keywords on `Game#initialize` | 14: `root`, `width`, `height`, `caption`, `media_root`, `input_map`, `device`, `players`, `input`, `audio`, `fullscreen`, `scale_mode`, `locales`, `seed` |
| Places that construct a `Game` | 56: 38 examples, 5 test projects, the generated project's `game.rb.tt`, `README.md`, and 11 snippets in `docs/api/`. Three `spec_core` specs build one in a child process, and `tools/drive_test_project.rb:783-786` prepends to `initialize` |
| Keywords passed, out of 56 | `root` 56, `caption` 49, `width` 47, `height` 47, `media_root` 41, `locales` 39, `input_map` 22, `seed` 9, `players` 7, `scale_mode` 4, `fullscreen` 3; `device`, `input` and `audio` 1 each, all in `game.md`'s full listing |
| Files naming a `Game` keyword in prose | 18, among them `CLAUDE.md` (`Game.new(players: 2)`, "`RGame::Game`'s `input:` keyword"), 9 pages in `docs/api/`, and 2 drive scripts |
| What the harness adds | `input:`, or `device:` under `--gamepad`, plus `audio:` when recording |
| `Data.define` in `lib/` | 9 uses; the house idiom for a value |
| `Metrics/ParameterLists` | disabled in `.rubocop.yml`, so a 13-keyword `initialize` needs no exception |
| Filtering today | `GL_NEAREST`, hardcoded at `ext/rgame_core/graphics/image.c:128-129`. Font pages use `GL_LINEAR` and `GL_ALPHA` (`text/font_atlas.c:121-126` and `:386`) |
| Blending today | straight alpha: `GL_SRC_ALPHA` as the source factor for both modes (`graphics/gl_backend.c:22`) |
| Where vertex colours are written | two places, both in `graphics/canvas.c`: `write_vertex` (`:266-267`) and `rgame_canvas_replay` (`:334-336`) |
| How a recording gets its colours | `rgame_recording_capture` copies the draw queue, so it holds what `write_vertex` wrote |
| Check tests asserting a translucent vertex colour | 4: `the_colour_reaches_the_vertex_in_gl_byte_order` in `test_canvas.c`, and three replay tests in `test_recording.c` |
| Callers of `rgame_texture_sheet_create` | `image.c`, and `test_texture.c`, `test_recording.c`, `test_primitives.c` |
| Callers of `rgame_app_create` | 2: `src/main.c` and `ruby/core_ext.c` |
| Pixel readback | `spec_core/support/rendered_frame.rb`, used by 6 specs, with PNGs written by `PngFixture` |
| `make test` | 412 checks, 0 failures, 1.5 s |
| `rake spec` | 4,514 examples, 0 failures, 36.8 s |
| `rake spec:core` | 533 examples, 0 failures, 15.8 s |

## What resembles this

**Reuse it.**

- `rgame_texture_uv` computes every UV in the engine, so the half-texel inset
  changes one function.
- `App`'s `media_root:` is set once at construction, with a reader and no
  writer, because the asset cache would otherwise hold assets made under two
  values. `texture_filter:` is the same kind of setting, for the same reason,
  and takes the same shape.
- `RenderedFrame` and `PngFixture` already read back pixels drawn from
  generated PNGs.
- `Presentation` keeps deciding scale and offset. Nothing in it changes.

**Extend or generalise it.**

- **The two blend modes share one source factor.** Under premultiplied alpha,
  `:alpha` and `:add` both take `GL_ONE` and differ only in the destination
  factor. The multiply mode in `possible-todos.md` fits the same shape.
- **The font atlas becomes premultiplied like every other texture.** Its
  `GL_ALPHA` pages are the one texture whose colour does not come from its
  texels. `GL_INTENSITY` makes a glyph's coverage scale all four channels, as
  a premultiplied texel does.

**Genuinely new.**

- `graphics/pixels.c`. Nothing touches decoded pixels between stb and the
  upload today.
- `Game::Configuration`. Nothing else groups a game's start-up settings. Its
  nearest relative is `InputMap.default.merge`, a value derived from a default,
  and `Data#with` gives `Configuration` the same idiom.

## Prior art

| Engine | Filter | Dark fringes |
|---|---|---|
| Godot 4 | a project-wide default, `default_texture_filter` (linear), with an override per `CanvasItem` | the importer's `fix_alpha_border` bleeds edges and is on by default; `premult_alpha` is off by default |
| Unity | per texture: point, bilinear or trilinear | the importer's "Alpha Is Transparency" dilates colour into transparent pixels |
| LÖVE | `love.graphics.setDefaultFilter`, read when an image is created, and `Image:setFilter` per image | left to the game: every blend mode takes `"alphamultiply"` or `"premultiplied"` |
| XNA 4.0, MonoGame | per draw, through `SamplerState` | the content pipeline premultiplies at build time, and `BlendState.AlphaBlend` is `One, InverseSourceAlpha` |
| raylib | `SetTextureFilter` per texture, point by default | left to the game |

They agree on a default read when a texture is created, plus a way to override
it. They split on fringes: XNA premultiplies, while Godot and Unity bleed edge
colours at import.

**None of them works without an import step.** Each fixes fringes in a pipeline
that runs before the game, whether an importer or a content build. rgame loads a
raw PNG at runtime, so load time is the only place the engine can fix it, and
the fix must be cheap enough for every load. Premultiplying is one pass of three
multiplies per pixel. Bleeding searches outward from every edge.

Sources:
[Godot, importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html);
[Godot, `default_texture_filter`](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-textures-canvas-textures-default-texture-filter);
[Unity, default texture import settings](https://docs.unity3d.com/Manual/texture-type-default.html);
[LÖVE, `setDefaultFilter`](https://love2d.org/wiki/love.graphics.setDefaultFilter);
[LÖVE, `BlendAlphaMode`](https://love2d.org/wiki/BlendAlphaMode);
[Shawn Hargreaves, premultiplied alpha in XNA 4.0](https://shawnhargreaves.com/blog/premultiplied-alpha-in-xna-game-studio-4-0.html);
[raylib cheatsheet](https://www.raylib.com/cheatsheet/cheatsheet.html).

## Considered and rejected

- **Bleeding edge colours into transparent pixels at load.** It leaves
  blending alone and is one function in `image.c`. But it fixes only pixels
  that are fully transparent. An anti-aliased edge is partly transparent, and
  straight-alpha filtering still weighs its colour wrongly. A render target
  will need premultiplied alpha anyway.
- **Extruding every sprite's border at load**, as TexturePacker's "extrude"
  does. It would stop sheet bleeding without touching UVs. But the loader
  cannot know where a sheet's sprites are: `subimage` and `tile` slice after
  the upload, as views on one texture.
- **A low-resolution render target, scaled linearly.** One filter would cover
  the whole frame, with no setting per texture. But it is the loader threshold
  `possible-todos.md` describes, it does nothing for fringes, and text would
  stop rasterising at full resolution.
- **`App` takes the configuration.** That would remove the overlap between
  `App`'s keywords and `Configuration`'s members. But Core may not name a
  `Game` type, and `spec_core` and `ext/rgame_core/example.rb` build an `App`
  with keywords. `Game` stays the one place that unpacks one into the other.
- **`Game.new(root:, caption:, **settings)`.** Callers would change least. But
  a misspelt key would need a check of its own, and the list would be invisible
  to readers and to the docs. `Data` raises on a misspelt member for free.
- **A chainable builder, `pixel_art:`, and a filter per image.** Each was a
  lettered choice in the question round; see decisions 4, 6 and 7.

## What this plan does not deliver

- Art drawn at under half its size. That needs mipmaps.
- A filter per image, or a Tiled tileset choosing its own.
- Switching the filter while the game runs; see decision 10.
- A render target, or any post-processing.
- Tiles that blend into each other at a non-integer scale. Each tile clamps to
  its own edge texel, so two tiles meet in a step, much as they do under
  `:nearest`.
- Snapping positions to whole pixels.
- Any change to how text looks. Glyphs are already filtered linearly, and only
  their texture format changes.
- An example with a tile map or a nine-slice panel in smooth art. Both draw
  through the path the figures take, and step 4's readback pins the tile map.
  Such an example waits for the art; see decision 11.

---

## Roadmap

### Dependency shape

```
1 Game::Configuration ───┐
                         ├─→ 3 texture_filter ─→ 4 example ─→ 5 fold back
2 premultiplied alpha ───┘
```

Steps 1 and 2 depend on nothing in this plan and can land in either order. Step
3 needs step 1 for its configuration member. It needs step 2 because linear
filtering without premultiplied alpha draws the fringes this plan removes.

### The invariant every step preserves

> **Under the default `:nearest`, every existing game draws what it drew
> before.** Every driven project enters the same scenes, plays the same sounds
> and makes the same draw calls. Every readback spec reads the same pixels,
> within 1 per channel where alpha is partial.

Check it by driving every example and test project with `--seed 1 --texts` at
the step's parent commit and at its head, then diffing the reports.

### What lands early, if the plan is abandoned

| Step | Closes |
|---|---|
| 1 | a constructor of 14 keywords that grows with every setting |
| 2 | straight-alpha blending, which a render target would composite wrongly and a multiply blend mode cannot be built on |

---

### Step 1 — `RGame::Game::Configuration`

`Game#initialize` takes 14 keywords, and `texture_filter:` would be the 15th.
Doing this first means step 3 adds a member rather than a keyword. It depends on
nothing else in the plan.

```ruby
# lib/rgame/game/configuration.rb
module RGame
  class Game < RGame::Core::App
    Configuration = Data.define(:width, :height, :scale_mode, :fullscreen, :media_root,
                                :locales, :players, :device, :input_map, :seed,
                                :input, :audio) do
      def initialize(width: 640, height: 480, scale_mode: :letterbox, fullscreen: false,
                     media_root: 'media', locales: 'locales', players: 1,
                     device: RGame::Util::Controls::KEYBOARD, input_map: nil, seed: nil,
                     input: nil, audio: nil)
        super
      end
    end
  end
end
```

```ruby
# lib/rgame/game.rb
def initialize(root:, caption: 'RGame', configuration: Configuration.new)
  super(width: configuration.width, height: configuration.height, caption:,
        media_root: configuration.media_root, fullscreen: configuration.fullscreen)
  # every other read goes through configuration
end
```

`Game::WIDTH` and `Game::HEIGHT` go, and the defaults live on `Configuration`
alone. An example passes one inline:

```ruby
RGame::Game.new(
  root: Scene.new,
  caption: 'Sprite',
  configuration: RGame::Game::Configuration.new(width: WIDTH, height: HEIGHT,
                                                media_root: ASSETS, locales: LOCALES)
)
```

The generated project keeps its configuration in a constant. A subclass finds
`Configuration` through its ancestors, so it needs no prefix:

```ruby
class Game < RGame::Game
  WIDTH = 640
  HEIGHT = 480
  CONFIGURATION = Configuration.new(width: WIDTH, height: HEIGHT,
                                    media_root: File.join(__dir__, 'assets'))

  def initialize(configuration: CONFIGURATION)
    super(root: Root.new, caption: '<%= caption %>', configuration:)
  end
end
```

The drive harness overrides the game's own configuration, whatever it holds:

```ruby
define_method(:initialize) do |configuration: RGame::Game::Configuration.new, **kwargs|
  extra = pad ? { device: RGame::Util::Controls.gamepad(0) } : { input: input }
  extra[:audio] = AudioProbe.new(RGame::Core::Audio.new, report) if recording
  super(**kwargs, configuration: configuration.with(**extra))
  # ...
end
```

**The old keywords get no deprecation path.** `Game.new(root:, width: 800)`
raises Ruby's own `ArgumentError: unknown keyword: :width`. No game outside this
repository is known to exist yet, so a shim would guard nobody, and the error
already fails loudly.

Rules the tests pin:

1. `Game.new(root:)` builds the same game as today, with every default
   unchanged.
2. Every member of `Configuration` reaches the game. A member `Game` forgets to
   read fails a spec, rather than doing nothing for a player.
3. A misspelt member raises `ArgumentError` from `Configuration.new` or `with`,
   naming it.
4. An old keyword passed to `Game.new` raises `ArgumentError`.
5. The harness's `input:`, `device:` and `audio:` win over the game's own
   configuration.

Tests:

- `spec_core/rgame/game_configuration_spec.rb`, which builds its game in a child
  process as `game_random_source_spec.rb` does:
  - `Game.new(root:)` alone opens 640×480, under `:letterbox`, with one player on
    the keyboard and `'media'` as its media root.
  - Every member reaches the game, read back through one probe per member:

    | Member | Read back through |
    |---|---|
    | `width`, `height` | `game.width`, `game.height` |
    | `scale_mode` | `game.scale_mode` |
    | `fullscreen` | `game.fullscreen?` |
    | `media_root` | `game.media_root` |
    | `locales` | a table in that directory shows in `RGame::Engine::I18n.available` |
    | `players` | `game.players.count` |
    | `device` | `game.players.primary.device` |
    | `input_map` | an action only this map declares, in `game.players.primary.input_map` |
    | `seed` | `game.random_source.seed`, with `RGAME_SEED` unset |
    | `input` | a stub backend that `game.update` polls |
    | `audio` | `game.audio` is the object passed |

  - The probes' keys equal `Configuration.members`. A member added without a
    probe fails here, which is what makes rule 2 hold for members not yet
    written.
  - A misspelt member raises, naming it.
  - `Game.new(root:, width: 800)` raises.
- `game_random_source_spec.rb`, `game_locales_spec.rb` and `game_tilemap_spec.rb`
  build their game through a configuration.
- `spec/rgame/cli/generated_project_spec.rb` passes against the new template.

Sub-steps:

- **1a. `Configuration` and `Game`, with every caller moved in the same commit**:
  38 examples, 5 test projects, the template, the harness and the three
  `spec_core` specs. The new signature breaks all of them at once, so they move
  together.
- **1b. The prose.** `docs/api/game.md` documents `Configuration` member by
  member, in place of the keyword list. The 10 other snippets in `docs/api/`,
  `README.md`, `CLAUDE.md`, the skills and the example header comments stop
  naming a keyword `Game` no longer takes. `CHANGELOG.md` gets a "Changed"
  entry.

**Verify.** `rake spec` and `rake spec:core` pass. The invariant's report diff
is empty for every driven project, which proves each caller moved every
keyword. A grep for each old keyword next to `Game.new(` finds nothing outside
`CHANGELOG.md`.

**Landed.** `RGame::Game::Configuration` lives in `lib/rgame/game/configuration.rb`
as sketched, with twelve members, and `Game#initialize` takes `root:`,
`caption:` and `configuration:`. The 38 examples, 4 test projects, the template,
the harness and the three child-process specs build their game through one; the
fifth test project, `hello_world`, passes only `root` and `caption`. The
template and the harness took the sketch's shape unchanged. 1a is `f481136`
and 1b is `9b7f260`.

- **`game.md`'s section on `Configuration` landed in 1a, not 1b.**
  `spec_core/api_docs/coverage_spec.rb` fails on a public class no page names,
  so 1a would not have been green without it. 1b kept the other prose.
- **The invariant's report diff cannot be literally empty.** A `--seed` run
  under load drops a frame now and then, so 14 of the 57 reports differed in
  their frame count and in every draw count that scales with it. Their scenes,
  sounds, distinct strings and kinds of draw call all matched. `examples/pooling`
  draws its own allocation rate, which also moves with the frame count; at 600
  frames of 600 it read the same at `main` and at the head. Steps 2 and 3 should
  compare those frame-independent parts, or rerun a report that differs with
  fewer runs at once. CLAUDE.md's "two runs are byte-identical" holds only when
  every tick draws.
- **The probes read the logical size, not the window.** The probe game opens
  fullscreen, so `game.width` reads the screen. `width` and `height` are read
  through `game.viewports.width` and `height` instead. The defaults example
  still reads `game.width`.
- **Two unreleased CHANGELOG entries named keywords no release had.** `seed:`
  and `audio:` arrived after v0.4.0, so their "Added" entries now describe
  members, and the "Changed" entry lists only the ten members that were
  keywords in v0.4.0.

`make test` 412 checks, `rake spec` 4,515 examples (one more: `game.md`'s new
snippet) in 35.7 s, and `rake spec:core` 539 (the six in
`game_configuration_spec.rb`, 1.5 s of them), all passing.
`rake drive:allocations` passed for all 43 projects. Two mutations fail the new
spec as intended: `Game` ignoring `players` fails "hands every member to the
game", and a thirteenth member with no probe fails "probes every member". The
grep for an old keyword next to `Game.new(` finds only the spec that expects
`width: 800` to raise. `docs/api/game.md` documents `Configuration` under
"`Configuration` — what a game sets at startup", and `CHANGELOG.md` has the
"Changed" entry.

---

### Step 2 — premultiplied alpha

This step lands before linear filtering and alone. Under `:nearest` its only
visible effect should be none, and a readback spec can prove that without
filtering muddying the numbers.

```c
/* graphics/pixels.h — pure: bytes in, bytes out. */

/* Multiplies each pixel's colour by its own alpha, in place. `rgba` is RGBA8,
 * tightly packed, as stb decodes it. */
void rgame_pixels_premultiply(unsigned char *rgba, size_t pixel_count);

/* One byte scaled by another, rounded to the nearest byte. Scaling by 255
 * returns `value` unchanged. */
unsigned char rgame_pixels_scale(unsigned char value, unsigned char by);
```

`image.c` calls `rgame_pixels_premultiply` between the decode and
`upload_rgba`. The count is `(size_t)width * (size_t)height`.

`canvas.c` writes premultiplied colours. `write_vertex` fades the alpha by the
opacity in effect, then scales the colour by that alpha. `rgame_canvas_replay`
premultiplies and fades its tint once per replay, then scales all four baked
channels by it. The baked vertices came through `write_vertex`, so they are
premultiplied already and nothing is multiplied twice.

`gl_backend.c` takes `GL_ONE` as the source factor for both modes:

```c
glBlendFunc(GL_ONE, blend == RGAME_BLEND_ADD ? GL_ONE : GL_ONE_MINUS_SRC_ALPHA);
```

`font_atlas.c` stores its pages as `GL_INTENSITY`. Under `GL_MODULATE` a glyph's
coverage then scales the vertex colour's RGB as well as its alpha. **The source
format must change with it, to `GL_LUMINANCE`,** in the page's `glTexImage2D`
(`:125`) and in each glyph's `glTexSubImage2D` (`:386`). GL converts `GL_ALPHA`
data to RGBA as `(0, 0, 0, a)`, and an intensity texture keeps the red, so every
glyph would upload as zero and all text would vanish. The file's header comment,
"Why the pages are GL_ALPHA", is rewritten to match.

Rules the tests pin:

1. An opaque colour at full opacity reaches the vertex byte for byte as before.
2. A vertex's RGB is its colour times its alpha, after the opacity in effect has
   faded that alpha.
3. A replay's tint is premultiplied and faded once, and scales all four channels
   of each baked vertex.
4. A fully transparent pixel uploads as `0, 0, 0, 0`, whatever colour the file
   stored.
5. Every scale rounds to the nearest byte, and a scale by 255 changes nothing.
   Rule 1 rests on this.
6. Text keeps its colour.

Tests:

- `test/test_pixels.c`, new, added to the root `Makefile`'s `TEST_OBJS`,
  `test/suites.h` and `test_main.c`:
  - an opaque pixel is unchanged
  - a fully transparent pixel becomes zero
  - a half-transparent pixel halves its colour, rounded
  - an empty buffer is left alone
- `test/test_canvas.c`:
  - `the_colour_reaches_the_vertex_in_gl_byte_order` expects premultiplied bytes
  - an opaque colour at opacity 1 is written unchanged
  - an opacity fades RGB along with alpha
- `test/test_recording.c`:
  - `a_tint_multiplies_the_recorded_colours`,
    `a_replay_inside_an_opacity_is_faded_after_its_tint` and
    `an_opacity_pushed_while_baking_is_baked_in` expect premultiplied RGB
  - a translucent baked vertex replayed under a white tint is unchanged, which
    is rule 3's "nothing twice"
- Readback specs in `spec_core/rgame/core/`, each reading the value a straight
  blend gives, within 1:
  - `renderer_spec.rb`: a half-transparent red rect over the clear colour, and
    the same rect under `blended(:add)`
  - `image_spec.rb`: a half-transparent pixel from a PNG
  - `font_spec.rb`: red text reads red, which catches the `GL_LUMINANCE` trap

Sub-steps:

- **2a. `graphics/pixels.c` and its Check tests.** Pure, and used by nothing
  yet.
- **2b. The pipeline switch: `canvas.c`, `image.c`, `gl_backend.c` and
  `font_atlas.c` together,** with the Check and readback changes above. Any
  subset of the four draws wrong colours.

**Verify.** `make test` and `rake spec:core` pass, and every readback spec that
existed before passes unchanged. The invariant's report diff is empty. By eye,
`examples/effects` looks as it did, with its additive particles, translucent
fades and text. Measure what the step adds, and record both numbers in its
landed note:

- the time to load the largest PNG under `examples/`, before and after
- a loop of a million `rgame_canvas_quad` calls with a translucent colour

`docs/api/drawing.md`'s "Blending and fading" makes no claim about the blend
factors today. Search `docs/api/` once more for one, as
[write-docs](../../.claude/skills/write-docs/SKILL.md) asks.

**Landed.** `graphics/pixels.{c,h}`, and the four files switched together, as
sketched. 2a is `8c284e7` and 2b is `ae5696b`.

- **`rgame_pixels_scale` is `static inline` in `pixels.h`**, since the canvas
  calls it for every colour it writes. Its Check test compares it with exact
  rounding for all 65,536 pairs of bytes.
- **The canvas works out a primitive's colour once, not once per vertex.**
  Premultiplying in `write_vertex`, as sketched, took a million translucent
  quads from 28.5 ms to about 37. A new `vertex_colour` fades and premultiplies
  the colour once, and each vertex copies it. The replay's tint goes through it
  too. That leaves the quads faster than before the step: 24.3 ms at best
  against 27.2, and a median of 26.8 against 29.2.
- **A tinted replay rounds where it truncated.** The old `modulate` truncated
  `value * tint / 255`, and `rgame_pixels_scale` rounds, so a tint that is not
  white can move a channel by 1.
- **A fifth Check test asserted straight colour.**
  `opacity_scales_alpha_to_the_nearest_byte_and_leaves_the_colour_alone`
  checked that a fade leaves RGB alone. It is now
  `..._and_the_colour_with_it`.
- **The `GL_LUMINANCE` trap was already covered.** Uploading glyphs as
  `GL_ALPHA` into the intensity pages fails ten existing text examples in
  `renderer_spec.rb`, as well as the new one in `font_spec.rb`. The new one
  adds that a glyph's edge blends by its coverage: over blue, red and blue sum
  to 255 in every pixel.
- **The invariant's report diff cannot see this step.** A drive report records
  draw calls, and premultiplying changes none of them. A scratch script instead
  prepended `frame_end` to `RGame::Game` and saved the back buffer with
  `RenderedFrame.grab` at four ticks of each of the 57 driven runs, at `main`
  and at the head. Of 215 frames, 174 are identical, and 41 differ by exactly
  1 in at most 56 channels, 933 in all. None differs by more.
  `examples/effects` is identical at all four ticks, which answers the plan's
  "by eye". One `--gamepad` run among four at once caught a press a tick late;
  run alone, it matched. **Step 3's invariant is about pixels too, so it should
  compare frames the same way.**
- **Framebuffer alpha now stays opaque.** `renderer_spec.rb` said half white
  over black leaves 0.75 in the framebuffer's alpha on macOS. With `GL_ONE`,
  that alpha is 1. The comment is rewritten; the spec compares colour only.
- **No CHANGELOG entry.** Nothing a game sees changes by more than 1. The
  "Added" entry for `texture_filter` in step 3 is where dark fringes belong.
  `docs/api/` makes no claim about blend factors, and `faded`'s "keeps its
  colour" still holds for what a player sees.

Load cost, median of repeated `Image.new`: `examples/assets/tileset.png`
(192×176, the largest image under `examples/`) went from 0.115 ms to 0.152 ms.
A 2048×2048 PNG with every pixel translucent went from 22.1 ms to 30.3 ms.
Premultiplying alone takes 2.4 ms for 4 million pixels of art that is opaque
or fully transparent, and 6.9 ms when every pixel is translucent. A
branch-free loop was no faster there, and three times slower on opaque art.

`make test` 422 checks (10 new), `rake spec` 4,515 examples, `rake spec:core`
544 (5 new), all passing, and `rake drive:allocations` passed for all 43
projects. Four mutations fail as intended: a truncating scale fails three
pixel tests, a replay that premultiplies again fails two recording tests,
`GL_ALPHA` glyph uploads fail 11 `spec_core` examples, and `GL_SRC_ALPHA` as
the source factor fails 8.

---

### Step 3 — `texture_filter:`

Steps 1 and 2 leave one setting to add, and a sheet that has to know its filter.

```c
/* include/rgame/core.h */
typedef enum { RGAME_TEXTURE_NEAREST, RGAME_TEXTURE_LINEAR } rgame_texture_filter;

rgame_app *rgame_app_create(int width, int height, const char *title, int fullscreen,
                            rgame_texture_filter filter);

/* The filter every image this app loads is sampled with. Fixed when the app is
 * created, because the asset cache would otherwise hold images made under two. */
rgame_texture_filter rgame_app_texture_filter(const rgame_app *app);
```

```c
/* graphics/texture.h, which includes rgame/core.h for the enum */
typedef struct {
    unsigned int name;
    int width, height;
    rgame_texture_filter filter; /* how this sheet was uploaded, and so how its UVs inset */
    int refs;
} rgame_texture_sheet;

rgame_texture_sheet *rgame_texture_sheet_create(unsigned int name, int width, int height,
                                                rgame_texture_filter filter);
```

`image.c` reads the app's filter, sets `GL_LINEAR` or `GL_NEAREST` in
`upload_rgba` and hands the filter to the sheet. `rgame_texture_uv` insets under
`:linear`. `src/main.c` passes `RGAME_TEXTURE_NEAREST`.

```ruby
RGame::Core::App.new(width:, height:, caption:, media_root: nil, fullscreen: false,
                     texture_filter: :nearest)
app.texture_filter   # => :nearest

RGame::Game::Configuration.new(texture_filter: :linear)   # Game passes it to App
```

Rules the tests pin:

1. Under `:nearest`, every UV and every texture parameter is what it is today,
   bit for bit.
2. Under `:linear`, each edge of a view that lies inside its sheet moves half a
   texel inward. An edge on the sheet's border stays, since `GL_CLAMP_TO_EDGE`
   covers it, so a whole image keeps its UVs of 0 to 1.
3. A view one texel wide samples that texel's centre from both edges.
4. Every image an app loads takes the app's filter. That covers assets, sprite
   sheets, UI atlases, tilesets and image layers, because every one goes through
   `rgame_image_load`.
5. An unknown filter raises `ArgumentError` from `App.new` before the window
   opens, naming the two it accepts.
6. Font pages stay linear whatever the setting.

Tests:

- `test/test_texture.c`:
  - UVs under `:nearest` are unchanged
  - interior edges inset under `:linear`
  - border edges stay
  - a view one texel wide samples its centre
  - a whole view keeps 0 to 1
  
  The other callers of `rgame_texture_sheet_create` pass `RGAME_TEXTURE_NEAREST`.
- `spec_core/rgame/core/app_spec.rb`:
  - the filter defaults to `:nearest`
  - `texture_filter` reads back the value given
  - an unknown symbol raises
- Readback specs. `RenderedFrame.capture` grows a `texture_filter:` keyword for
  them:
  - A 2×1 black-and-white image drawn eight times wide. Under `:nearest` it
    reads only black and white; under `:linear` it reads grey between them.
  - Tile 0 of a sheet of two tiles, red and blue, drawn at 3.5× under
    `:linear`. It reads no blue.
  - A white disc with a transparent black surround, drawn at 2.5× under
    `:linear` over a white rect. Every pixel reads white. A fringe would show
    as a grey ring: straight alpha turns a half-covered edge texel into 75%
    grey there. Over the dark clear colour the fringe is still brighter than
    the background, so only a white background makes it measurable. **This is
    the plan's acceptance test:** premultiplied alpha and linear filtering,
    together.
- `game_configuration_spec.rb` gets a probe for `texture_filter`. The guard from
  step 1 fails until it exists.

Sub-steps:

- **3a. Sheets carry a filter, and `rgame_texture_uv` insets under `:linear`.**
  Pure, with Check tests.
- **3b. `App` and `Image` take the filter**: the C API, `App`'s keyword, and the
  readback specs.
- **3c. `Configuration` gains `texture_filter`, and `Game` passes it on.** Update
  `docs/api/images.md`'s "Images always use nearest-neighbour sampling",
  `app.md` and `game.md`. `CHANGELOG.md` gets an "Added" entry.

**Verify.** The disc readback passes. Under the default, the invariant's report
diff is empty. `rake spec`, `rake spec:core` and `make test` pass.

**Landed.** As sketched: the sheet's `filter`, the half-texel inset in
`rgame_texture_uv`, `rgame_app_create`'s new argument with
`rgame_app_texture_filter`, `App.new(texture_filter:)` with its reader, and the
`Configuration` member, which `Game` passes to `App`. 3a is `4db2753`, 3b
`7bdeed1` and 3c `70ffb99`.

- **`app.md` and `images.md` landed in 3b, not 3c.** As in step 1, the
  coverage spec fails on a public method no page names, here
  `App#texture_filter`. `images.md`'s "always nearest-neighbour" would also have
  been false from 3b on. 3c kept `game.md` and `CHANGELOG.md`. `ui.md` said
  icon scales default to 1 because images are nearest; it now says so of the
  default filter.
- **Rule 5's "before the window opens" has no spec.** The binding checks the
  Symbol before it calls `rgame_app_create`, so it holds by construction, but
  Ruby can see no count of open windows. The spec checks the error and its
  message.
- **Rule 6 needed no code.** Font pages were linear already.
- **The acceptance test draws the disc over black too.** Over white alone, a
  disc that never drew would pass. Over black, its centre reads white and its
  edge grey, so the test also shows the image was drawn and filtered.
- **The Configuration probe was added last, to watch step 1's guard work.**
  Without it, "probes every member" failed, naming `texture_filter`.

The readbacks: under `:nearest` the 2×1 image's row reads eight 0s and eight
255s, and under `:linear` it runs from 0 to 255 through greys. Every pixel of
the red tile at 3.5 times reads pure red. Over white, the disc's lowest channel
is at least 254. Three mutations fail them as intended: straight alpha (no
premultiply at load, and `GL_SRC_ALPHA`) draws the disc's edge at 202 over
white, a tile without the inset shows blue, and two UV mutations fail three and
two Check tests.

The invariant, compared as step 2 suggested: the back buffer at four ticks of
each of the 57 driven runs, at `main` and at the head. All 215 frames are
identical byte for byte, and every run exited 0. By eye, `examples/scroll_map`
shot fullscreen at 800×600, a letterbox scale of 1.25, draws its tile map under
`:linear` with no seam between tiles and no dark edge on the fence or the
sand. The art is pixel art, so it looks soft, as it should.
`examples/fullscreen` draws no images, so the filter changes none of its
pixels.

`make test` 428 checks (6 new), `rake spec` 4,516 examples (`images.md`'s new
snippet), `rake spec:core` 551 (7 new), all passing, and
`rake drive:allocations` passed for all 43 projects.

CI's first Windows run hung in an example this step does not touch, and a
re-run passed; see open question 4.

---

### Step 4 — `examples/smooth_art`, on the two figures

Re-planned after step 3 landed, with the art in hand. The rough version listed
six things for the example to show. The two figures show the point of this
plan, and nothing else on the list needs art drawn for it:

| Rough list | What it would show | Now |
|---|---|---|
| sprites from a shared sheet | a sprite samples none of its neighbour | Pinned by `image_spec.rb`'s red and blue tiles. The figures cannot show it: each has a transparent margin of 2 to 4 pixels at its sides and top, so a neighbour on a sheet has nothing to bleed |
| a translucent sprite | premultiplied texels, filtered and faded | In the example: one figure fades in and out |
| text | glyphs beside filtered art | In the example, as in every example. Glyph pages were linear before this plan |
| additive particles | premultiplied colour under `:add` | Dropped. `examples/effects` draws its particles as shapes, which no texture filter touches, and step 2's frames showed them unchanged |
| a tile map from an extruded tileset | tiles of one sheet, side by side on screen | Dropped from the example. `TileMapRenderer` draws each tile with `image_at`, the path every image takes. 4a pins it with a readback on generated tiles |
| a nine-slice panel | nine views of one image | Dropped. `NineSlice` draws subimages with `image_at` too, and shows nothing the tile map readback does not |

The figures cannot show the dark fringe either: their edge is a near-black
outline. `image_spec.rb`'s disc readback pins that, and stays this plan's
acceptance test.

**Art.** Two figures, drawn for rgame, are in `examples/assets/` but not
committed yet. 4b commits them with an entry in `examples/assets/README.md`
that records them as drawn for rgame.

| | `older-man@1x.png` | `woman@1x.png` |
|---|---|---|
| Size | 64×150 | 56×132 |
| Pixels at partial alpha | 386, at 59 levels | 426, at 69 levels |
| Fully transparent pixels | 3,354, each storing black | 3,257, each storing black |
| Pixels at partial alpha, average colour | 27, 27, 27 | 27, 27, 27 |

Both are anti-aliased throughout, outlines and inner lines alike. Scaled 1.5
times, from 1280×720 to 1920×1080, nearest sampling doubles some outline rows
and not others, and linear sampling keeps them even. That is the requirement's
"jaggy and uneven in thickness", on art drawn for this engine.

#### 4a. A tile map from a `:linear` sheet *(pure readback)*

A tile map puts a sheet's tiles side by side on screen, which is where a tile
sampling its neighbour would show. Nothing checks that composition today:
`image_spec.rb` draws one tile alone.

Rules the test pins:

1. Under `:linear`, a tile map drawn at a scale that is not a whole number
   shows each tile's own pixels and none of its neighbour's on the sheet.

Tests, in `spec_core/rgame/core/tile_map_renderer_spec.rb`:

- A 32×16 sheet, a red tile then a blue one, and a 2×1 map showing blue then
  red, drawn at 1.5 times under `:linear`. Every pixel reads pure red or pure
  blue. The order is reversed so that each tile's edge beside its neighbour on
  the sheet lies at the end of the map on screen, where a bleed would show as
  purple.

#### 4b. `examples/smooth_art`

One scene at 1280×720 under `:letterbox`, in which each figure is resampled a
different way:

| On screen | Resampled by |
|---|---|
| both figures, as drawn, side by side | the window alone: 1.5 times in a 1920×1080 fullscreen, and not at all in a 1280×720 window |
| the woman at 2.5 times | a scale in the scene, at any window size |
| the man, tilting to and fro | rotation |
| the woman, gliding slowly and fading in and out | movement by fractions of a pixel, and opacity |

**F** switches fullscreen, as in `examples/fullscreen`. **`RGAME_FILTER=nearest`
runs the same scene unfiltered.** The filter is fixed for the game's life
(decision 10), so comparing the two means running it twice. A status line
names the filter in use, and a help line names both switches.

```ruby
module SmoothArtExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH = 1280
  HEIGHT = 720
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__)
  TEXTURE_FILTER = ENV.fetch('RGAME_FILTER', 'linear').to_sym

  # A figure standing on its node's origin. The node's size is the image's,
  # which is what Components::Sprite's anchor measures from.
  class Figure < Engine::Node2D
    def initialize(image, width:, height:, **)
      super(width:, height:, **)
      add_component(Components::Sprite.new(id: image))
    end
  end

  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Smooth art',
      configuration: RGame::Game::Configuration.new(
        width: WIDTH,
        height: HEIGHT,
        media_root: ASSETS,
        locales: LOCALES,
        texture_filter: TEXTURE_FILTER,
        input_map: Engine::InputMap.default.merge(
          fullscreen: { buttons: [Util::Controls::KEY_F, Util::Controls::PAD_Y] }
        )
      )
    )
    game.start
  end
end
```

The tilt, the glide and the fade accumulate their own elapsed time in
`_update`, as CLAUDE.md requires of anything animated, and set the node's
`angle`, `x` and `opacity`. Nothing in the example allocates once warm.

Tests:

- `tools/drive/examples/smooth_art.rb`. It presses F, and F again before the
  run ends, since a fullscreen window left behind on Xvfb hangs the next run.
  Its header says what the report shows: both images drawn every frame, the
  status and help lines, and no missing translation.
- The default allocation budget, under `rake drive:allocations`.
- `docs/api/examples.md` gets a `### smooth_art` entry, which
  `spec/api_docs/index_spec.rb` requires, and `README.md`'s examples table a
  row.

Sub-steps:

- **4a. The tile map readback.** A spec only.
- **4b. The example**, with the two images and their `examples/assets/README.md`
  entry, `locales/en.yml`, the drive script, the `examples.md` entry, the
  `README.md` row and a CHANGELOG "Added" entry.

**Verify.** The 4a readback passes, and fails with the inset removed. The
example's driven run exits 0 and stays within the default allocation budget.
By eye, frames shot fullscreen on a 1920×1080 Xvfb screen, as steps 2 and 3
shot theirs, show under `:nearest` outlines whose thickness varies at 1.5
times, and under `:linear` outlines that stay even, with smooth edges on the
tilting figure. `make test`, `rake spec` and `rake spec:core` pass.

**Landed.** As sketched: 4a's readback in `tile_map_renderer_spec.rb`, and
`examples/smooth_art` with the two figures, their entry in
`examples/assets/README.md`, `locales/en.yml`, the drive script, the
`examples.md` entry, the `README.md` row and a CHANGELOG "Added" entry. The
re-plan is `0e89e4d`, 4a `eb9233f` and 4b `8ada662`.

- **Step 3's sweep missed six comments outside `docs/api/`.** `Image`'s class
  comment, `rgame_image`'s in `core.h`, `UI::IconButton`'s reason for its
  default scales, `examples/radial_menu`'s header and two entries in
  `examples/assets/README.md` still said images are always sampled
  nearest-neighbour. They ship, so they were fixed here, in a commit of their
  own (`486bace`). Step 5's pass over the landed notes should ask why a search
  of `docs/api/` alone was the rule.
- **Switching fullscreen under Xvfb does not resize GL's drawable.** On a
  1920x1080 Xvfb screen, after F only the bottom-left 1280x720 of the back
  buffer held an image, at the right scale, and the rest read black for as
  long as the run went on. Leaving fullscreen kept the screen's size, while
  `fullscreen?` answered false. `examples/fullscreen` takes the same path, so
  nothing here is new; see open question 6. The frames below were shot with the
  game started fullscreen, as step 3's were.
- **`Figure` takes `scale:`**, for the woman at 2.5 times, and passes it to
  `Components::Sprite`. `Tilting` and `Gliding` subclass it.
- **The status line reads `App#texture_filter`** through `root.context`,
  rather than the file's constant, so it names the filter the game runs with.
- **`images.md`'s "Filtering" points at the example**, which the sketch did not
  list.

4a passes. With the inset removed, the map's two ends read (43, 0, 212) and
(212, 0, 43), where they should read pure blue and pure red. The driven run
exits 0, and its report matches the script's header: five `image` calls a
frame all at x 0.0, `rotated` and `faded` on 239 of 240 frames, from -14.3 to
14.3 degrees and from 0.2 to 1.0, and no missing translation.
`--allocations` measures 0.6 objects a second, on 0.7% of ticks.

By eye, frames shot at 1920x1080 fullscreen show what the plan said: under
`:nearest` some outline rows double at 1.5 times and others do not, and the
tilting figure's edges break into steps. Under `:linear` the outlines keep
their weight and the edges stay smooth, with no dark fringe. Two measurements
back that up, in a 1280x720 window:

- **The glide.** Frame by frame, the gliding figure's centre moves 0, 0, 0, 1,
  0, 0, 1, 0, 0, 1 pixels under `:nearest`, and 0.29 to 0.30 pixels every
  frame under `:linear`.
- **The figures as drawn** are identical under both filters: 0 of 28,800
  pixels differ, since nothing resamples them at 1 times.

`make test` 428 checks, `rake spec` 4,516 examples, `rake spec:core` 552 (1
new), all passing, and `rake drive:allocations` passed for all 44 projects.

---

### Step 5 — fold back and delete this plan *(rough)*

- `possible-todos.md` gains three entries, each with its trigger: a filter per
  image, mipmaps, and switching the filter while the game runs.
- `possible-todos.md`'s render-target entry is updated: premultiplied alpha is in
  place, and its sentence about "the filter and the factor" now names
  `texture_filter`.
- Its blend-modes entry is updated: under premultiplied alpha, multiply is
  `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)`.
- Run the pass over every step's landed notes that
  [learn-from-mistakes](../../.claude/skills/learn-from-mistakes/SKILL.md)
  describes.

**Verify.** `CHANGELOG.md` is checked against everything the plan shipped,
following [update-changelog](../../.claude/skills/update-changelog/SKILL.md).
`docs/plans/smooth-art.md` is deleted, and no link in `docs/` points at it.
