# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Reaches for the nearest thing that answers a press, and presses it.
      #
      #   hero.add_component(Interactor.new(range: 56, actions: %i[interact search]))
      #   chest.add_component(Interaction.new(interact: :open, search: :search))
      #
      # Each update it queries the scene's CollisionWorld around its node, as
      # Targeting does, and keeps the nearest node whose Interaction answers
      # each of its `actions`. On a press of one, it calls that action's handler
      # on that node, passing its own node as `by:`. A press with nothing in reach
      # does nothing.
      #
      # So the verbs belong to the target, and an action passes over a nearer
      # node that does not answer it: a hold to search reaches the chest behind a
      # lever that only answers `interact`. A collider without an Interaction is
      # never a target, whatever its layer.
      #
      # #target is the nearest node answering any of the actions, and nil when
      # nothing is in reach. A game draws its prompt over it. #target_for names
      # the node one action would reach.
      #
      # The actions are read from whoever owns the node, so two players each
      # press their own target and neither is told the other exists.
      #
      # ## It is a Targeting, and that has one consequence
      #
      # `get_component(Targeting)` matches this too, so a node holding both, or a
      # Grab beside it, cannot be asked for either by class. Hold the one you need
      # by name, the way `add_component` already returns it.
      class Interactor < Targeting
        # `actions` are the input actions this reads, each one an action some
        # Interaction may answer. Raises ArgumentError for an empty list, a name
        # that is not a Symbol, or a name given twice.
        def initialize(range:, actions: [:interact], policy: :nearest)
          super(range:, policy:, having: Interaction)
          unless actions.is_a?(Array) && !actions.empty? && actions.all?(Symbol) && actions.uniq.size == actions.size
            raise ArgumentError, "actions is a list of distinct action names, not #{actions.inspect}"
          end

          @rgame_actions = actions.dup.freeze
          @rgame_answerers = Array.new(actions.size)
          @rgame_distances = Array.new(actions.size)
        end

        # The actions this reads, so a game can show the button for each:
        # `player.input_map.button_for(action, player.device)`.
        sealed_reader :actions

        # The nearest node that answers `action`, or nil. Raises ArgumentError
        # for an action this does not read.
        # hot-path
        def target_for(action)
          index = @rgame_actions.index(action) || refuse_an_unread_action(action)
          @rgame_answerers[index]&.node
        end

        # hot-path
        def _update(_dt)
          @rgame_answerers.fill(nil)
          @rgame_distances.fill(nil)
          x = node.world_x
          y = node.world_y
          @rgame_world.query_circle(x, y, @rgame_range) do |collider|
            candidate = collider.node
            next if candidate.equal?(node)

            interaction = candidate.get_component(Interaction)
            next unless interaction

            dx = collider.cx - x
            dy = collider.cy - y
            consider(interaction, (dx * dx) + (dy * dy))
          end
          @rgame_target = nearest_answerer&.node
        end

        # hot-path
        def _control(actions)
          i = 0
          while i < @rgame_actions.size
            action = @rgame_actions[i]
            answerer = @rgame_answerers[i]
            answerer.perform(action, by: node) if actions.pressed?(action) && answerer
            i += 1
          end
        end

        private

        def consider(interaction, distance)
          i = 0
          while i < @rgame_actions.size
            if interaction.answers?(@rgame_actions[i]) && (@rgame_distances[i].nil? || distance < @rgame_distances[i])
              @rgame_answerers[i] = interaction
              @rgame_distances[i] = distance
            end
            i += 1
          end
        end

        def nearest_answerer
          nearest = nil
          nearest_distance = nil
          i = 0
          while i < @rgame_actions.size
            distance = @rgame_distances[i]
            if distance && (nearest_distance.nil? || distance < nearest_distance)
              nearest = @rgame_answerers[i]
              nearest_distance = distance
            end
            i += 1
          end
          nearest
        end

        def refuse_an_unread_action(action)
          raise ArgumentError, "this Interactor reads #{@rgame_actions.inspect}, not #{action.inspect}"
        end
      end
    end
  end
end
