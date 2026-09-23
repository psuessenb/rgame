# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Takes hold of a Pushable while an action is held, so the node's mover drags it
      # along: forwards, backwards and sideways.
      #
      #   hero.add_component(CharacterBody.new(speed: 60, blocked_by: %i[tiles crate]))
      #   hero.add_component(Grab.new(layer: :crate, range: 24))
      #
      # "What is nearest in range on this layer" is the question Targeting answers, so this
      # is a Targeting plus a held button. While `action` is held it holds the Pushable on
      # its #target's node, and keeps that one until the action is let go, even if
      # something else comes nearer. The tick the action is released, it lets go. A target
      # with no Pushable is not held.
      #
      # It hands the crate to the sibling Mover in `_control`, and the mover moves it in
      # `_update`. Every `_control` in the tree runs before any `_update`, so the crate is
      # always in hand before the step that drags it, whatever order the two components
      # were added in. Mover's header says how the step moves both.
      #
      # `action` is read from the actions of whoever owns the node, as Interactor's is, so
      # two players each hold their own crate.
      #
      # Like Interactor it is a Targeting, so a node holding both, or both of these,
      # answers `get_component(Targeting)` with a raise. Hold each by name.
      class Grab < Targeting
        def initialize(range:, layer:, action: :grab, policy: :nearest)
          super(range:, layer:, policy:)
          @action = action
          @held = nil
        end

        # The action this reads, so a game can show the button that holds it.
        attr_reader :action

        # The node being held, or nil.
        def holding = @held&.node

        def _attach
          super
          @mover = require_sibling(Mover)
        end

        def _detach
          release
          @mover = nil
        end

        def _control(actions)
          return release unless actions.held?(@action)

          @held = nil if @held && gone?(@held.node)
          @held ||= pushable_on(target)
          @mover.grabbed = @held
        end

        private

        def pushable_on(candidate)
          return nil if candidate.nil? || gone?(candidate)

          candidate.get_component(Pushable)
        end

        def gone?(candidate) = candidate.freed? || !candidate.in_tree?

        def release
          @held = nil
          @mover&.grabbed = nil
        end
      end
    end
  end
end
