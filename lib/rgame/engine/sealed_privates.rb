# frozen_string_literal: true

module RGame
  module Engine
    # The rule for the two classes a game subclasses, Node2D and Component: a
    # non-public method whose name starts with `_` is the engine's machinery, and
    # a subclass defining a method of the same name raises where it is defined.
    #
    #   class Hop < RGame::Engine::Node2D
    #     def _draw_content(renderer, view) = ...   # NameError: would replace Node2D#_draw_content
    #     def draw_children(renderer, view) = ...   # fine: no underscore, meant to be overridden
    #   end
    #
    # `private` in Ruby says who may *call* a method, not who may *replace* one: a
    # subclass method of the same name is found first, and the base class quietly
    # stops doing what that method did — for that subclass only, with the failure
    # somewhere else entirely. So the underscore is the opt-in. A private or
    # protected method *without* one is a seam, meant to be overridden with
    # `super`, and nothing guards it.
    #
    # Only the base class's own methods are sealed. A private hook an engine
    # subclass writes for its own subclasses — Components::Mover's `take_step` —
    # is not covered, and the underscore convention does not apply outside these
    # two classes.
    #
    # What it cannot see: a method arriving through `include` or `prepend` of a
    # module, which does not pass through `method_added`.
    module SealedPrivates
      def self.extended(base)
        base.define_singleton_method(:sealed_base) { base }
      end

      # Every method a subclass may not define: the base's non-public methods
      # whose names start with `_`.
      def sealed_methods
        base = sealed_base
        (base.private_instance_methods(false) + base.protected_instance_methods(false))
          .select { |name| name.start_with?('_') }
      end

      def method_added(name)
        super
        base = sealed_base
        return if equal?(base) || !name.start_with?('_')
        return unless base.private_method_defined?(name, false) || base.protected_method_defined?(name, false)

        raise NameError.new("#{self}##{name} would replace #{base}##{name}, which #{base} calls " \
                            "itself, and #{base} would silently stop doing its job for this class. " \
                            'Give the method another name.', name)
      end
    end
  end
end
