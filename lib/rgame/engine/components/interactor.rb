# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What the owning node would interact with, and the press that does it.
      #
      #   hero.add_component(Interactor.new(range: 56, layer: :interactable))
      #       .on_interacted { |target| target.open }
      #
      # "What am I standing next to" is the question Targeting already answers
      # for a turret, so this is that component plus a press. #target is the
      # nearest collider's node on `layer` within `range`, refreshed every
      # update and nil when nothing is in reach — which is also what a game
      # draws its prompt over, and why the target is exposed rather than only
      # emitted.
      #
      # `action` is read from the actions of whoever owns the node, so two
      # players each interact with their own target and neither is told the
      # other exists. A press with nothing in range does nothing at all: there
      # is no signal for "tried and missed", because a game that wants one is
      # asking about its own state rather than about what is nearby.
      #
      # ## It is a Targeting, and that has one consequence
      #
      # `get_component(Targeting)` matches this too, so a node holding both
      # cannot be asked for either by class. Hold the one you need by name, the
      # way `add_component` already returns it. A node needing two ranges is
      # the case that wants the names anyway.
      class Interactor < Targeting
        # The press landed on `target`, which is never nil.
        signal :interacted, :target

        def initialize(range:, layer: :interactable, action: :interact, policy: :nearest)
          super(range: range, layer: layer, policy: policy)
          @action = action
        end

        # The action this reads, so a game can show the button that presses it:
        # `player.input_map.button_for(interactor.action, player.device)`.
        attr_reader :action

        def _control(actions)
          return if target.nil? || !actions.pressed?(@action)

          interacted_signal.emit(target)
        end
      end
    end
  end
end
