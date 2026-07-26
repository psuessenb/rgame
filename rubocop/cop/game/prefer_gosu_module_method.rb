# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # In per-frame methods, prefer Gosu's *module* methods over the deprecated
      # Window/instance compat shims.
      #
      # Gosu's `gosu/compat.rb` re-exposes these methods on instances with
      # `define_method(name) { |*args, &block| Gosu.send(name, *args, &block) }`; the
      # `*args` splat allocates an Array on every call — once per polled key, every frame.
      # The module method (`Gosu.button_down?(id)`) is what the shim forwards to anyway,
      # but allocation-free.
      #
      # Conservative on purpose: only an explicit, non-`Gosu` receiver is flagged
      # (`@window.button_down?`), so unrelated `$stdout.flush` / `obj.record` calls are
      # left alone.
      #
      # @example
      #   # bad
      #   def draw(_r) = @window.button_down?(id)
      #   # good
      #   def draw(_r) = Gosu.button_down?(id)
      class PreferGosuModuleMethod < RuboCop::Cop::Base
        include HotPath

        MSG = 'Use `Gosu.%{name}` instead of the deprecated `%{name}` instance shim, ' \
              'which allocates an args Array per call.'

        # The instance methods gosu/compat.rb turns into allocating shims.
        SHIMS = %i[
          draw_line draw_triangle draw_quad draw_rect flush gl clip_to record
          transform translate rotate scale button_id_to_char char_to_button_id button_down?
        ].freeze

        def on_def(node)
          return unless hot_path_def?(node)

          node.each_descendant(:send) do |send_node|
            next unless SHIMS.include?(send_node.method_name)
            next unless flagged_receiver?(send_node.receiver)

            add_offense(send_node.loc.selector, message: format(MSG, name: send_node.method_name))
          end
        end

        private

        def flagged_receiver?(receiver)
          return false if receiver.nil? # bare call (implicit self) — too ambiguous to flag
          return false if receiver.const_type? && receiver.const_name == 'Gosu'

          true
        end
      end
    end
  end
end
