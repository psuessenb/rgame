# frozen_string_literal: true

module RGame
  module Engine
    # The rule for the two classes a game subclasses, Node2D and Component: a
    # non-public method whose name starts with `rgame_` is the engine's
    # machinery, and a subclass defining a method of the same name raises where
    # it is defined.
    #
    #   class Hop < RGame::Engine::Node2D
    #     def rgame_draw_content(renderer, view) = ...   # NameError: would replace Node2D#rgame_draw_content
    #     def draw_children(renderer, view) = ...        # fine: no prefix, meant to be overridden
    #   end
    #
    # `private` in Ruby says who may *call* a method, not who may *replace* one: a
    # subclass method of the same name is found first, and the base class quietly
    # stops doing what that method did — for that subclass only, with the failure
    # somewhere else entirely. So the prefix is the opt-in. A private or
    # protected method *without* one is a seam, meant to be overridden with
    # `super`, and nothing guards it. The prefix matches the C layer's
    # `rgame_app_push_clip` and the like, and no game names a method that by
    # accident.
    #
    # Only the base class's own methods are sealed. A private hook an engine
    # subclass writes for its own subclasses — Components::Mover's `take_step` —
    # is not covered.
    #
    # The two classes keep their ivars under the prefix as well, `@rgame_opacity`
    # rather than `@opacity`, so an ivar a subclass names is its own.
    # #sealed_reader and its two siblings keep an attribute's public name over
    # the prefixed ivar.
    #
    # What it cannot see: a method arriving through `include` or `prepend` of a
    # module, which does not pass through `method_added`.
    module SealedPrivates
      PREFIX = 'rgame_'

      def self.extended(base)
        base.define_singleton_method(:sealed_base) { base }
        base.singleton_class.send(:private, :sealed_base)
      end

      # A public reader `name` over the ivar `@rgame_<name>`, as fast as an
      # `attr_reader`: it is an alias of a private reader `rgame_<name>`, which
      # the seal covers in Node2D and Component. Returns the names.
      #
      #   sealed_reader :opacity   # node.opacity reads @rgame_opacity
      #
      # The reader is public even below a bare `private`, which sets the
      # visibility of methods the class body defines and does not reach into a
      # macro. A private attribute needs no macro: its methods read the ivar.
      #
      # @api private
      def sealed_reader(*names)
        names.each do |name|
          reader = :"#{PREFIX}#{name}"
          attr_reader reader
          alias_method name, reader
          public name
          private reader
        end
      end

      # A public writer `name=` over `@rgame_<name>`, for an attribute with no
      # check to run, built as #sealed_reader builds a reader. Returns the
      # names.
      #
      # @api private
      def sealed_writer(*names)
        names.each do |name|
          writer = :"#{PREFIX}#{name}="
          attr_writer :"#{PREFIX}#{name}"
          alias_method :"#{name}=", writer
          public :"#{name}="
          private writer
        end
      end

      # Both #sealed_reader and #sealed_writer. Returns the names.
      #
      # @api private
      def sealed_accessor(*names)
        sealed_reader(*names)
        sealed_writer(*names)
      end

      # Every method a subclass may not define: the base's non-public methods
      # whose names start with PREFIX.
      def sealed_methods
        base = sealed_base
        (base.private_instance_methods(false) + base.protected_instance_methods(false))
          .select { |name| name.start_with?(PREFIX) }
      end

      def method_added(name)
        super
        base = sealed_base
        return if equal?(base) || !name.start_with?(PREFIX)
        return unless base.private_method_defined?(name, false) || base.protected_method_defined?(name, false)

        raise NameError.new("#{self}##{name} would replace #{base}##{name}, which #{base} calls " \
                            "itself, and #{base} would silently stop doing its job for this class. " \
                            'Give the method another name.', name)
      end
    end
  end
end
