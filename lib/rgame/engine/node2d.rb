# frozen_string_literal: true

module RGame
  module Engine
    # A node in a scene graph. We currently have only 2D nodes, but the
    # name reflects this should there ever be a 3D space. Nodes are
    # containers for both containers and nodes. They extend the signal
    # DSL to allow for easy signal usage.
    class Node2D
      extend Engine::Signal::DSL

      # This node's transform **in its parent's space** — where it sits inside
      # whatever contains it, and the only position a node ever sets. `x`, `y`
      # and `angle` are the short spelling of the same three, because that is
      # what reads well where a node moves itself:
      #
      #   def on_update(dt) = self.x += @speed * dt
      #
      # Not for drawing, though it is tempting: `on_draw` runs with the renderer
      # already on this node (see #in_local_space), so drawing at `x` offsets by
      # this node's own position a second time. `Game/DrawInLocalSpace` says so.
      #
      # The ivar carries the longer name so that `@x` does not exist. Reaching
      # for a parent-relative coordinate where a world one was meant is the
      # mistake this whole design is arranged against, and the spelling that used
      # to make it silent is simply not there any more.
      attr_reader :rel_x, :rel_y, :rel_angle
      alias x rel_x
      alias y rel_y
      alias angle rel_angle

      attr_accessor :width, :height
      attr_writer :scene, :context

      # The other way a node moves, and the only one that does not go through a
      # coordinate writer: its `x`/`y` do not change, but they are now an offset
      # from somewhere else. Set by #add_node and #remove_node — a game does not
      # call this — and it invalidates the subtree for the same reason a move
      # does.
      def parent=(value)
        @parent = value
        soil
      end

      # Moving a node invalidates the world transform of the node *and its whole
      # subtree* — every one of them is now somewhere else — but computes none of
      # them. Whoever reads one next pays for that one.
      #
      # `node.x += dx` from a component (Components::Velocity does exactly that)
      # is two writes and so two invalidations, which is why #soil returns
      # immediately on a subtree that is already stale.
      def rel_x=(value)
        @rel_x = value
        soil
      end

      def rel_y=(value)
        @rel_y = value
        soil
      end

      def rel_angle=(value)
        @rel_angle = value
        soil
      end

      alias x= rel_x=
      alias y= rel_y=
      alias angle= rel_angle=

      # Insertion order among siblings, the tie-breaker for equal `z`. Engine
      # bookkeeping, set by the parent's #add_node the way `parent` is — not for
      # game code, and meaningless on a node with no parent.
      attr_accessor :sibling_order

      # This node's transform **in world space**, accumulated from its whole
      # ancestry. A node lives in its parent's space and is moved by setting
      # `x`/`y`/`angle`; `world_x=`/`world_y=` below are that same move, worked
      # out from a world position for the code that thinks in one.
      #
      # `world_` rather than `abs_`, because the name should say which space the
      # value is in. `abs_band` and `abs_input_owner` keep theirs deliberately —
      # those are *inherited* from the nearest ancestor that declares one rather
      # than expressed in a space, and a band is not in world coordinates.
      #
      # **Computed on demand and cached**, which is how Godot and Unity do it and
      # why no phase resolves this any more. Moving a node marks it and its whole
      # subtree stale (see #soil); the next read walks up to the nearest node
      # still current, recomputing on the way back down. Two consequences worth
      # knowing:
      #
      # - It is never stale. There is no "resolved at the top of the phase" value
      #   to go out of date, so a node that moved, a node whose *ancestor* moved,
      #   and a paused node under a moving ancestor all answer correctly, at any
      #   point in any phase.
      # - Nothing is computed for a node nobody asks about. A still frame costs
      #   nothing at all, where resolving the tree eagerly cost a full pass per
      #   phase whether or not anything had moved.
      # hot-path
      def world_x
        resolve_transform unless @world_current
        @world_x
      end

      # hot-path
      def world_y
        resolve_transform unless @world_current
        @world_y
      end

      # Place the node at a world coordinate, leaving the other one where it is.
      #
      # For code that decides where a node goes in world space — the edge of the
      # world, a resolved collision — and must still write the node's own, local
      # position. The target is turned back into the parent's frame, so the
      # answer is exact under a rotated ancestor too: there it moves the local
      # position along *both* axes, which is what one world axis looks like from
      # inside a turned frame.
      #
      # A node with no parent is pinned to the origin (see #resolve_transform),
      # so there is no local position that would put it anywhere else, and this
      # changes nothing.
      # hot-path
      def world_x=(value)
        return if @parent.nil?

        pa = @parent.world_angle
        if pa.zero?
          self.rel_x = value - @parent.world_x
        else
          place_in_rotated_parent(value - @parent.world_x, world_y - @parent.world_y, pa)
        end
      end

      # hot-path
      def world_y=(value)
        return if @parent.nil?

        pa = @parent.world_angle
        if pa.zero?
          self.rel_y = value - @parent.world_y
        else
          place_in_rotated_parent(world_x - @parent.world_x, value - @parent.world_y, pa)
        end
      end

      # hot-path
      def world_angle
        resolve_transform unless @world_current
        @world_angle
      end

      attr_reader :children, :components, :parent, :abs_input_owner, :z, :band, :abs_band

      # Where this node sits among its **siblings**, and nowhere else.
      #
      # The tree is drawn depth-first with siblings in `z` order, so a node's
      # whole subtree is drawn before or after a sibling's whole subtree —
      # never interleaved with it. Clouds over birds over people is three
      # children of one node at `z` 2, 1 and 0, and each of them may be built
      # out of as many parts as it likes without any of those parts escaping.
      #
      # Only the *comparison* matters. `z` is never added to anything and never
      # reaches the renderer, so its magnitude means nothing: 1 and 1_000_000
      # behave identically if they are the only two children, and a negative is
      # ordinary. Equal `z` keeps the order the nodes were added in.
      #
      # This is deliberately unlike the additive relative z it replaces
      # (`abs_z = parent.abs_z + z`), where a node at z 2 with a child at z 5
      # resolved to 7 and overtook a sibling at 4 — some of a node's parts in
      # front of something the node itself was behind. See RGame::Util::Z.
      def z=(value)
        @z = value
        @parent&.children_unsorted!
      end

      # Which band this node and everything under it draws in — `:world` (the
      # default), `:hud`, `:overlay` or `:debug`. A band beats every `z` in the
      # tree: nothing in `:world` can draw over anything in `:hud`.
      #
      # Inherited like `input_owner`, and normally set by a node that exists to
      # mark one: WorldView is `:world`, PlayerLayer is `:hud`. Setting it
      # directly is the escape hatch — a node inside the world that must draw
      # over the HUD says `band: :overlay` and does, still clipped to whatever
      # its ancestors allowed. That is explicit and named, which is the whole
      # difference from the Integer bases this replaces.
      def band=(value)
        Util::Z.band!(value) unless value.nil?
        @band = value
      end

      # Whose input drives this node: an RGame::Engine::Player, or nil.
      #
      # Inherited down the tree exactly like the transform. Set it on a node and
      # its whole subtree reads that player, so `ship.input_owner = players[1]`
      # is all it takes for everything under the ship to answer to player two. A
      # node that sets none inherits its parent's, and a tree that sets none
      # anywhere reads the primary player — which is why single player needs no
      # mention of this at all.
      #
      # **Not `player`**, deliberately, and not `controller` either. `@player` is
      # what a game's own code naturally calls its hero node, so an
      # `attr_accessor :player` here would quietly claim that ivar out from
      # under every scene that has one — which it did, and the symptom
      # was the input system being handed a Node2D. `controller` is taken too:
      # a controller is the component that produces movement intent — see
      # Components::PlayerController — which is a different idea entirely. This
      # name says exactly what it decides and collides with neither.
      attr_accessor :input_owner

      # A paused node skips `control` and `update` — and so does everything
      # under it, because a subtree is only ever reached through its parent.
      # It still **draws**: pausing is about time, not visibility, which is what
      # lets a frozen world sit under a cutscene overlay that keeps animating.
      #
      #   world_view.paused = true    # the world stops; the overlay above it does not
      #
      # There is no `abs_paused` to go with `abs_input_owner`. Ownership has to
      # be resolved because a node needs to know whose input it reads even when
      # its parent claims nobody; pausing needs no resolution at all, because a
      # paused node simply never descends.
      attr_accessor :paused

      def initialize(x: 0, y: 0, z: 0, angle: 0, width: 0, height: 0, input_owner: nil,
                     band: nil)
        @input_owner = input_owner
        @paused = false
        @rel_x = x
        @rel_y = y
        @z = z
        self.band = band
        @rel_angle = angle
        @width = width
        @height = height
        @world_current = false
        @world_x = @world_y = @world_angle = 0
        @abs_input_owner = @input_owner
        @abs_band = @band || Util::Z::DEFAULT
        @children = []
        @child_seq = 0
        @children_sorted = true
        @components = []
        @component_slots = {}
        @parent = nil
        @scene = nil
        @in_tree = false
        @freed = false
      end

      def add_node(node)
        @children << node
        node.parent = self
        node.sibling_order = (@child_seq += 1)
        @children_sorted = false
        node.enter_tree if @in_tree
        node
      end

      # A child was added, or one changed its `z`, so the child order is stale.
      # The sort is deferred to the next traversal rather than done here, so
      # building a scene of a thousand nodes costs one sort rather than a
      # thousand. Called by the engine; a game only ever assigns `z`.
      def children_unsorted! = @children_sorted = false

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

      # `input` is an input *source*, not one player's snapshot: an
      # RGame::Engine::Players registry, or a bare Actions when there is only
      # ever one answer (which is what a spec usually passes).
      #
      # Each node asks the source for the actions of whichever player owns it,
      # and hands its components and its own hook that plain Actions. So a
      # component never learns there is more than one player — `control(actions)`
      # means the same thing it always did — while two subtrees under one tick
      # can read two different controllers.
      #
      # The source is what descends, not the resolved snapshot, because
      # ownership can change further down.
      def control(input)
        return if @paused

        resolve_inherited
        actions = input.actions_for(@abs_input_owner)
        @components.each { it.control(actions) }
        on_control(actions)
        children_in_order.each { it.control(input) }
      end

      # update game logic and physics (might become two calls with
      # time, but for now works in one step). This runs second in a
      # game tick
      def update(dt)
        return if @paused

        @components.each { it.update(dt) }
        on_update(dt)
        children_in_order.each { it.update(dt) }
      end

      # update visual game state, drawing the node. This runs last in
      # a game tick
      # `view` is the viewport being drawn into: its rectangle, and the camera
      # (if any) it is seen through. Every node gets it, because a node cannot
      # otherwise know where the edges of its own region are — a HUD laying out
      # against the whole window is wrong the moment the window is one player's
      # half of it — and because culling needs it once the world is drawn more
      # than once. Most nodes ignore it and simply draw.
      def draw(renderer, view)
        resolve_inherited
        in_local_space(renderer) do
          renderer.layered(@abs_band) { draw_content(renderer, view) }
          draw_children(renderer, view)
        end
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
            remove_node(child)
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
        @freed = false
        @components.each(&:on_attach)
        on_add
        children_in_order.each(&:enter_tree)
      end

      # Leaving-tree cascade: mirror of #enter_tree (children first, then this
      # node's on_remove, then component on_detach to release registrations).
      def exit_tree
        return unless @in_tree

        children_in_order.each(&:exit_tree)
        on_remove
        @components.each(&:on_detach)
        @in_tree = false
      end

      def on_control(actions); end
      def on_update(dt); end
      def on_draw(renderer, view); end
      def on_add; end
      def on_remove; end

      private

      # hot-path
      # rubocop:disable Style/ExplicitBlockArgument -- an explicit &block would
      # allocate a Proc for every node, every frame, per viewport. `yield` is
      # what keeps this path allocation-free, which culling_spec asserts.
      def in_local_space(renderer)
        return yield if @parent.nil?
        return yield if @rel_x.zero? && @rel_y.zero? && @rel_angle.zero?

        renderer.translated(@rel_x, @rel_y) do
          if @rel_angle.zero?
            yield
          else
            renderer.rotated(@rel_angle * 180.0 / Math::PI, 0, 0) { yield }
          end
        end
      end
      # rubocop:enable Style/ExplicitBlockArgument

      # hot-path
      def draw_content(renderer, view)
        @components.each { it.draw(renderer, view) }
        on_draw(renderer, view)
      end

      # hot-path
      def draw_children(renderer, view)
        children_in_order.each { it.draw(renderer, view) }
      end

      # hot-path
      def children_in_order
        sort_children unless @children_sorted
        @children
      end

      def sort_children
        @children_sorted = true
        return if @children.size < 2

        @children.sort! do |a, b|
          order = a.z <=> b.z
          order.zero? ? a.sibling_order <=> b.sibling_order : order
        end
      end

      # hot-path
      def resolve_transform
        @world_current = true
        if @parent.nil?
          @world_x = @world_y = 0
          @world_angle = 0
          return
        end

        pa = @parent.world_angle
        if pa.zero?
          @world_x = @parent.world_x + @rel_x
          @world_y = @parent.world_y + @rel_y
        else
          cos = Math.cos(pa)
          sin = Math.sin(pa)
          @world_x = @parent.world_x + (@rel_x * cos) - (@rel_y * sin)
          @world_y = @parent.world_y + (@rel_x * sin) + (@rel_y * cos)
        end
        @world_angle = pa + @rel_angle
      end

      def place_in_rotated_parent(offset_x, offset_y, pa)
        cos = Math.cos(pa)
        sin = Math.sin(pa)
        self.rel_x = (offset_x * cos) + (offset_y * sin)
        self.rel_y = (offset_y * cos) - (offset_x * sin)
      end

      protected

      # hot-path
      def soil
        return unless @world_current

        @world_current = false
        # rubocop:disable Style/SymbolProc -- `&:soil` would call through
        # Symbol#to_proc, which dispatches publicly and so cannot reach a
        # protected method. An explicit receiver is the only form that works
        # here, and it allocates no more than the symbol would.
        @children.each { it.soil }
        # rubocop:enable Style/SymbolProc
      end

      private

      # hot-path
      def resolve_inherited
        if @parent.nil?
          @abs_input_owner = @input_owner
          @abs_band = @band || Util::Z::DEFAULT
          return
        end

        @abs_input_owner = @input_owner || @parent.abs_input_owner
        @abs_band = @band || @parent.abs_band
      end
    end
  end
end
