# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'objspace'
require 'optparse'
require 'tmpdir'

require_relative '../spec_core/support/headless_display'

module DriveTestProject
  ROOT = File.expand_path('..', __dir__)

  # Where a project's default input script lives: `tools/drive/` with the
  # project's own directory path under it, so
  # `examples/collision_tiles/main.rb` reads `tools/drive/examples/collision_tiles.rb`.
  #
  # **It mirrors the path rather than taking the basename**, which it used to.
  # A basename is unique only by luck once there is more than one tree of
  # projects: `examples/maze` and `test_projects/maze` would silently share
  # one script, and the symptom would be a game driven by inputs written for a
  # different game — a confusing report rather than an error. Mirroring makes
  # the collision impossible instead of merely unlikely.
  def self.default_script_for(project)
    directory = File.dirname(File.expand_path(project, ROOT))
    relative = directory.delete_prefix("#{ROOT}/")
    abort "#{project} is outside #{ROOT}, so it has no default script — pass --script." \
      if relative == directory

    File.join(__dir__, 'drive', "#{relative}.rb")
  end

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
      @budget = {}
    end

    # What a run of this script may allocate once it is warm, for
    # `--allocations`: the objects a second, and the share of its ticks that
    # allocate anything. Each left out keeps AllocationProbe's default. A
    # script that raises one says why in its header.
    #
    #   allocation_budget objects_per_second: 1_500
    def allocation_budget(objects_per_second: nil, share_of_ticks: nil)
      @budget = { objects_per_second:, share_of_ticks: }.compact
      self
    end

    # The limits `allocation_budget` set, as keywords for AllocationProbe.new.
    attr_reader :budget

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

  # Everything the run observed. Counts, plus the first and last argument tuple
  # for each kind of call — which is what turns "the tilemap was drawn 90 times"
  # into "and the camera moved from (0, 0) to (240, 180) while it happened".
  #
  # First and last cannot see a value that leaves and comes back — a hop starts and
  # ends on the ground — so each numeric argument's range is kept too, and printed
  # as `spans` for the positions where it varied.
  class Report
    Call = Struct.new(:calls, :first_args, :last_args, :ranges)

    attr_accessor :ticks, :frames, :loaded_from, :saves, :allocations
    attr_reader :draws, :clips, :translates, :sounds, :scenes, :bands, :texts, :missing_keys

    # `texts:` adds a section listing every distinct String drawn with `text`,
    # which the draw-call section cannot show: it keeps only the first and last
    # arguments of each method.
    #
    # A run that pushed more than one clip also lists them per clip, keyed by
    # the innermost clip each was drawn in. Each viewport and each PlayerLayer
    # clips to its player's region, so that is what ties a string to a player.
    # A run with one clip would list the same strings twice, so it lists them
    # once.
    def initialize(texts: false)
      @show_texts = texts
      @texts = {}
      @clip_texts = {}
      @missing_keys = {}
      @ticks = 0
      @frames = 0
      @draws = {}
      @clips = Hash.new(0)
      @translates = Hash.new(0)
      @sounds = Hash.new(0)
      @scenes = []
      @bands = Hash.new(0)
      @per_clip = {}
      @clip = nil
    end

    def record_draw(name, args)
      summary = args.map { |a| summarize(a) }
      call = (@draws[name] ||= Call.new(0, summary, summary, {}))
      call.calls += 1
      call.last_args = summary
      widen_ranges(call.ranges, args)
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

    # Keyed by the String's contents, so a label rebuilt into an equal String
    # counts as the same text. Kept in first-drawn order, with the tick it first
    # appeared on, so a report shows what changed and when.
    def record_text(string)
      count_text(@texts, string)
      count_text(@clip_texts[@clip] ||= {}, string) if @clip
    end

    # A key `I18n` could not answer: missing from every table in the chain, or
    # translated with other variables than its Text declares. Kept like texts,
    # with the tick it first appeared on. Returns nil, so the policy that calls
    # this can answer with the key.
    def record_missing(key)
      seen = (@missing_keys[key] ||= [0, @ticks])
      seen[0] += 1
      nil
    end

    def record_band(band) = @bands[band] += 1
    def record_sound(kind, id) = @sounds["#{kind} #{id}"] += 1
    def record_scene(action, scene) = @scenes << "#{action} #{scene.class}"

    def to_s
      out = +"\n"
      out << section('rgame loaded from', Array(@loaded_from))
      out << section('saves', [@saves])
      out << section('ticks / frames', ["#{@ticks} ticks, #{@frames} frames"])
      return allocation_report(out) if @allocations

      out << section('scenes', @scenes)
      out << section('draw calls', @draws.sort_by { |_, c| -c.calls }.map { |name, c| draw_line(name, c) })
      out << section('texts drawn', text_lines(@texts)) if @show_texts
      out << section('texts drawn per clip', clip_text_lines) if @show_texts && @clip_texts.size > 1
      out << section('missing or mismatched keys', missing_lines) unless @missing_keys.empty?
      out << section('layers per band', band_lines)
      out << section('clips pushed', clip_lines)
      out << section('translates pushed', translate_lines)
      out << section('audio', @sounds.map { |what, n| "#{n} × #{what}" })
      out
    end

    private

    def allocation_report(out)
      out << section('missing or mismatched keys', missing_lines) unless @missing_keys.empty?
      out << section("allocations after a #{AllocationProbe::WARMUP}-tick warm-up", @allocations.lines)
    end

    def count_text(texts, string)
      seen = (texts[string] ||= [0, @ticks])
      seen[0] += 1
    end

    def text_lines(texts)
      texts.map { |string, (count, tick)| format('%6d  %s from tick %d', count, string.inspect, tick) }
    end

    def clip_text_lines
      @clip_texts.flat_map { |rect, texts| [rect.inspect, *text_lines(texts).map { "  #{it}" }] }
    end

    def missing_lines
      @missing_keys.map { |key, (count, tick)| format('%6d  %s from tick %d', count, key, tick) }
    end

    def band_lines
      RGame::Util::Z::BANDS.filter_map do |band|
        count = @bands[band]
        "#{count} × #{band}" unless count.zero?
      end
    end

    def clip_lines
      @clips.map do |rect, count|
        inside = @per_clip.fetch(rect, {})
        line = "#{count} × #{rect.inspect}"
        line << " — #{inside.size} distinct translate(s) inside" unless inside.empty?
        line
      end
    end

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
      spans = call.ranges.filter_map { |index, (min, max)| "#{index}: #{round(min)}..#{round(max)}" if min != max }
      line << " spans(#{spans.join(', ')})" unless spans.empty?
      line
    end

    def widen_ranges(ranges, args)
      args.each_with_index do |arg, index|
        next unless arg.is_a?(Numeric)

        min, max = ranges[index]
        ranges[index] = min ? [[min, arg].min, [max, arg].max] : [arg, arg]
      end
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

    # Named so `--texts` lists what a player saw. A label revealing a line
    # draws the whole line with `bytes:`, and what reached the screen is its
    # start, cut at the last whole character as the renderer cuts it.
    def text(string, *, bytes: nil, **, &)
      drawn = @target.text(string, *, bytes: bytes, **, &)
      label = label?(string) ? string.to_str : string
      note(:text, [bytes ? label.byteslice(0, bytes).scrub('') : label, *])
      drawn
    end

    private

    def note(name, args)
      return if NOT_DRAWING.include?(name) || name.to_s.start_with?('register_')

      args = [args.first.to_str, *args.drop(1)] if name == :text && label?(args.first)
      @report.record_text(args.first) if name == :text && args.first.is_a?(String)
      @report.record_draw(name, args)
    end

    def label?(value)
      !value.is_a?(String) && value.respond_to?(:to_str)
    end
  end

  # The audio server, passed to the game as `audio:`. `Engine::AudioOut` calls
  # it by name, so a delegator is all it takes. Only playback is recorded — the asset manager
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

    # Recorded with no id because it takes none: `stop_music` stops whatever
    # *this registry* started, deliberately rather than "whatever is playing".
    # It is reported for the same reason the other two are — a scene that stops
    # its music on the way out is a structural fact, and its absence from a run
    # that should have had one is the kind of thing this harness exists to show.
    def stop_music
      @report.record_sound('music', 'stop')
      @target.stop_music
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

  # What a run allocates once it is warm, for `--allocations`.
  #
  # The first WARMUP ticks load assets, build scenes and fill Ruby's method
  # caches, none of which a player waits on twice, so counting starts after
  # them. From then on the collector is paused: every object the game makes is
  # still there at the end to be traced to the line that made it, and no
  # collection adds objects of its own mid-count.
  #
  # **Two numbers, because they catch different mistakes.** Objects a second
  # is what the collector has to keep up with, and a burst of work on an event
  # is what raises it: a page of dialogue, a path planned. The share of ticks
  # that allocate anything is what an allocation every frame raises. One
  # object a frame is only 60 a second, but it is on every tick, where the
  # events in a driven run touch a few in a hundred.
  #
  # A failed run lists the lines that allocated most. The dump they come from
  # also lists Ruby's object shapes and the harness's own objects. Neither is
  # the game's, so neither is listed.
  class AllocationProbe
    WARMUP = 120
    TICKS_PER_SECOND = 60
    OBJECTS_PER_SECOND = 60
    SHARE_OF_TICKS = 0.1
    SITES = 12
    HARNESS = File.expand_path(__FILE__)

    def initialize(objects_per_second: OBJECTS_PER_SECOND, share_of_ticks: SHARE_OF_TICKS)
      @objects_per_second = objects_per_second
      @share_of_ticks = share_of_ticks
      @per_tick = []
      @sites = []
    end

    # Called once a tick, with the tick's number counted from 1.
    def tick(number)
      if number == WARMUP
        start
      elsif @counted
        note
      end
    end

    # Stops counting at the end of the run, and traces what was counted.
    def finish
      return unless @counted

      note
      ObjectSpace.trace_object_allocations_stop
      @sites = sites
      @counted = nil
      GC.enable
    end

    # Whether the run went over either budget, or ended before its warm-up
    # did and so measured nothing.
    def failed? = @per_tick.empty? || per_second > @objects_per_second || share > @share_of_ticks

    def lines
      return ["the run ended before its #{WARMUP}-tick warm-up did, so nothing was measured"] if @per_tick.empty?

      [format('%<n>d objects over %<ticks>d ticks: %<rate>.1f a second (budget %<budget>d)',
              n: total, ticks: @per_tick.size, rate: per_second, budget: @objects_per_second),
       format('%<busy>d of %<ticks>d ticks allocated anything: %<share>.1f%% (budget %<budget>.1f%%)',
              busy: busy, ticks: @per_tick.size, share: share * 100, budget: @share_of_ticks * 100),
       "worst second: #{worst_second}",
       *(failed? ? ['where, most first:', *@sites] : [])]
    end

    private

    def start
      GC.start
      GC.disable
      @generation = GC.count
      ObjectSpace.trace_object_allocations_start
      @counted = GC.stat(:total_allocated_objects)
    end

    def note
      now = GC.stat(:total_allocated_objects)
      @per_tick << (now - @counted)
      @counted = GC.stat(:total_allocated_objects)
    end

    def total = @per_tick.sum
    def busy = @per_tick.count(&:positive?)
    def per_second = total.fdiv(@per_tick.size) * TICKS_PER_SECOND
    def share = busy.fdiv(@per_tick.size)
    def worst_second = @per_tick.each_slice(TICKS_PER_SECOND).map(&:sum).max

    def sites
      counts = Hash.new(0)
      ObjectSpace.dump_all(output: :string, since: @generation).each_line do |line|
        object = JSON.parse(line)
        next if object['type'] == 'SHAPE' || (object['file'] && File.expand_path(object['file']) == HARNESS)

        counts[site(object)] += 1
      end
      counts.sort_by { |_, n| -n }.first(SITES).map { |where, n| format('%6d  %s', n, where) }
    end

    def site(object)
      type = object['type'] == 'IMEMO' ? "IMEMO/#{object['imemo_type']}" : object['type']
      return "#{type} (no Ruby frame)" unless object['file']

      "#{type} #{object['file'].delete_prefix("#{ROOT}/")}:#{object['line']} in #{object['method']}"
    end
  end

  class << self
    # Drives one project and returns what it did.
    #
    # `installed:` leaves the load path alone, so `rgame` resolves to whatever
    # RubyGems has installed rather than to this checkout. That is what lets the
    # same harness prove a built gem works on a machine that did not build it —
    # and because the difference is invisible in a report full of draw counts,
    # every run says which `core_ext` and `util_ext` it loaded and from where.
    # An example under `examples/` puts its own directory's `lib` on the path
    # too, so driving the copy inside an installed gem loads that gem either way.
    #
    # Every example that saves passes `RGAME_SAVE_DIR` to `Util::SaveFile` as
    # its `dir:`, and saves into the player's real data directory when it is
    # unset. So a run given none gets a fresh directory, removed afterwards:
    # nothing an earlier run saved can change what this one does. Pass one to keep a save across two runs. The
    # report names a directory only when it was passed, so two runs' reports
    # stay comparable byte for byte.
    #
    # `allocations:` counts what the run allocates instead of what it drew; see
    # AllocationProbe. It records nothing, because recording would allocate far
    # more than any game. `ticks: nil` runs 240 ticks, and with `allocations:`
    # the whole script or AllocationProbe::WARMUP and 300 more, the longer.
    def run(project:, script_path:, ticks: nil, gamepad: false, texts: false, installed: false,
            allocations: false, out: $stdout)
      fresh = ENV['RGAME_SAVE_DIR'].nil?
      ENV['RGAME_SAVE_DIR'] = Dir.mktmpdir('rgame-drive-') if fresh
      drive(project, script_path, ticks, gamepad, texts, installed, allocations, out, fresh)
    ensure
      FileUtils.remove_entry(ENV.delete('RGAME_SAVE_DIR')) if fresh && ENV['RGAME_SAVE_DIR']
    end

    def drive(project, script_path, ticks, gamepad, texts, installed, allocations, out, fresh)
      HeadlessDisplay.start
      checkout_lib = File.join(ROOT, 'lib')
      $LOAD_PATH.unshift(checkout_lib) unless installed || $LOAD_PATH.include?(checkout_lib)
      require 'rgame/game'

      script = Script.load(script_path)
      report = Report.new(texts: texts)
      report.loaded_from = loaded_binaries
      report.saves = fresh ? 'a fresh directory, removed after the run' : ENV.fetch('RGAME_SAVE_DIR')
      report.allocations = AllocationProbe.new(**script.budget) if allocations
      ticks ||= allocations ? [script.length, AllocationProbe::WARMUP + 300].max : 240
      if gamepad
        require_relative '../spec_core/support/virtual_gamepad'
        install(report, nil, ticks, pad: ScriptedGamepad.new(script))
      else
        install(report, ScriptedInput.new(script), ticks)
      end
      report_missing_keys(report)
      load File.expand_path(project, ROOT)

      out.puts report
      report
    end

    # Whether a run failed on its translations: a key went unanswered in a
    # project that loaded tables. A project with no tables has made no promise
    # about its text, so it only gets the report section.
    def missing_translations?(report) = !report.missing_keys.empty? && !RGame::Engine::I18n.available.empty?

    # Whether the run never drew. A project that reached no frame did not run at
    # all, whatever the rest of the report says, so it fails rather than
    # reporting a page of zeroes somebody has to notice.
    def drew_nothing?(report) = report.frames.zero?

    private

    def loaded_binaries = $LOADED_FEATURES.grep(%r{rgame/(?:core|util)_ext\.})

    def report_missing_keys(report)
      RGame::Engine::I18n.missing = ->(key, _chain) { report.record_missing(key) || key }
    end

    def install(report, input, budget, pad: nil)
      RGame::Game.prepend(game_probe(report, input, budget, pad))
      RGame::Engine::Scene::SceneStack.prepend(scene_probe(report)) unless report.allocations
    end

    def game_probe(report, input, budget, pad)
      recording = report.allocations.nil?
      Module.new do
        define_method(:initialize) do |**kwargs|
          extra = pad ? { device: RGame::Util::Controls.gamepad(0) } : { input: input }
          extra[:audio] = AudioProbe.new(RGame::Core::Audio.new, report) if recording
          super(**kwargs, **extra)
          @renderer = RendererProbe.new(@renderer, report) if recording
        end

        define_method(:update) do |dt|
          if pad
            pad.tick(report.ticks)
          else
            input.gamepad_slots.each { |slot| gamepad_connected(slot) } if report.ticks.zero?
            input.tick = report.ticks
          end
          report.ticks += 1
          report.allocations&.tick(report.ticks)
          super(dt)
          next unless report.ticks >= budget

          report.allocations&.finish
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

if $PROGRAM_NAME == __FILE__
  options = { ticks: nil, script: nil, gamepad: false, seed: nil, texts: false, installed: false, allocations: false }
  parser = OptionParser.new do |o|
    o.banner = 'Usage: ruby tools/drive_test_project.rb PROJECT_MAIN [options]'
    o.on('--ticks N', Integer, 'Stop after N simulation ticks (default 240, or the script with --allocations)') do |n|
      options[:ticks] = n
    end
    o.on('--script PATH', 'Input script (default: tools/drive/<project path>.rb)') { options[:script] = it }
    o.on('--gamepad', 'Drive a synthetic SDL controller instead of the input backend') { options[:gamepad] = true }
    o.on('--seed N', Integer, 'Seed the project RNG, so two runs can be compared') { options[:seed] = it }
    o.on('--texts', 'List every distinct string drawn with text, overall and per clip') { options[:texts] = true }
    o.on('--installed', 'Load rgame as installed, instead of from this checkout') { options[:installed] = true }
    o.on('--allocations', 'Count what the run allocates once warm, and fail over its budget') do
      options[:allocations] = true
    end
  end
  parser.parse!

  ENV['RGAME_SEED'] = options[:seed].to_s if options[:seed]

  project = ARGV.shift or abort(parser.to_s)

  script_path = options[:script] || DriveTestProject.default_script_for(project)
  unless File.exist?(script_path)
    abort "No script at #{script_path}. Write one (see tools/drive/**/*.rb) or pass --script."
  end

  report = DriveTestProject.run(project: project, script_path: script_path,
                                ticks: options[:ticks], gamepad: options.fetch(:gamepad, false),
                                texts: options[:texts], installed: options[:installed],
                                allocations: options[:allocations])

  abort "#{project} drew nothing in #{report.ticks} ticks." if DriveTestProject.drew_nothing?(report)
  exit 1 if DriveTestProject.missing_translations?(report)
  exit 1 if report.allocations&.failed?
end
