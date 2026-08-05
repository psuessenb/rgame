# frozen_string_literal: true

module Engine
  module Scene
    class SceneStack < Engine::Component
      def initialize
        super
        @stack = []
      end

      def push(scene)
        @stack.push(scene)
        scene.parent = node          # so scene.root resolves up to the host
        scene.scene = scene          # mark the scene as its subtree's scene boundary
        scene.enter_tree             # cascades on_attach/on_add through the scene
        self
      end

      def pop
        scene = @stack.pop
        return self unless scene

        scene.exit_tree              # cascades on_remove/on_detach, releasing systems
        scene.scene = nil
        scene.parent = nil
        self
      end

      def replace(scene)
        pop
        push(scene)
      end

      def current
        @stack.last
      end

      def control(actions)
        return unless (current_scene = current)

        current_scene.control(actions)
      end

      def update(dt)
        return unless (current_scene = current)

        current_scene.update(dt)
      end

      def draw(renderer)
        @stack.each do |scene|
          scene.draw(renderer)
        end
      end

      # Scenes live in @stack, off the host's child list, so the host's #sweep_freed
      # can't reach them — forward the sweep into the active scene's subtree.
      def sweep_freed
        current&.sweep_freed
      end
    end
  end
end
