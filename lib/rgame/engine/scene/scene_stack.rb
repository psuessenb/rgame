# frozen_string_literal: true

module RGame
  module Engine
    module Scene
      class SceneStack < Engine::Component
        def initialize
          super
          @stack = []
          @players = nil
        end

        # See #control: the scenes this holds need the input source, and a
        # component is only handed one player's snapshot.
        def on_attach = @players = node.system(Engine::Players)

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

        # Scenes live off the host's child list, so the traversal does not reach
        # them on its own — and what has to reach them is the input *source*,
        # not the snapshot this component was handed.
        #
        # A component receives one player's resolved Actions, which is right for
        # a component: it belongs to exactly one node. A scene is a whole subtree
        # and may contain nodes owned by different players, so handing it a
        # single snapshot would flatten all of them onto whoever owns the host.
        # The registry is pulled from the tree instead, the same way any system
        # is, and passed down so each node in the scene resolves its own.
        #
        # Without a registry — a spec driving a stack with a bare snapshot — the
        # snapshot is passed on, which is exactly what it means: one answer for
        # everyone.
        def control(actions)
          return unless (current_scene = current)

          current_scene.control(@players || actions)
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
end
