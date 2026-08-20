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
    # | `axis:` | `axis` | `[negative_id, positive_id]` — a digital axis from two buttons |
    # | `stick:` | `axis` | an analog axis id, for a real stick or trigger |
    #
    # ## One table serves every device
    #
    # Listing a key and a pad button in the same entry is safe, and needs no
    # per-device branching, because **a device only answers for its own kind of
    # input** — asking a gamepad about a keyboard scancode is `false`, never the
    # keyboard's answer (see docs/api/input.md). So `fire` can be "Space or A"
    # and each player's device picks out the half that applies to it.
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
      Binding = Struct.new(:buttons, :negative, :positive, :stick)

      SOURCES = %i[buttons axis stick].freeze

      # The universal set, merged into every map unless the game overrides it.
      #
      # The UI package navigates and activates through these, so a control can
      # rely on them existing for *every* player without a game having declared
      # them. They are prefixed rather than plain (`ui_up`, not `up`) so a game
      # is free to use `:up` for something of its own.
      #
      # `ui_cancel` is Escape, which is why RGame::Game's quit key is F2: the
      # button a player expects to back out of a menu belongs to the menu.
      UI = {
        ui_up: { buttons: [Controls::KEY_UP, Controls::PAD_DPAD_UP] },
        ui_down: { buttons: [Controls::KEY_DOWN, Controls::PAD_DPAD_DOWN] },
        ui_left: { buttons: [Controls::KEY_LEFT, Controls::PAD_DPAD_LEFT] },
        ui_right: { buttons: [Controls::KEY_RIGHT, Controls::PAD_DPAD_RIGHT] },
        ui_confirm: { buttons: [Controls::KEY_RETURN, Controls::KEY_SPACE, Controls::PAD_A] },
        ui_cancel: { buttons: [Controls::KEY_ESCAPE, Controls::PAD_B] }
      }.freeze

      # A playable starting point: eight-way movement on the arrows or the left
      # stick, and a fire button. A game that wants exactly this declares
      # nothing at all.
      DEFAULT_ACTIONS = {
        move_x: { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT], stick: Controls::AXIS_LEFT_X },
        move_y: { axis: [Controls::KEY_UP, Controls::KEY_DOWN], stick: Controls::AXIS_LEFT_Y },
        fire: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
      }.freeze

      # Every action this map can answer for, as `name => Binding`.
      attr_reader :bindings

      # `entries` are merged over the universal UI set, so declaring a game's
      # actions never costs it the ones the UI needs.
      def initialize(entries = {})
        @bindings = UI.merge(entries).to_h { |name, entry| [name, build(name, entry)] }.freeze
      end

      # The default map: the UI set plus DEFAULT_ACTIONS.
      def self.default = new(DEFAULT_ACTIONS)

      # A copy with `entries` overriding, which is how a game rebinds one action
      # without restating the rest.
      def merge(entries) = self.class.new(to_h.merge(entries))

      def [](action) = @bindings[action]

      def actions = @bindings.keys

      # The entries in the shape they were declared in, so a map can be edited
      # and rebuilt (a config screen) or merged.
      def to_h
        @bindings.to_h do |name, binding|
          entry = {}
          entry[:buttons] = binding.buttons if binding.buttons
          entry[:axis] = [binding.negative, binding.positive] if binding.positive
          entry[:stick] = binding.stick if binding.stick
          [name, entry]
        end
      end

      private

      # Malformed entries raise here rather than reading as "nothing is ever
      # pressed" for the rest of the program. An action name misspelled at a
      # *read* site is still silent — see Actions — but one misspelled in the
      # map is the mistake that is actually easy to make, and this catches it at
      # construction rather than at the first frame nobody can move.
      def build(name, entry)
        unknown = entry.keys - SOURCES
        raise ArgumentError, "#{name}: unknown source #{unknown.first.inspect}" unless unknown.empty?

        buttons = freeze_ids(name, entry[:buttons])
        negative, positive = axis_pair(name, entry[:axis])
        raise ArgumentError, "#{name}: no buttons, axis or stick" if buttons.nil? && positive.nil? && entry[:stick].nil?

        Binding.new(buttons, negative, positive, entry[:stick]).freeze
      end

      def freeze_ids(name, ids)
        return nil if ids.nil?
        raise ArgumentError, "#{name}: buttons must be a list of ids" unless ids.is_a?(Array) && !ids.empty?

        ids.dup.freeze
      end

      def axis_pair(name, pair)
        return [nil, nil] if pair.nil?

        unless pair.is_a?(Array) && pair.size == 2
          raise ArgumentError, "#{name}: axis must be [negative_id, positive_id]"
        end

        pair
      end
    end
  end
end
