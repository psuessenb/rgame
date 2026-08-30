# Project structure

Where everything in the repository lives, and why it lives there. This is the
map for working *on* rgame; for using it from Ruby, see
[the API guide](api/README.md).

The engine C lives under `ext/rgame_core/` — a Ruby C extension directory —
rather than a top-level `src/`. That's deliberate: `gem install` unpacks the gem
and runs each `extconf.rb`, which can only build sources inside its own
directory, so keeping the C there means one copy of the code serves both the
standalone binary and the gem.

```
ext/rgame_core/              RGame::Core — the SDL/GL half. The sources are
                             grouped by subsystem, one folder each, and a file
                             names the folder it includes from: graphics/canvas.c
                             says #include "graphics/clip.h".
  include/rgame/core.h       Public C API (opaque handle, no SDL/GL types
                             leaked) — what both src/main.c and the extension
                             bind against.
  app/                       The window, the context and the loop.
    app.c                    Engine implementation: SDL window + OpenGL context
                             setup; owns the main loop and calls back to the
                             caller's update/draw callbacks.
    app_gl.h                 Private: the GL context behind the opaque handle.
    frame_loop.h/.c          Pure fixed-timestep + FPS logic, no SDL/GL — unit-
                             tested without a window (see CLAUDE.md's layering).
  graphics/                  Everything on the drawing path.
    transform.h/.c           Pure 2D affine transform stack — rotate, scale,
                             translate, composed. No SDL.
    clip.h/.c                Pure rects and the intersecting clip stack, in
                             screen space. No SDL.
    draw_queue.h/.c          Pure z-sort and batching: collects draw commands,
                             orders them by z, merges what can share a GL call.
    canvas.h/.c              Pure composition of transform + clip + layer +
                             queue; the seam the drawing API is written
                             against. The layer stack is what makes a z an
                             offset inside one node's slot rather than a
                             global number.
    backend.h/.c             The layer-2 seam: a function-pointer table a real
                             GL backend or a recording fake plugs into, plus
                             the loop that drives it from a prepared frame.
    texture.h/.c             Pure: refcounted texture sheets, the sub-rects
                             sprites cut out of them, and pixels -> UVs.
    primitives.h/.c          Pure: rects, thick lines, circles and sprites, in
                             terms of the canvas's triangles and quads.
    recording.h/.c           Pure: a baked block of drawing, kept between
                             frames and replayed as one call per texture.
    gl_backend.h/.c          The real GL calls — the only file that issues
                             them on the drawing path.
    image.c                  Decode a PNG and upload it — the thin GL shim
                             over texture.h. Views share one upload.
    image_internal.h         What the draw path needs from inside an image.
  text/                      Glyphs, from a .ttf to a texture page.
    atlas.h/.c               Pure: shelf packing for the glyph atlas — where
                             the next glyph goes on a texture page.
    glyph_cache.h/.c         Pure: codepoint -> rasterised glyph, open
                             addressed, never evicted.
    font.h/.c                Pure: a typeface at one size — glyph metrics,
                             kerning, rasterisation and UTF-8, over
                             stb_truetype. No atlas, no GL.
    font_atlas.c             Composes font + atlas + glyph cache and owns the
                             GL pages — the only text file that calls gl*.
    font_internal.h          What the draw path needs from inside a font.
  input/                     Keyboard and controllers.
    input.h/.c               Pure input snapshot + the flat button-id space
                             (keyboard and gamepad ranges). No SDL.
    device_slots.h/.c        Pure player-slot table for controllers: keeps a
                             player on the same slot across a disconnect. No SDL.
    gamepad.h/.c             Thin SDL_GameController shim: opens/closes pads on
                             hot-plug and copies their state into the snapshot.
  audio/                     Sound, which touches neither SDL nor GL.
    audio.c                  The sound device, samples and songs — miniaudio
                             talks to the platform directly.
    audio_internal.h         The live-sound counter, for tests.
    vorbis_decoder.h/.c      Ogg Vorbis for miniaudio, over stb_vorbis —
                             miniaudio cannot read ogg on its own.
  ruby/                      The Ruby-facing glue, and the only C here that
                             includes ruby.h.
    core_ext.c               VALUE wrappers + callback trampolines, and the
                             extension's entry point.
    core_ext.h               One init function per Ruby-visible class here.
    image_ext.c              RGame::Core::Image — the Ruby binding.
    audio_ext.c              RGame::Core::Audio, Sample and Song — the
                             bindings; three classes in one file because they
                             share a wrapping shape.
    renderer_ext.c           RGame::Core::Renderer — the drawing primitives.
    font_ext.c               RGame::Core::Font — the Ruby binding.
    recording_ext.c          RGame::Core::Recording — baked, replayable draws.
  vendor/                    Third-party sources + their licences.
    <name>_impl.c            One per vendored library (stb_image, stb_truetype,
                             stb_vorbis, miniaudio): instantiates it and picks
                             its features. The only files built without
                             -Wall -Wextra; the suffix is what selects that.
  extconf.rb                 mkmf script; pkg_config("sdl2"), -lGL. It lists
                             the subsystem folders, because mkmf's own default
                             only finds sources one level up from here.
  example.rb                 Manual smoke test driven from Ruby.

ext/rgame_util/              RGame::Util — the graphics-free half, so pure-data
                             helpers can be required without pulling in SDL/GL.
  util_ext.c                 Entry point; hands RGame::Util to each class init.
  util_ext.h                 One init function per Ruby-visible class here.
  tensor.c                   RGame::Util::Tensor — flat-array 3D grid.
  color.c/.h                 Pure RGBA packing, no Ruby — Check-tested.
  color_ext.c                RGame::Util::Color — the Ruby binding over it.
  extconf.rb                 mkmf script; no pkg_config, no -lGL.

lib/rgame.rb                 `require "rgame"` — RGame::Util + RGame::Engine,
                             i.e. everything that runs without a window. It
                             must never reach RGame::Core, directly or
                             transitively.
lib/rgame/version.rb         RGame::VERSION, and nothing else — the gemspec
                             loads this file before anything is compiled.
lib/rgame/game.rb            RGame::Game — the entry point a game is written
                             against, and the only class allowed to name both
                             Core and Engine.
lib/rgame/boot.rb            Enables YJIT where this Ruby has it. Required by
                             RGame::Game, so it is the entry point's decision
                             rather than a line every game repeats.

lib/rgame/util.rb            Namespace loader.
lib/rgame/util/tensor.rb     Requires the compiled rgame/util_ext.
lib/rgame/util/color.rb      Requires the compiled rgame/util_ext for Color.
lib/rgame/util/controls.rb   Input id vocabulary (keys, pad buttons, axes,
                             device slots). Pure Ruby values, so a game may
                             name them without Core.
lib/rgame/util/z.rb          Draw bands (:world, :hud, :overlay, :debug) and
                             the rules for ordering within them.

lib/rgame/core.rb            `require "rgame/core"` — opt-in, loads SDL/GL.
lib/rgame/core/app.rb        Requires the compiled rgame/core_ext.
lib/rgame/core/input.rb      The raw input query, over the C snapshot.
lib/rgame/core/gamepad.rb    Which controllers are plugged in, and their names.
lib/rgame/core/image.rb      Sprite-sheet slicing over the C-backed Image.
lib/rgame/core/renderer.rb   Keyword args, colours and transform blocks over
                             the C-backed Renderer.
lib/rgame/core/recording.rb  #draw over the C-backed Recording.
lib/rgame/core/font.rb       The default font path, over the C-backed Font.
lib/rgame/core/*.rb          The rest are whole classes in Ruby that hold GPU
                             handles rather than wrap C: asset_manager,
                             sprite_sheet, nine_slice, ui_atlas,
                             tile_map_renderer.

lib/rgame/engine.rb          `require "rgame/engine"` — the scene graph, pure
                             Ruby, and the layer a game is written in. It may
                             not name RGame::Core at all.
lib/rgame/engine/node2d.rb   The node: transform, children, components, the
                             control -> update -> draw phases.
lib/rgame/engine/components/ Reusable behaviour attached to a node — sprites,
                             bodies, colliders, controllers, timers.
lib/rgame/engine/input/      InputMap, ActionMapper and the Actions snapshot:
                             physical ids in, named actions out.
lib/rgame/engine/ui/         Menu and MenuItem — focus-navigated UI.
lib/rgame/engine/scene/      SceneStack.
lib/rgame/engine/*.rb        The rest of the layer: players and viewports,
                             tile maps, collision, pathfinding, camera,
                             signals, pooling, i18n, the audio bus.

lib/rgame/fonts/             The default font shipped with the engine:
                             Liberation Sans 2.1.5 (SIL OFL 1.1). Data read at
                             runtime, so it lives here rather than in ext/.
lib/rgame/*.so               Build artifacts, copied here by `make ext`.

src/main.c                   Standalone executable entry point — the C
                             equivalent of example.rb. Only talks to
                             rgame/core.h, never touches SDL/GL directly. Kept
                             outside ext/ so mkmf doesn't compile its main()
                             into the extension.

test/                        Check unit tests for the pure C logic (`make test`).
  test_main.c                Runs every suite; one binary, build/test_rgame.
  suites.h                   Each test_<x>.c exposes a Suite, declared here.
  support/                   Test-only helpers, e.g. the recording draw backend
                             that stands in for OpenGL.
spec/                        Headless RSpec specs: RGame::Util and
                             RGame::Engine (`rake spec`). Never loads SDL.
  support/                   The stand-ins headless specs draw and play
                             through, and the shared example groups that hold
                             them to the same contract as the real thing.
  packaging_spec.rb          What the gem ships, asserted against the tree so a
                             new source or data file cannot be left out of it.
spec_core/                   RSpec specs for RGame::Core (`rake spec:core`).
                             Opens real windows; boots its own Xvfb.

examples/                    One runnable file per concept — "how do I do X".
                             Ships in the gem, so an installed copy can be run.
  assets/                    The art they draw, CC0 or drawn here, with its
                             provenance in README.md. Nothing from media/: it
                             cannot be redistributed and this directory ships.
test_projects/               Complete games built on the public API. They are
                             the acceptance test for how the layers are wired,
                             because they are the only tier where all three are
                             present at once. Unlike examples/ these read from
                             media/, so they do not ship.
tools/                       Development tools, outside the engine and not
                             built by make.
  drive_test_project.rb      Boots a test project unmodified, feeds it a
                             scripted input backend and reports what it actually
                             asked for — draws, clips, sounds, scenes.
  drive/                     One input script per project run, at a path
                             mirroring the project's own.
  make_ogg_fixture.c         Generates the audio suite's .ogg fixture.
rubocop/cop/game/            The project's own cops, loaded by .rubocop.yml:
                             the per-frame allocation guards and the two that
                             police the Core/Engine layer boundary.

docs/                        Documentation.
  api/                       Reference documentation for using rgame from Ruby.
                             The one part of docs/ the gem ships.
  project_structure.md       This file.
  c_engine_feature_specs.md  The feature spec the C engine was built out to.
  plans/                     Working documents for an implementation effort,
                             deleted when the work lands.

rgame.gemspec                Packages both halves as one gem: both extconf.rb
                             files, and a globbed file list so a new source or
                             asset ships without being listed anywhere.
```

Three test suites cover it, one per tier: `make test` for the C (Check),
`rake spec` for the headless Ruby half, `rake spec:core` for the parts that open
a window. None needs a display of its own — `spec:core` boots Xvfb itself.
`rake` runs all three. See the README for how to run them.
