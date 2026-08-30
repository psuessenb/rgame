# frozen_string_literal: true

# Drives a test project from a script and reports what the game actually asked
# for.
#
#   ruby tools/drive_test_project.rb test_projects/tiled_world/main.rb
#   ruby tools/drive_test_project.rb test_projects/asteroids/main.rb --ticks 200
#   ruby tools/drive_test_project.rb test_projects/asteroids/main.rb --seed 7
#
# The input script is found by mirroring the project's own path under
# `tools/drive/`, so the first line above reads
# `tools/drive/test_projects/tiled_world.rb`. `--script` overrides it, which is
# how one project has several scripts (`tiled_world_2p.rb`, `_cutscene.rb`).
#
# ## Why this exists
#
# The test projects are the acceptance test for anything that changes how the
# three layers are wired together, because they are the only tier where all
# three are present at once (CLAUDE.md, "The test projects are the acceptance
# test for wiring"). But **booting one is not enough**, and that is not a
# theoretical worry: a polling bug that consumed every input edge before a tick
# could read it left a game whose menu responded to nothing, and a plain boot of
# it reported "90 ticks, 90 frames" and looked perfectly healthy.
#
# So this harness counts rather than eyeballs. It swaps in a scripted input
# backend, bounds the tick count, and reports the draw calls issued, the clips
# and translates pushed, the sounds played and the scenes entered.
#
# ## Why it lives in the repo
#
# The harness this replaces lived outside it, which made it a caller no
# project-wide rename could reach — and it broke after every sweep, silently,
# because nothing in CI ran it. `tools/` is the documented home for development
# tools that are not built by `make` and do not ship in the gem (it is not in
# rgame.gemspec's packaged glob, and spec/packaging_spec.rb asserts that).
#
# ## How it drives a test project without modifying it
#
# A test project's `main.rb` builds a Game and calls `start` at the bottom, as a
# game would. This file prepares the ground and then `load`s it unchanged:
#
#   - `RGame::Game` gains an `input:` keyword (the one production change this
#     needed), so the scripted backend goes in where the real one would;
#   - modules are prepended to `Game` and `SceneStack` to count and to stop the
#     loop after the tick budget;
#   - the renderer and audio server are wrapped in recording proxies.
#
# Prepending is the right tool here precisely because the test project must stay
# a caller like any other. The moment this harness constructs its own Game
# instead of loading the project's, it stops testing the wiring it uses.
#
# ## What the counts do and do not promise
#
# Structure is stable: which scenes were entered, which sounds fired, how many
# clips and translates were pushed, ticks against frames. Those are what to
# assert on.
#
# Clips are aggregated by rectangle, and **a player's region is clipped twice a
# frame** once they have UI: once by the WorldView drawing the world through
# their camera, and once by their PlayerLayer drawing their own screen. Both
# push the same rectangle, so a two-player frame shows four clips over three
# rects and the counts are double what the frame count suggests. The distinct
# translates inside a rect are the two passes' offsets together.
#
# Exact draw counts are **not** stable, for two reasons.
#
# `test_projects/asteroids` seeds its rock spawns with an unseeded `Random.new`,
# so two runs differ by tens of `image` calls and may or may not reach a
# collision. That is the game's choice, not a defect here.
#
# And the fixed-timestep loop decouples ticks from frames: a slow frame runs
# several catch-up ticks, so the budget can be spent — and `close` called —
# before that frame draws. Even a seeded project can therefore come in one draw
# short of its usual count. Observed once in about a dozen runs of tiled_world.
#
# So "the number went from 843 to 944" is not by itself a regression, and
# neither is a difference of one. Compare orders of magnitude, and assert on
# structure.

require 'optparse'

# Xvfb, from the Core suite's helper rather than a second copy of it. It has to
# be started before rgame/core is loaded — it registers an at_exit that must run
# after Core's own — which is why this require and this call come first.
require_relative '../spec_core/support/headless_display'

module DriveTestProject
  ROOT = File.expand_path('..', __dir__)

  # Where a project's default input script lives: `tools/drive/` with the
  # project's own directory path under it, so
  # `test_projects/tiled_world/main.rb` reads `tools/drive/test_projects/tiled_world.rb`.
  #
  # **It mirrors the path rather than taking the basename**, which it used to.
  # A basename is unique only by luck once there is more than one tree of
  # projects: `examples/snake` and `test_projects/snake` would silently share
  # one script, and the symptom would be a game driven by inputs written for a
  # different game — a confusing report rather than an error. Mirroring makes
  # the collision impossible instead of merely unlikely.
  def self.default_script_for(project)
    directory = File.dirname(File.expand_path(project, ROOT))
    relative = directory.delete_prefix("#{ROOT}/")
    # Only a path under the repo has a mirror position under tools/drive/. One
    # from outside it would compose an absolute path onto `drive/` and produce a
    # nonsense filename, so say what is wrong instead of reporting it missing.
    abort "#{project} is outside #{ROOT}, so it has no default script — pass --script." \
      if relative == directory

    File.join(__dir__, 'drive', "#{relative}.rb")
  end

  # ---------------------------------------------------------------- the script

  # A per-tick timeline of what each device is doing, built with a small DSL:
  #
  #   idle 30                       # 30 ticks with nothing held
  #   press controls::KEY_RETURN    # one tick down, one tick up
  #   hold controls::KEY_LEFT, 20   # 20 ticks held
  #   hold [controls::KEY_LEFT, controls::KEY_SPACE], 15
  #   tilt controls::AXIS_LEFT_X, 0.5, 30
  #
  # `press` is two ticks on purpose. Edge queries (`pressed?`) compare against
  # the previous poll, so an action that never goes back up fires once and then
  # reads as held forever — which is a different thing from a press and drives
  # menus differently.
  #
  # ## One timeline per device
  #
  # Bare verbs drive the keyboard. `on` switches to another device, and each
  # device's timeline is **independent and absolute** — every track starts at
  # tick 0 — so two players written one after the other in the file act at the
  # same time, not in turn:
  #
  #   on controls::KEYBOARD do
  #     idle 20
  #     hold controls::KEY_RIGHT, 60      # ticks 20..80
  #   end
  #
  #   on controls.gamepad(0) do
  #     idle 20
  #     hold controls::PAD_DPAD_LEFT, 60  # also ticks 20..80
  #   end
  #
  # Repeating the leading `idle` is the price of being able to read one player's
  # whole timeline top to bottom, which beats tracking a shared cursor in your
  # head across two blocks.
  class Script
    NOTHING = [].freeze
    NO_AXES = {}.freeze
    Frame = Struct.new(:held, :axes)
    RESTING = Frame.new(NOTHING, NO_AXES).freeze

    # One device's timeline, indexed by absolute tick.
    class Track
      def initialize = @frames = []

      def idle(count)
        count.times { @frames << RESTING }
        self
      end

      def hold(ids, count, axes)
        frame = Frame.new(Array(ids).freeze, axes).freeze
        count.times { @frames << frame }
        self
      end

      # Past the end of a track everything rests, so a tick budget longer than
      # the script simply runs the game idle.
      def at(tick) = @frames.fetch(tick, RESTING)
      def length = @frames.length
    end

    def initialize
      @tracks = {}
      @device = nil
    end

    # Available to a script, so it can name physical ids without knowing where
    # they live: `hold controls::KEY_RIGHT, 60`.
    def controls = RGame::Util::Controls

    # Write the enclosed verbs to `device`'s timeline instead of the keyboard's.
    def on(device)
      previous = @device
      @device = device
      yield
      self
    ensure
      @device = previous
    end

    def idle(count = 1)
      track.idle(count)
      self
    end

    def hold(ids, count = 1, axes: NO_AXES)
      track.hold(ids, count, axes)
      self
    end

    def press(ids)
      hold(ids, 1)
      idle(1)
    end

    # Deflect an analog axis. Buttons and sticks are separate verbs because a
    # stick carries a magnitude and a button does not; `hold(..., axes:)` is
    # there for the case that wants both at once.
    def tilt(axis_id, value, count = 1)
      hold(NOTHING, count, axes: { axis_id => value }.freeze)
    end

    # What `device` is holding and deflecting on `tick`. A device the script
    # never mentioned rests throughout.
    def at(tick, device) = @tracks[device]&.at(tick) || RESTING

    def length = @tracks.values.map(&:length).max || 0

    def devices = @tracks.keys

    # Read only after rgame is loaded — a script names Controls ids, so the
    # constants have to exist before it is evaluated.
    def self.load(path)
      script = new
      script.instance_eval(File.read(path), path)
      script
    end

    private

    # The default is the keyboard, resolved here rather than at construction
    # because this file is loaded before rgame is.
    def track = @tracks[@device || controls::KEYBOARD] ||= Track.new
  end

  # The input backend, standing in for RGame::Core::Input.
  #
  # It answers the two questions ActionMapper asks — `down?(id, device:)` and
  # `axis(axis_id, device:)` — where an id is a physical one from
  # RGame::Util::Controls, exactly as the real backend takes.
  #
  # Each device reads its own timeline, so two players polled in the same tick
  # get two different answers — which is the whole point of the backend rather
  # than the hardware being faked for a two-player run.
  class ScriptedInput
    attr_accessor :tick

    def initialize(script)
      @script = script
      @tick = 0
    end

    def down?(id, device: nil) = @script.at(@tick, device).held.include?(id)

    def axis(axis_id, device: nil) = @script.at(@tick, device).axes.fetch(axis_id, 0.0)

    # The gamepad slots this script drives.
    #
    # Standing in for the input backend fakes what a device *says*, not that it
    # is there — and a player joins by using a controller the engine knows
    # exists. So the harness announces these the way SDL's hot-plug would;
    # otherwise a scripted pad presses buttons into a slot nothing is watching.
    def gamepad_slots
      first = RGame::Util::Controls::GAMEPAD_FIRST
      @script.devices.select { |device| device >= first }.map { |device| device - first }
    end
  end

  # ---------------------------------------------------------------- the report

  # Everything the run observed. Counts, plus the first and last argument tuple
  # for each kind of call — which is what turns "the tilemap was drawn 90 times"
  # into "and the camera moved from (0, 0) to (240, 180) while it happened".
  class Report
    Call = Struct.new(:calls, :first_args, :last_args)

    attr_accessor :ticks, :frames
    attr_reader :draws, :clips, :translates, :sounds, :scenes, :bands

    def initialize
      @ticks = 0
      @frames = 0
      @draws = {}
      @clips = Hash.new(0)
      @translates = Hash.new(0)
      @sounds = Hash.new(0)
      @scenes = []
      # Layers opened per band. Draw order is band first, then tree order, so
      # this is the coarse half of "what covered what" — and the half a boot
      # cannot show. A game whose HUD never opens a :hud layer draws its score
      # under the world and looks perfectly healthy from every other count here.
      @bands = Hash.new(0)
      # Which translates happened inside which clip. Split-screen's signature is
      # one clip per viewport each containing its *own* camera track, and that is
      # two facts about the same nesting — reading it off two separate lists left
      # the reader to correlate them.
      @per_clip = {}
      @clip = nil
    end

    def record_draw(name, args)
      summary = args.map { |a| summarize(a) }
      call = (@draws[name] ||= Call.new(0, summary, summary))
      call.calls += 1
      call.last_args = summary
    end

    # Entered rather than merely counted, so what happens inside is attributable.
    def within_clip(rect)
      key = rect.map { |n| round(n) }
      @clips[key] += 1
      outer = @clip
      @clip = key
      @per_clip[key] ||= Hash.new(0)
      yield
    ensure
      @clip = outer
    end

    def record_translate(dxdy)
      key = dxdy.map { |n| round(n) }
      @translates[key] += 1
      @per_clip[@clip][key] += 1 if @clip
    end

    def record_band(band) = @bands[band] += 1
    def record_sound(kind, id) = @sounds["#{kind} #{id}"] += 1
    def record_scene(action, scene) = @scenes << "#{action} #{scene.class}"

    def to_s
      out = +"\n"
      out << section('ticks / frames', ["#{@ticks} ticks, #{@frames} frames"])
      out << section('scenes', @scenes)
      out << section('draw calls', @draws.sort_by { |_, c| -c.calls }.map { |name, c| draw_line(name, c) })
      out << section('layers per band', band_lines)
      out << section('clips pushed', clip_lines)
      out << section('translates pushed', translate_lines)
      out << section('audio', @sounds.map { |what, n| "#{n} × #{what}" })
      out
    end

    private

    # One line per band, back to front, so the reader sees the frame's coarse
    # stacking at a glance: how many nodes drew in the world, how many in a
    # player's HUD, whether an overlay opened at all.
    def band_lines
      RGame::Util::Z::BANDS.filter_map do |band|
        count = @bands[band]
        "#{count} × #{band}" unless count.zero?
      end
    end

    # One line per clip, with what moved inside it. Two clips each holding their
    # own set of translates is what two players looking at one world produces —
    # and one clip holding both cameras' worth would be the bug.
    def clip_lines
      @clips.map do |rect, count|
        inside = @per_clip.fetch(rect, {})
        line = "#{count} × #{rect.inspect}"
        line << " — #{inside.size} distinct translate(s) inside" unless inside.empty?
        line
      end
    end

    # Translates are the busiest list and the least interesting one by volume —
    # every rotated sprite pushes one. Show the extremes, which is where a
    # camera lives.
    def translate_lines
      return [] if @translates.empty?

      keys = @translates.keys
      xs = keys.map(&:first)
      ys = keys.map(&:last)
      ["#{keys.size} distinct, x #{xs.min}..#{xs.max}, y #{ys.min}..#{ys.max}"]
    end

    def draw_line(name, call)
      return format('%6d  %s', call.calls, name) if call.first_args.empty?

      line = format('%6d  %-18s first(%s)', call.calls, name, call.first_args.join(', '))
      line << " last(#{call.last_args.join(', ')})" if call.last_args != call.first_args
      line
    end

    def section(title, lines)
      body = lines.empty? ? ['(none)'] : lines
      "#{title}\n#{body.map { |l| "  #{l}" }.join("\n")}\n\n"
    end

    def summarize(value)
      case value
      when Float then round(value).to_s
      when Integer, Symbol, true, false, nil then value.inspect
      when String then (value.length > 24 ? "#{value[0, 21]}..." : value).inspect
      when Hash then value.map { |k, v| "#{k}: #{summarize(v)}" }.join(' ')
      else value.class.name.split('::').last
      end
    end

    def round(number) = number.is_a?(Float) ? number.round(1) : number
  end

  # ------------------------------------------------------------- the recorders

  # A recording stand-in for something the game is handed and calls by name.
  #
  # It forwards everything and records what went past. Deliberately a
  # method_missing delegator rather than an enumerated list: the point of this
  # harness is to survive the renderer growing methods, and a hand-listed proxy
  # is the thing that silently stops covering the method somebody added last
  # week. Subclasses say what is worth recording; the forwarding is shared.
  class Probe
    def initialize(target, report)
      @target = target
      @report = report
    end

    def method_missing(name, *args, **, &)
      return super unless @target.respond_to?(name)

      note(name, args)
      @target.public_send(name, *args, **, &)
    end

    def respond_to_missing?(name, include_private = false)
      @target.respond_to?(name, include_private) || super
    end

    private

    def note(name, args); end
  end

  # The renderer. Everything that reaches it is counted except the handful of
  # calls that put nothing on screen — a deny-list, so a renderer that grows a
  # new primitive is counted without this file being edited.
  class RendererProbe < Probe
    NOT_DRAWING = %i[text_width text_height font font= assets app].freeze

    # The two block-taking methods are named rather than left to the generic
    # path, because the harness has to record the *rect* and the *offset*, not
    # merely that a call happened. They are also the whole point of the harness
    # for split-screen: one clip per viewport, one distinct translate per camera.
    def clipped(x, y, width, height, &)
      @report.within_clip([x, y, width, height]) { @target.clipped(x, y, width, height, &) }
    end

    def translated(dx, dy, &)
      @report.record_translate([dx, dy])
      @target.translated(dx, dy, &)
    end

    # Named for the same reason as the two above: the *band* is what matters,
    # and the generic path would only say a layer was opened.
    def layered(band = RGame::Util::Z::DEFAULT, &)
      @report.record_band(band)
      @target.layered(band, &)
    end

    private

    def note(name, args)
      return if NOT_DRAWING.include?(name) || name.to_s.start_with?('register_')

      @report.record_draw(name, args)
    end
  end

  # The audio server. `AudioDirector` and `AudioBus` call it by name, so a
  # delegator is all it takes. Only playback is recorded — the asset manager
  # also decodes through this object (`sample`, `song`), and a file being loaded
  # is not a sound being heard.
  class AudioProbe < Probe
    def play_sound(id, **)
      @report.record_sound('sound', id)
      @target.play_sound(id, **)
    end

    def play_music(id, **)
      @report.record_sound('music', id)
      @target.play_music(id, **)
    end
  end

  # Drives a *synthetic controller* instead of the input backend.
  #
  # The scripted backend above replaces RGame::Core::Input, which is the right
  # seam for asking "does the game react to this action". It cannot answer "does
  # a controller reach the game at all", because it stands where the controller's
  # answer would have arrived.
  #
  # So this mode fakes the hardware instead: SDL fabricates a real game
  # controller in-process (the same VirtualGamepad the Core suite uses), and the
  # whole path runs unmodified — SDL event pump, the C per-frame snapshot,
  # RGame::Core::Input, InputMap, ActionMapper. Nothing is stubbed.
  #
  # Script ids are Controls ids. Pad buttons live at RGAME_BUTTON_GAMEPAD_FIRST
  # plus SDL's own button number, so converting one back is a subtraction; axis
  # ids are already SDL's numbering. Keyboard ids in a gamepad script simply do
  # nothing, which is the same thing that happens to them in a real game.
  class ScriptedGamepad
    FULL_DEFLECTION = 32_767

    # A method rather than a constant: this file is loaded before rgame is, so
    # nothing at class-definition time may name RGame.
    # Equal to RGAME_BUTTON_GAMEPAD_FIRST: pad ids are that base plus SDL's own
    # button number.
    def pad_base = RGame::Util::Controls::PAD_A

    # `slot` is the player slot SDL will seat the pad in, and therefore which of
    # the script's timelines it plays: a pad script says
    # `on controls.gamepad(0) { ... }`, like any other device.
    def initialize(script, slot: 0)
      @script = script
      @slot = slot
      @pad = nil
      @down = []
    end

    # SDL needs a frame to notice the new device and seat it in a slot, so the
    # pad is attached on the first tick rather than at construction — the same
    # shape spec_core's gamepad specs use.
    def tick(number)
      @pad ||= VirtualGamepad.new
      frame = @script.at(number, RGame::Util::Controls.gamepad(@slot))
      apply_buttons(frame.held)
      apply_axes(frame.axes)
    end

    def detach = @pad&.detach

    private

    def apply_buttons(held)
      base = pad_base
      wanted = held.filter_map { |id| id - base if id >= base }
      (@down - wanted).each { |button| @pad.release(button) }
      (wanted - @down).each { |button| @pad.press(button) }
      @down = wanted
    end

    def apply_axes(axes)
      RGame::Util::Controls.constants.grep(/\AAXIS_/).each do |name|
        id = RGame::Util::Controls.const_get(name)
        @pad.move_axis(id, (axes.fetch(id, 0.0) * FULL_DEFLECTION).round)
      end
    end
  end

  # ------------------------------------------------------------- the harness

  class << self
    def run(project:, script_path:, ticks:, gamepad: false, out: $stdout)
      HeadlessDisplay.start
      # The project's own main.rb does this too, but the probes have to be
      # installed before it is loaded, and installing them means the classes
      # must already exist.
      $LOAD_PATH.unshift(File.join(ROOT, 'lib')) unless $LOAD_PATH.include?(File.join(ROOT, 'lib'))
      require 'rgame/game'

      script = Script.load(script_path)
      report = Report.new
      if gamepad
        require_relative '../spec_core/support/virtual_gamepad'
        install(report, nil, ticks, pad: ScriptedGamepad.new(script))
      else
        install(report, ScriptedInput.new(script), ticks)
      end
      load File.expand_path(project, ROOT)

      out.puts report
      report
    end

    private

    # Prepend the counting behaviour onto the classes the project will build.
    # Done before the project is loaded, so the project itself is untouched.
    def install(report, input, budget, pad: nil)
      RGame::Game.prepend(game_probe(report, input, budget, pad))
      RGame::Engine::Scene::SceneStack.prepend(scene_probe(report))
    end

    def game_probe(report, input, budget, pad)
      Module.new do
        define_method(:initialize) do |**kwargs|
          # In gamepad mode the real backend stays in place and the game is
          # pointed at slot 0 — the whole point is that nothing is stubbed.
          extra = pad ? { device: RGame::Util::Controls.gamepad(0) } : { input: input }
          super(**kwargs, **extra)
          @renderer = RendererProbe.new(@renderer, report)
        end

        # Wrapped lazily: App#audio opens a device on first use, and wrapping it
        # in initialize would open one for a game that never plays a sound.
        # Not @audio: that is App's own ivar holding the real device, and
        # memoizing the wrapper there would overwrite what we are wrapping.
        define_method(:audio) do
          # rubocop:disable Naming/MemoizedInstanceVariableName -- see above
          @audio_probe ||= AudioProbe.new(super(), report)
          # rubocop:enable Naming/MemoizedInstanceVariableName
        end

        define_method(:update) do |dt|
          if pad
            pad.tick(report.ticks)
          else
            # Announce the script's controllers once, as SDL would a frame in.
            input.gamepad_slots.each { |slot| gamepad_connected(slot) } if report.ticks.zero?
            input.tick = report.ticks
          end
          report.ticks += 1
          super(dt)
          next unless report.ticks >= budget

          pad&.detach
          close
        end

        define_method(:draw) do
          report.frames += 1
          super()
        end
      end
    end

    def scene_probe(report)
      Module.new do
        define_method(:push) do |scene|
          report.record_scene('push', scene)
          super(scene)
        end

        define_method(:pop) do
          report.record_scene('pop', current) if current
          super()
        end
      end
    end
  end
end

# ------------------------------------------------------------------------ CLI

if $PROGRAM_NAME == __FILE__
  options = { ticks: 240, script: nil, gamepad: false, seed: nil }
  parser = OptionParser.new do |o|
    o.banner = 'Usage: ruby tools/drive_test_project.rb PROJECT_MAIN [options]'
    o.on('--ticks N', Integer, 'Stop after N simulation ticks (default 240)') { options[:ticks] = it }
    o.on('--script PATH', 'Input script (default: tools/drive/<project path>.rb)') { options[:script] = it }
    o.on('--gamepad', 'Drive a synthetic SDL controller instead of the input backend') { options[:gamepad] = true }
    o.on('--seed N', Integer, 'Seed the project RNG, so two runs can be compared') { options[:seed] = it }
  end
  parser.parse!

  # Passed to the project through the environment rather than through ARGV,
  # because the project is `load`ed into this process and never sees a command
  # line of its own. A project that has nothing random ignores it.
  ENV['RGAME_SEED'] = options[:seed].to_s if options[:seed]

  project = ARGV.shift or abort(parser.to_s)

  script_path = options[:script] || DriveTestProject.default_script_for(project)
  unless File.exist?(script_path)
    abort "No script at #{script_path}. Write one (see tools/drive/**/*.rb) or pass --script."
  end

  DriveTestProject.run(project: project, script_path: script_path,
                       ticks: options[:ticks], gamepad: options.fetch(:gamepad, false))
end
