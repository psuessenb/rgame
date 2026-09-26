# frozen_string_literal: true

module RGame
  module Engine
    # rgame's own classes and modules are closed to the `class` and `module`
    # keywords of the code that uses them. A game subclasses Node2D or Component
    # and never reopens one of rgame's: a constant, method or singleton method
    # written in a class or module body outside rgame, onto a class or module
    # under RGame::Engine or RGame::Util, raises where it is written.
    #
    #   module MyGame
    #     Engine = RGame::Engine
    #     Components = Engine::Components
    #
    #     module Components                    # rgame's Components, reopened
    #       class Timer < Engine::Component    # rgame's Components::Timer
    #         def _update(dt) = ...            # NameError: would change RGame::Engine::Components::Timer
    #       end
    #     end
    #   end
    #
    # A game's module names rgame's namespaces `Engine`, `Util`, `UI` and
    # `Components`. A module of the game's own with one of those names therefore
    # reopens rgame's rather than making a new one, and Ruby says nothing: the
    # game's classes land in rgame's namespace, and a class sharing a name with
    # one of rgame's, such as `Timer`, replaces rgame's methods.
    #
    # Only a body written with the keywords counts. A spec that stubs a method
    # on an rgame module, `stub_const`, `class_eval` and `define_method` define
    # from a method or a block, and pass. So do rgame's own files, and a class
    # rgame loads later is closed as it is defined. What it cannot see: a
    # reopening that defines nothing, and a method arriving through `include` or
    # `prepend`, which does not pass through `method_added`.
    #
    # @api private
    module Closed
      ROOT = File.expand_path('..', __dir__)

      BODY = /\A(?:<class:|<module:|singleton class\z)/

      CLOSED = {}.compare_by_identity

      # Closes `namespace` and every class and module defined under it.
      def self.close(namespace)
        return if CLOSED.key?(namespace)

        CLOSED[namespace] = true
        namespace.extend(self)
        namespace.constants(false).each { close_constant(namespace, it) }
      end

      def self.close_constant(namespace, name)
        return if namespace.autoload?(name, false)

        value = namespace.const_get(name, false)
        close(value) if value.is_a?(Module) && value.name&.start_with?("#{namespace.name}::")
      end

      def self.closed?(mod) = CLOSED.key?(mod)

      # Raises when `location`, where `what` was defined, is a class or module
      # body outside rgame. `callers` are the frames that led to the definition.
      def self.check(what, location, callers)
        return if location.nil? || rgame_file?(location.first)

        site = callers.find { !rgame_file?(it.path) }
        return unless site&.label&.match?(BODY)

        raise NameError, "#{location.first}:#{location.last} would change #{what}, which is rgame's own. " \
                         "rgame's classes and modules are closed: subclass one, or give yours a name of " \
                         "its own. Inside a game's module, Engine, Util, UI and Components name rgame's, " \
                         "so a module of the same name there reopens rgame's rather than making a new one."
      end

      # True for a file in rgame's own lib/, and for a definition made in C,
      # which has none.
      def self.rgame_file?(file)
        return true if file.nil? || file.empty?

        path = File.expand_path(file)
        path.start_with?(ROOT) || (File.file?(path) && File.realpath(path).start_with?(File.realpath(ROOT)))
      end

      def method_added(name)
        super
        Closed.check("#{self}##{name}", instance_method(name).source_location, caller_locations) if Closed.closed?(self)
      end

      def singleton_method_added(name)
        super
        Closed.check("#{self}.#{name}", method(name).source_location, caller_locations) if Closed.closed?(self)
      end

      def const_added(name)
        super
        return unless Closed.closed?(self)

        Closed.check("#{self}::#{name}", const_source_location(name), caller_locations)
        Closed.close_constant(self, name)
      end
    end
  end
end
