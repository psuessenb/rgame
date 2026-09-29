# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What a node does when an actor presses it: one method of the node for each
      # input action it answers.
      #
      #   chest.add_component(Interaction.new(interact: :open, search: :search))
      #
      #   def open = ...          # a handler may ignore who acted,
      #   def search(by:) = ...   # or take the actor's node as `by:`
      #
      # An actor's Interactor finds the nearest node whose Interaction answers an
      # action it reads, and calls #perform on a press. So the verbs belong to the
      # target: a lever answers `interact` and nothing else, and a hold meant for
      # the chest behind it passes the lever by.
      #
      # A key is the input action's own name, so there is one vocabulary, the
      # InputMap's. A value is a method name rather than a block, because a
      # method's `self` is the node, and a block's is wherever it was written.
      #
      # ## Attach checks what a press would find out too late
      #
      # A node needs a collider, box or circle, for the actor's broadphase to see
      # it, and holds one Interaction, which answers every one of its verbs. Each
      # handler must be a public method of the node that needs no argument beyond
      # `by:`. And each action must be one some player's input map declares,
      # since a misspelled one would never be pressed. A scene with no Players
      # system, such as a headless spec, skips that last check.
      class Interaction < Engine::Component
        # `handlers` maps an input action's name to the name of a method on the
        # node. Raises ArgumentError with none, and for a method name that is not
        # a Symbol.
        def initialize(**handlers)
          super()
          raise ArgumentError, 'an Interaction answers at least one action' if handlers.empty?

          handlers.each do |action, handler|
            next if handler.is_a?(Symbol)

            raise ArgumentError, "the #{action} handler is a method name, a Symbol, not #{handler.inspect}"
          end

          @rgame_handlers = handlers.freeze
          @rgame_actions = handlers.keys.freeze
          @rgame_passes_by = {}
        end

        # The actions this answers, in the order given.
        sealed_reader :actions

        # hot-path
        def answers?(action) = @rgame_handlers.key?(action)

        # Calls the node's handler for `action`, passing `by` to a handler that
        # takes a `by` keyword. `by` is the node that acted. Raises KeyError for
        # an action this does not answer.
        def perform(action, by:)
          handler = @rgame_handlers.fetch(action)
          if @rgame_passes_by[action]
            node.public_send(handler, by:)
          else
            node.public_send(handler)
          end
        end

        def _attach
          require_sibling(Collider)
          refuse_a_second_interaction
          players = node.system(Engine::Players)
          @rgame_handlers.each do |action, handler|
            refuse_an_undeclared_action(action, players) if players
            @rgame_passes_by[action] = takes_by?(action, handler)
          end
        end

        private

        def refuse_a_second_interaction
          count = node.components.count { it.is_a?(Interaction) }
          return if count == 1

          raise ArgumentError, "#{node.class} holds #{count} Interactions. One Interaction answers " \
                               'every action of its node, so give its verbs to one of them.'
        end

        def refuse_an_undeclared_action(action, players)
          return if players.any? { |player| player.input_map[action] }

          raise ArgumentError, "#{node.class} answers the #{action} action, and no player's input map " \
                               'declares it, so nothing would ever press it. Declare it in the ' \
                               "game's input_map, or correct the name."
        end

        def takes_by?(action, handler)
          unless node.respond_to?(handler)
            raise ArgumentError, "#{node.class} has no public method #{handler} for the #{action} action"
          end

          parameters = node.method(handler).parameters
          if parameters.any? { |type, name| type == :req || (type == :keyreq && name != :by) }
            raise ArgumentError, "#{node.class}##{handler} handles the #{action} action, so it takes " \
                                 "nothing or `by:`, and it takes #{parameters.inspect}"
          end

          parameters.any? { |type, name| name == :by && %i[key keyreq].include?(type) }
        end
      end
    end
  end
end
