# frozen_string_literal: true

module RGame
  module Engine
    # A node in a scene graph. We currently have only 2D nodes, but the
    # name reflects this should there ever be a 3D space. Nodes are
    # containers for both containers and nodes. They extend the signal
    # DSL to allow for easy signal usage.
    class Node2D
      extend Engine::Signal::DSL

      attr_accessor :x, :y, :z, :angle, :width, :height, :parent
      attr_writer :scene, :context
      attr_reader :children, :components, :abs_x, :abs_y, :abs_z, :abs_angle

      def initialize(x: 0, y: 0, z: 0, angle: 0, width: 0, height: 0)
        @x = x
        @y = y
        @z = z
        @angle = angle
        @width = width
        @height = height
        @children = []
        @components = []
        @component_slots = {} # slot (Class by default, or a Symbol name) => component
        @parent = nil
        @scene = nil
        @in_tree = false
        @freed = false
      end

      def add_node(node)
        @children << node
        node.parent = self
        # Defer the entered-tree cascade until this node is itself live; otherwise it
        # fires when an ancestor enters (see #enter_tree). This is the construct-vs-enter
        # split — a node built inside another node's initialize is not yet in the tree.
        node.enter_tree if @in_tree
        node
      end

      def remove_node(node)
        node.exit_tree if @in_tree
        @children.delete(node)
        node.parent = nil
        node
      end

      # Look a component up by its slot. A Class/Module is matched by ancestry across every
      # component (so a base class finds a subclass instance); a Symbol names a specific slot
      # (see #add_component's `as:`). A class lookup raises when it's ambiguous — two
      # components share that type — so the caller reaches for the name instead. The scan is
      # allocation-free, so it's safe to call on the per-frame path.
      def get_component(key)
        return @component_slots[key] unless key.is_a?(Module)

        found = nil
        @components.each do |component|
          next unless component.is_a?(key)
          raise ArgumentError, "Multiple components match #{key}; look one up by name" if found

          found = component
        end
        found
      end

      # Attach a component in a named slot. The slot defaults to the component's class, so a
      # node still holds at most one component per class — until you give them distinct
      # names: `add_component(Timer.new, as: :spawn)` / `add_component(Timer.new, as: :wave)`.
      # A taken slot raises, so an accidental duplicate is still caught.
      def add_component(component, as: nil)
        slot = as || component.class
        raise ArgumentError, "Node already has a component in slot #{slot.inspect}" if @component_slots.key?(slot)

        @components << component
        @component_slots[slot] = component
        component.node = self
        component.on_attach if @in_tree
        component
      end

      def remove_component(key)
        component = get_component(key)
        return nil unless component

        component.on_detach if @in_tree
        @components.delete(component)
        @component_slots.delete(@component_slots.key(component))
        component.node = nil
        component
      end

      # Anchors, resolved by walking parents so they can never go stale (a cached
      # back-link set at add-time breaks when children are built before the node is
      # in the tree). Shared systems live as components on an anchor node and are
      # reached through these, not threaded through constructors.

      # The top-most node — a node with no parent is its own root. Global,
      # program-lifetime systems live here as components.
      def root
        @parent ? @parent.root : self
      end

      # The nearest enclosing scene node, marked as a boundary by SceneStack
      # (#scene= self). Scene-lifetime systems live on it as components.
      def scene
        @scene || @parent&.scene
      end

      def context
        @context ||= root.context
      end

      # Nearest system of a class: scene scope first, then the global root.
      def system(klass)
        scene&.get_component(klass) || root.get_component(klass)
      end

      # updates input, both from player (readings actions) as well as
      # AI-driven node control. This run first in a game tick
      # Each phase settles this node first (components, then the node's own
      # hook), then descends into children. Self-before-subtree keeps the
      # transform flowing downward: a component or hook that moves this node
      # does so before children resolve their origin from it.

      def control(actions)
        resolve_origin
        @components.each { it.control(actions) }
        on_control(actions)
        @children.each { it.control(actions) }
      end

      # update game logic and physics (might become two calls with
      # time, but for now works in one step). This runs second in a
      # game tick
      def update(dt)
        resolve_origin
        @components.each { it.update(dt) }
        on_update(dt)
        @children.each { it.update(dt) }
      end

      # update visual game state, drawing the node. This runs last in
      # a game tick
      def draw(renderer)
        resolve_origin
        # Draw this node's own visuals oriented by its absolute angle, then descend.
        # Children resolve their own world transform (resolve_origin already baked this
        # node's rotation into their abs_x/abs_y), so they draw in flat world space and
        # must NOT be nested inside this node's rotation — nesting would apply that
        # rotation to them a second time. Unrotated nodes skip the wrapper entirely.
        if abs_angle.zero?
          draw_content(renderer)
        else
          renderer.rotated(abs_angle * 180.0 / Math::PI, abs_x, abs_y) { draw_content(renderer) }
        end
        draw_children(renderer)
      end

      def in_tree? = @in_tree

      # Deferred removal (à la Godot's queue_free): mark this node for removal
      # instead of detaching it now. A node that removes itself or a sibling
      # mid-traversal would mutate the parent's @children while it's being iterated;
      # marking instead and sweeping once after the tick (see #sweep_freed, flushed by
      # the platform loop) keeps removal safe and allocation-free.
      def queue_free = @freed = true
      def freed? = @freed

      # Detach every node marked by #queue_free, depth-first, from a point outside the
      # update traversal. Components get a hook too, so a container-style component
      # (e.g. SceneStack) can flush the subtree it owns off the normal child list.
      def sweep_freed
        @components.each(&:sweep_freed)
        i = 0
        while i < @children.size
          child = @children[i]
          if child.freed?
            remove_node(child) # detaches + exit_tree; @children shrinks, so don't advance i
          else
            child.sweep_freed
            i += 1
          end
        end
      end

      # Entered-tree cascade: anchors (root/scene) and sibling systems are now
      # reachable, so components attach (register with systems) before this node's
      # own on_add, and the whole subtree enters depth-first. The engine fires this
      # — the user never calls it — so registration can't be forgotten. Idempotent.
      def enter_tree
        return if @in_tree

        @in_tree = true
        @freed = false # revive: a pooled node reacquired after death re-enters here
        @components.each(&:on_attach)
        on_add
        @children.each(&:enter_tree)
      end

      # Leaving-tree cascade: mirror of #enter_tree (children first, then this
      # node's on_remove, then component on_detach to release registrations).
      def exit_tree
        return unless @in_tree

        @children.each(&:exit_tree)
        on_remove
        @components.each(&:on_detach)
        @in_tree = false
      end

      # Lifecycle hooks: Subclasses should implement these instead of
      # overwriting the public interface draw/update/add etc. on_add/on_remove
      # fire when the node enters/leaves the live tree (see #enter_tree), not at
      # construction — so anchors and systems are available inside them.

      def on_control(actions); end
      def on_update(dt); end
      def on_draw(renderer); end
      def on_add; end
      def on_remove; end

      private

      # This node's own drawing: its components and its draw hook, in that order.
      # Wrapped in renderer.rotated by #draw when the node carries an absolute angle.
      def draw_content(renderer)
        @components.each { it.draw(renderer) }
        on_draw(renderer)
      end

      # Draw the child subtrees. Its own method so a node can wrap the whole subtree's
      # draw in a transform — e.g. CameraView wraps it in renderer.translated to apply a
      # camera offset, without each child knowing about the camera.
      def draw_children(renderer)
        @children.each { it.draw(renderer) }
      end

      # TODO: Calculate (and cache?) depth
      # depth = z + highest z of children, maybe +1?

      # Resolve this node's absolute transform from the parent origin passed down by the
      # traversal. Relative x/y/z/angle accumulate, so a nested Node offsets, re-layers
      # and rotates its whole subtree: a child's local (x, y) is rotated by the parent's
      # accumulated angle before being added to the parent's origin.
      # TODO: Do not recalculate every time, but use a @dirty flag
      # TODO: Handle z better - offset not by Z of the parent, but their
      #       depth
      def resolve_origin
        if @parent.nil?
          @abs_x = @abs_y = @abs_z = 0
          @abs_angle = 0 # root pinned to identity, like its position
          return
        end

        pa = @parent.abs_angle
        if pa.zero? # fast path: parent unrotated -> plain translation, no trig
          @abs_x = @parent.abs_x + @x
          @abs_y = @parent.abs_y + @y
        else
          cos = Math.cos(pa)
          sin = Math.sin(pa)
          @abs_x = @parent.abs_x + (@x * cos) - (@y * sin)
          @abs_y = @parent.abs_y + (@x * sin) + (@y * cos)
        end
        @abs_z     = @parent.abs_z + @z
        @abs_angle = pa + @angle
      end
    end
  end
end
