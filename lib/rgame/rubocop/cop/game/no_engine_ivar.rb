# frozen_string_literal: true

module RuboCop
  module Cop
    module Game
      # Flag an ivar starting with `@rgame_` in a game's code: read, written,
      # assigned with `+=` or `||=`, or named by a literal Symbol or String
      # given to `instance_variable_get` and its siblings.
      #
      # Every node and component in `RGame::Engine` keeps its ivars under that
      # prefix, so a game's own ivars never share a name with the engine's. An
      # ivar a game writes with the prefix can only be one of the engine's, and
      # writing it switches off whatever the engine kept there, with no error.
      # A game reaches the engine's state through its public methods.
      #
      # This sees a literal name only. A name built at runtime, such as
      # `instance_variable_get(:"@rgame_#{name}")`, passes.
      #
      # @example
      #   # bad
      #   @rgame_opacity = 0.5
      #   node.instance_variable_get(:@rgame_paused)
      #
      #   # good
      #   self.opacity = 0.5
      #   @opacity = 0.5   # the game's own ivar, which the engine never touches
      class NoEngineIvar < RuboCop::Cop::Base
        MSG = '`%{name}` is the engine\'s: every node and component keeps its ivars under `@rgame_`. ' \
              'Name the ivar without the prefix, or call the public method.'

        PREFIX = '@rgame_'

        RESTRICT_ON_SEND = %i[
          instance_variable_get instance_variable_set instance_variable_defined? remove_instance_variable
        ].freeze

        def on_ivar(node)
          check(node, node.children.first)
        end

        # A compound assignment holds its target as an ivasgn, so `+=`, `||=`
        # and `&&=` arrive here too, as does each target of `@a, @b = ...`.
        def on_ivasgn(node)
          check(node.loc.name, node.children.first)
        end

        def on_send(node)
          name = node.first_argument
          check(name, name.value) if name&.type?(:sym, :str)
        end
        alias on_csend on_send

        private

        def check(location, name)
          add_offense(location, message: format(MSG, name: name)) if name.to_s.start_with?(PREFIX)
        end
      end
    end
  end
end
