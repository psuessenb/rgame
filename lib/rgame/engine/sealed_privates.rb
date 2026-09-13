# frozen_string_literal: true

module RGame
  module Engine
    # Refuses a subclass method that would replace a private method of the base
    # class, raising where the subclass is defined.
    #
    #   class Hop < RGame::Engine::Node2D
    #     def draw_content(renderer) = ...   # NameError: would replace Node2D#draw_content
    #   end
    #
    # A base class the game subclasses keeps its machinery in private methods
    # and calls them itself. `private` in Ruby says who may *call* a method, not
    # who may *replace* one: a subclass method of the same name is found first,
    # and the base class quietly stops doing what that method did — for that
    # subclass only, with the failure somewhere else entirely. The public hooks
    # (`on_draw`, `update`, ...) are what a subclass is meant to write, so a
    # clash with a private name is always a mistake, and this makes it fail when
    # the class is loaded rather than when a frame goes wrong.
    #
    # A private method that *is* meant to be overridden, with `super`, is
    # declared so beside its definition:
    #
    #   unsealed :draw_children
    #
    # Only the base class's own private methods are sealed, not those of its
    # subclasses: UI::OptionButton overriding UI::TextButton's private
    # `draw_foreground` is how that hook is used.
    #
    # What it cannot see: a method arriving through `include` or `prepend` of a
    # module, which does not pass through `method_added`.
    module SealedPrivates
      def self.extended(base)
        base.define_singleton_method(:sealed_base) { base }
      end

      # The private methods of the base class a subclass may override.
      def unsealed_privates = sealed_base.instance_variable_get(:@unsealed_privates) || []

      def method_added(name)
        super
        base = sealed_base
        return if equal?(base) || name == :initialize
        return unless base.private_method_defined?(name, false)
        return if unsealed_privates.include?(name)

        raise NameError.new("#{self}##{name} would replace #{base}##{name}, a private method " \
                            "#{base} calls itself, and #{base} would silently stop doing its job " \
                            'for this class. Give the method another name.', name)
      end

      private

      def unsealed(*names)
        raise NameError, "only #{sealed_base} may unseal its own private methods" unless equal?(sealed_base)

        @unsealed_privates = (unsealed_privates + names).freeze
      end
    end
  end
end
