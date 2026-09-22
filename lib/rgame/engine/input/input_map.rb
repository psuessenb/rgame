# frozen_string_literal: true

module RGame
  module Engine
    # What physical inputs mean, for one player.
    #
    #   map = InputMap.new(
    #     thrust: { axis: [Controls::KEY_DOWN, Controls::KEY_UP], stick: Controls::AXIS_TRIGGER_RIGHT },
    #     fire:   { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
    #   )
    #
    # One entry per action, naming **physical ids from RGame::Util::Controls**
    # directly. That is the whole point of this class: it is the single table a
    # rebinding screen edits, and it holds nothing but integers, so the engine
    # layer may own one outright.
    #
    # Three kinds of source, and an action may combine them:
    #
    # | Key | Reads as | Meaning |
    # |---|---|---|
    # | `buttons:` | `held?` | down if *any* listed id is down |
    # | `axis:` | `axis` | `[negative_id, positive_id]`, or a list of such pairs — a digital axis from buttons |
    # | `stick:` | `axis` | an analog axis id, for a real stick or trigger |
    #
    # ## A hold and a tap are declared here, not counted by the caller
    #
    # Two more keys say *when* an action's buttons count as pressed:
    #
    #   interact: { buttons: [Controls::KEY_E, Controls::PAD_A], tap: 0.3 },
    #   search:   { buttons: [Controls::KEY_E, Controls::PAD_A], hold: 0.6 }
    #
    # `hold:` is the seconds the buttons must be down before the action presses;
    # `tap:` is the seconds within which the release must come for it to press at
    # all. **One button can back both**, which is the whole point: E tapped opens
    # the chest and E held searches it. Holding past the tap's threshold means
    # the release presses nothing, so the two never fire together.
    #
    # Both are numbers rather than `true`, so the threshold is a literal a
    # rebinding screen can show and a designer can argue with. `ActionMapper`
    # measures them from the timestep it polls with, and a game reads the
    # ordinary `pressed?`, `held?` and `released?` — a hold is a level that
    # begins late, and a tap is a one-tick pulse on the way up.
    #
    # ## A chord is buttons held together
    #
    # `all:` is an action that presses when the last of its ids arrives and reads
    # held while every one of them is down:
    #
    #   swap: { all: [Controls::PAD_LEFT_SHOULDER, Controls::PAD_RIGHT_SHOULDER] }
    #
    # **While a chord is held, the plain actions on its buttons read as not
    # held.** Otherwise the shoulder button that blocks would go on blocking
    # through the swap, and a game would have to check for the chord in every
    # action that shares a button with it. Which actions a chord silences is
    # worked out here, once, from the ids they declare.
    #
    # A chord is held on **one** device, because a player holding two buttons at
    # once is holding one thing. So an entry takes a list of chords, exactly as
    # `axis:` takes a list of pairs, and the action is held while any one of them
    # is complete:
    #
    #   swap: { all: [[Controls::KEY_Q, Controls::KEY_E],
    #                 [Controls::PAD_LEFT_SHOULDER, Controls::PAD_RIGHT_SHOULDER]] }
    #
    # Without that, a keyboard chord and a pad chord would be two actions with
    # one meaning, and every reader of either would have to know both.
    #
    # ## One table serves every device
    #
    # Listing a key and a pad button in the same entry is safe, and needs no
    # per-device branching, because **a device only answers for its own kind of
    # input** — asking a gamepad about a keyboard scancode is `false`, never the
    # keyboard's answer (see docs/api/input.md). So `fire` can be "Space or A"
    # and each player's device picks out the half that applies to it.
    #
    # ## An axis can have several pairs, like a button can have several ids
    #
    # `axis: [KEY_LEFT, KEY_RIGHT]` is the common case and stays a bare pair.
    # A list of pairs binds more than one control to the same axis:
    #
    #   move_x: { axis: [[Controls::KEY_LEFT, Controls::KEY_RIGHT],
    #                    [Controls::PAD_DPAD_LEFT, Controls::PAD_DPAD_RIGHT]],
    #             stick: Controls::AXIS_LEFT_X }
    #
    # Without it a d-pad cannot drive movement at all, because the same action
    # already needed the arrow keys. The largest deflection wins, so the pairs
    # cost nothing on a device that has only one of them.
    #
    # This replaces a two-stage scheme in which a game's action map named
    # RGame::Core::Input's action names, which named physical ids — two tables in
    # series, neither of them the one a config screen wanted, and the lower one
    # unreachable from the engine layer, which may not name Core at all.
    #
    # ## A stick's sign is the device's, not the game's
    #
    # `AXIS_LEFT_Y` is positive *downwards*, like screen coordinates. An action
    # that wants the opposite ("thrust", "climb") negates at the call site or
    # binds a trigger instead — the map stays declarative rather than growing an
    # inversion flag that every reader would then have to check for.
    class InputMap
      Controls = RGame::Util::Controls

      # One action's resolved sources. Built once, at construction, so polling
      # walks plain attribute reads and allocates nothing.
      #
      # `buttons` is "held if any of these is down"; `pairs` is a list of
      # `[negative, positive]` button pairs, each a digital axis; `stick` is an
      # analog axis id; `all` is a list of chords, each held when every one of its
      # ids is down.
      # `hold` and `tap` are thresholds in seconds, and an action has at most one
      # of them. `silences` is the plain actions a chord switches off while it is
      # held, worked out from the map as a whole.
      # rubocop:disable Lint/StructNewOverride -- a member is named after the entry key it
      # holds, and `tap:` is that key. Kernel#tap on a Binding is worth less than the two
      # spellings matching, and nothing in the engine taps one.
      Binding = Struct.new(:buttons, :pairs, :stick, :all, :hold, :tap, :silences)
      # rubocop:enable Lint/StructNewOverride

      SOURCES = %i[buttons axis stick all hold tap].freeze

      UI = {
        ui_up: { buttons: [Controls::KEY_UP, Controls::PAD_DPAD_UP] },
        ui_down: { buttons: [Controls::KEY_DOWN, Controls::PAD_DPAD_DOWN] },
        ui_left: { buttons: [Controls::KEY_LEFT, Controls::PAD_DPAD_LEFT] },
        ui_right: { buttons: [Controls::KEY_RIGHT, Controls::PAD_DPAD_RIGHT] },
        ui_confirm: { buttons: [Controls::KEY_RETURN, Controls::KEY_SPACE, Controls::PAD_A] },
        ui_cancel: { buttons: [Controls::KEY_ESCAPE, Controls::PAD_B] },
        ui_radial_x: { axis: [[Controls::KEY_LEFT, Controls::KEY_RIGHT],
                              [Controls::PAD_DPAD_LEFT, Controls::PAD_DPAD_RIGHT]],
                       stick: Controls::AXIS_LEFT_X },
        ui_radial_y: { axis: [[Controls::KEY_UP, Controls::KEY_DOWN],
                              [Controls::PAD_DPAD_UP, Controls::PAD_DPAD_DOWN]],
                       stick: Controls::AXIS_LEFT_Y }
      }.freeze

      DEFAULT_ACTIONS = {
        move_x: { axis: [[Controls::KEY_LEFT, Controls::KEY_RIGHT],
                         [Controls::KEY_A, Controls::KEY_D],
                         [Controls::PAD_DPAD_LEFT, Controls::PAD_DPAD_RIGHT]],
                  stick: Controls::AXIS_LEFT_X },
        move_y: { axis: [[Controls::KEY_UP, Controls::KEY_DOWN],
                         [Controls::KEY_W, Controls::KEY_S],
                         [Controls::PAD_DPAD_UP, Controls::PAD_DPAD_DOWN]],
                  stick: Controls::AXIS_LEFT_Y },
        fire: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
      }.freeze

      # Every action this map can answer for, as `name => Binding`.
      attr_reader :bindings

      # `entries` are merged over the universal UI set, so declaring a game's
      # actions never costs it the ones the UI needs.
      def initialize(entries = {})
        bindings = UI.merge(entries).to_h { |name, entry| [name, build(name, entry)] }
        bindings.each { |name, binding| silence(name, binding, bindings) }
        @bindings = bindings.each_value(&:freeze).freeze
      end

      # The default map: the UI set plus DEFAULT_ACTIONS.
      def self.default = new(DEFAULT_ACTIONS)

      # A copy with `entries` overriding, which is how a game rebinds one action
      # without restating the rest.
      def merge(entries) = self.class.new(to_h.merge(entries))

      def [](action) = @bindings[action]

      def actions = @bindings.keys

      # The button bound to `action` that `device` can actually press, or nil.
      #
      # This undoes what the section above describes. One entry lists a key and
      # a pad button together so that polling needs no branch, and that is right
      # for reading input and wrong for *showing* it: a prompt has to say "press
      # A" or "press Space", never both, and which one depends on what the
      # player last touched.
      #
      #   map.button_for(:fire, Controls::KEYBOARD)    # => KEY_SPACE
      #   map.button_for(:fire, Controls.gamepad(0))   # => PAD_A
      #
      # The first match wins, so the order an entry lists its ids in is the order
      # a prompt prefers them — `ui_confirm` names Return before Space, and a
      # prompt for it says Return.
      #
      # Nil for an action nobody bound, for one with no buttons at all (a stick
      # or a digital axis is not a button and a prompt for one is a different
      # picture), and for a device kind the entry does not cover. A caller
      # showing a prompt has to handle that nil either way, because a rebinding
      # screen can leave an action unbound.
      #
      # Allocation-free, so a HUD may call it per frame rather than caching a
      # string it would then have to invalidate.
      def button_for(action, device)
        binding = @bindings[action]
        buttons = binding&.buttons
        return nil if buttons.nil?

        pad = Controls.gamepad?(device)
        buttons.find { |id| Controls.pad_button?(id) == pad }
      end

      # The entries in the shape they were declared in, so a map can be edited
      # and rebuilt (a config screen) or merged.
      def to_h
        @bindings.to_h do |name, binding|
          entry = {}
          entry[:buttons] = binding.buttons if binding.buttons
          entry[:axis] = binding.pairs.size == 1 ? binding.pairs.first : binding.pairs if binding.pairs
          entry[:stick] = binding.stick if binding.stick
          entry[:all] = binding.all.size == 1 ? binding.all.first : binding.all if binding.all
          entry[:hold] = binding.hold if binding.hold
          entry[:tap] = binding.tap if binding.tap
          [name, entry]
        end
      end

      private

      def build(name, entry)
        unknown = entry.keys - SOURCES
        raise ArgumentError, "#{name}: unknown source #{unknown.first.inspect}" unless unknown.empty?

        buttons = freeze_ids(name, entry[:buttons])
        pairs = axis_pairs(name, entry[:axis])
        all = chords(name, entry[:all])
        if buttons.nil? && pairs.nil? && all.nil? && entry[:stick].nil?
          raise ArgumentError, "#{name}: no buttons, axis, stick or all"
        end

        check_thresholds(name, entry, buttons || all)
        Binding.new(buttons, pairs, entry[:stick], all, entry[:hold], entry[:tap], nil)
      end

      def silence(name, binding, bindings)
        return if binding.all.nil?

        ids = binding.all.flatten
        binding.silences = bindings.filter_map do |other, candidate|
          other if other != name && candidate.buttons&.intersect?(ids)
        end.freeze
      end

      def chords(name, all)
        return nil if all.nil?

        list = all.is_a?(Array) && all.first.is_a?(Array) ? all : [all]
        list.each { |ids| check_chord(name, ids) }
        list.map { |ids| ids.dup.freeze }.freeze
      end

      def check_chord(name, ids)
        return if ids.is_a?(Array) && ids.size > 1

        raise ArgumentError, "#{name}: all must be at least two ids, or a list of those"
      end

      def check_thresholds(name, entry, buttons)
        hold = entry[:hold]
        tap = entry[:tap]
        raise ArgumentError, "#{name}: hold and tap are two answers to one question" if hold && tap
        return if hold.nil? && tap.nil?
        raise ArgumentError, "#{name}: a hold or a tap needs buttons or all" if buttons.nil?

        check_threshold(name, hold || tap)
      end

      def check_threshold(name, seconds)
        return if seconds.is_a?(Numeric) && seconds.positive?

        raise ArgumentError, "#{name}: a threshold is a positive number of seconds, not #{seconds.inspect}"
      end

      def freeze_ids(name, ids)
        return nil if ids.nil?
        raise ArgumentError, "#{name}: buttons must be a list of ids" unless ids.is_a?(Array) && !ids.empty?

        ids.dup.freeze
      end

      def axis_pairs(name, axis)
        return nil if axis.nil?

        pairs = axis.is_a?(Array) && axis.first.is_a?(Array) ? axis : [axis]
        pairs.each { |pair| check_pair(name, pair) }
        pairs.map { |pair| pair.dup.freeze }.freeze
      end

      def check_pair(name, pair)
        return if pair.is_a?(Array) && pair.size == 2

        raise ArgumentError, "#{name}: axis must be [negative_id, positive_id], or a list of those"
      end
    end
  end
end
