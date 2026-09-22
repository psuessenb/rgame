# frozen_string_literal: true

module RGame
  module Engine
    # The rule for the two classes a game subclasses, Node2D and Component: a
    # method whose name starts with `_` is a hook, and a subclass may define one
    # only if an ancestor has it or the class declared it with `hook`.
    #
    #   class Hop < RGame::Engine::Node2D
    #     def _update(dt) = ...        # fine: Node2D calls it
    #     def _updte(dt) = ...         # NameError: no hook of that name
    #     def _attach = ...            # NameError: a component's hook, not a node's
    #   end
    #
    # A misspelled hook is never called, and nothing else would say so. The same
    # goes for a hook guessed from another engine, such as Godot's `_process`.
    # The message lists the hooks the class has.
    #
    # A class that adds a hook of its own for its subclasses declares it before
    # defining it, as UI::Button does:
    #
    #   hook :_gain_focus, :_lose_focus
    #   def _gain_focus; end
    #
    # What it cannot see: a method arriving through `include` or `prepend` of a
    # module, which does not pass through `method_added`.
    module Hooks
      PREFIX = '_'

      def self.extended(base)
        base.define_singleton_method(:hook_base) { base }
        base.singleton_class.send(:private, :hook_base)
      end

      # Declares new hooks on this class, so it and its subclasses may define
      # them. Each name starts with `_`.
      def hook(*names)
        names.each do |name|
          raise ArgumentError, "hook #{name.inspect}: a hook's name starts with _" unless name.start_with?(PREFIX)
        end
        declared_hooks.concat(names)
      end

      # Every hook this class may define: its ancestors' methods whose names
      # start with `_`, and the ones it declared.
      def hooks
        methods = superclass.public_instance_methods + superclass.private_instance_methods +
                  superclass.protected_instance_methods
        (methods.select { hook_name?(it) } + declared_hooks).uniq.sort
      end

      def method_added(name)
        super
        return if equal?(hook_base) || !hook_name?(name)
        return if declared_hooks.include?(name) || superclass.method_defined?(name) ||
                  superclass.private_method_defined?(name)

        raise NameError.new("#{self}##{name} is no hook of #{hook_base}, so nothing would ever call it. " \
                            "The hooks are #{hooks.join(', ')}. Name a helper without the leading _, " \
                            "or declare a new hook first: hook :#{name}.", name)
      end

      private

      def hook_name?(name) = name.start_with?(PREFIX) && !name.start_with?('__')
      def declared_hooks = (@declared_hooks ||= [])
    end
  end
end
