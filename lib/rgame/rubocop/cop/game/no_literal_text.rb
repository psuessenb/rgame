# frozen_string_literal: true

module RuboCop
  module Cop
    module Game
      # Flag a String literal drawn or measured as a label: the first argument of
      # `text` or `text_width`, on any receiver.
      #
      # Text a player reads belongs in a translation table, where `RGame::Game`
      # loads it and a language switch reaches it. A literal at the call site is
      # the one place no table can: it shows the same words in every language, and
      # it is the form a reader copies out of an example. Build an `Engine::Text`
      # from a key once, off the per-frame path, and pass it as it is.
      #
      # This sees the call site only. A constant or ivar holding a String passes,
      # so a table of Strings chosen by state is not caught; whether a constant
      # holds words is not a question syntax can answer.
      #
      # @example
      #   # bad
      #   renderer.text('Press Space to jump', 12, 12)
      #   renderer.text("Lives: #{lives}", 12, 34)
      #
      #   # good
      #   @help = Engine::Text.new('help.jump')   # in initialize
      #   renderer.text(@help, 12, 12)
      class NoLiteralText < RuboCop::Cop::Base
        MSG = 'Draw an Engine::Text built from a key, not a String literal: ' \
              'text a player reads belongs in a translation table.'

        RESTRICT_ON_SEND = %i[text text_width].freeze

        def on_send(node)
          label = node.first_argument
          add_offense(label) if label&.type?(:str, :dstr)
        end
        alias on_csend on_send
      end
    end
  end
end
