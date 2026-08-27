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
      # ancestry. Read-only: a node is moved by setting `x`/`y`/`angle`, which is
      # the space it actually lives in.
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
      # what a game's own code calls its hero node (`examples/15_tiled_world`
      # does), so an `attr_accessor :player` here would quietly claim that ivar
      # out from under every scene that has one — which it did, and the symptom
      # was the input system being handed a Node2D. `controller` is taken too:
      # Actor#controller is the thing that produces movement intent, a different
      # idea entirely. This name says exactly what it decides and collides with
      # neither.
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
        # A fresh node has never resolved its world transform, so the first read
        # of one computes it — including on a node built but never ticked, which
        # is why these seeds are a floor rather than an answer. They exist so
        # that nothing reads nil if a future path ever bypasses the readers.
        @world_current = false
        @world_x = @world_y = @world_angle = 0
        @abs_input_owner = @input_owner
        @abs_band = @band || Util::Z::DEFAULT
        @children = []
        # Siblings are drawn in `z` order, and in insertion order within one
        # `z`. Ruby's sort is not stable, so insertion order is carried as a
        # number rather than relied on — the same reason the C draw queue
        # compares (z, order) instead of trusting qsort.
        @child_seq = 0
        @children_sorted = true
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
        node.sibling_order = (@child_seq += 1)
        @children_sorted = false
        # Defer the entered-tree cascade until this node is itself live; otherwise it
        # fires when an ancestor enters (see #enter_tree). This is the construct-vs-enter
        # split — a node built inside another node's initialize is not yet in the tree.
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
      # hook), then descends into children. Nothing about a node's position
      # depends on that order — a world position is computed when it is read —
      # but it is what lets a hook decide something the subtree then acts on in
      # the same tick.

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

        # Only the inherited attributes: `control` reads no coordinates. There is
        # no pointer in this engine by design (see RGame::Core::Input), so
        # `on_control(actions)` is handed input and nothing spatial at all.
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

        # Nothing is resolved here at all. The world transform is computed on
        # demand by whoever reads it (see #world_x), and the inherited attributes
        # are read by `control` and `draw` rather than by anything on this path.
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
        # Only the inherited attributes: `renderer.layered` below needs the band.
        #
        # Nothing here resolves a coordinate. Drawing expresses position by
        # pushing this node's transform rather than by reading a resolved one,
        # and culling — which *is* world-space, since a view is a camera
        # rectangle in the world — asks `node.world_x`, which computes itself if
        # it has to. That is what lets a paused node under a moving ancestor cull
        # correctly despite never running `update`; see
        # spec/rgame/engine/node2d_paused_spec.rb.
        resolve_inherited
        # Everything this node and its subtree draws happens in the node's own
        # local space: (0, 0) is the node, +x is its right. `in_local_space`
        # pushes the transform that makes that true, the renderer composes it
        # with every ancestor's, and the node never sees a world coordinate.
        in_local_space(renderer) do
          # This node's own drawing goes in its own layer: the renderer hands out
          # the next slot in the node's band, and every `z:` the node passes is an
          # offset inside it. Because the traversal takes slots in the order it
          # reaches nodes, draw order *is* tree order — and because a slot is
          # narrow, nothing a node draws can reach past itself. The node never
          # asks for this and cannot forget it; see RGame::Util::Z.
          renderer.layered(@abs_band) { draw_content(renderer, view) }
          # Outside that block: a child takes a slot of its own, after this one.
          # Inside this one: a child's coordinates are relative to this node, so
          # its whole subtree must draw under this node's transform.
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

      # Lifecycle hooks: Subclasses should implement these instead of
      # overwriting the public interface draw/update/add etc. on_add/on_remove
      # fire when the node enters/leaves the live tree (see #enter_tree), not at
      # construction — so anchors and systems are available inside them.

      def on_control(actions); end
      def on_update(dt); end
      def on_draw(renderer, view); end
      def on_add; end
      def on_remove; end

      private

      # Push this node's transform, so everything drawn inside the block is placed
      # and oriented relative to the node rather than to the window.
      #
      # The transform pushed is the node's **parent-relative** one, because the
      # renderer is already inside every ancestor's — composing them is the
      # renderer's job and this is the same mechanism WorldView uses for the
      # camera, one level further down. Translate first, then rotate about the
      # node's own origin: that composes to `parent_origin + R(parent) * local`,
      # which is the same thing #resolve_transform computes arithmetically for
      # anything that asks where the node is in the world.
      #
      # A root pushes nothing, matching #resolve_transform pinning a parentless
      # node to the identity regardless of its own x/y/angle.
      #
      # An identity transform is skipped here rather than left to the renderer,
      # which short-circuits it too. Most nodes are organizational and sit at
      # their parent's origin, so the common case costs one comparison and no
      # block at all — and the call sequence a node issues is then unchanged from
      # before this was a transform push, which is what lets the recording fakes
      # keep their expectations.
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

      # This node's own drawing: its components and its draw hook, in that order.
      # Both draw in the node's local space — see #in_local_space.
      # hot-path
      def draw_content(renderer, view)
        @components.each { it.draw(renderer, view) }
        on_draw(renderer, view)
      end

      # Draw the child subtrees. Its own method so a node can wrap the whole subtree's
      # draw in a transform without each child knowing about it.
      # hot-path
      def draw_children(renderer, view)
        children_in_order.each { it.draw(renderer, view) }
      end

      # The children, in the order every phase visits them: by `z`, then by when
      # they were added. Sorted lazily — a scene that never touches `z` after
      # building sorts once and then pays one boolean per phase.
      # hot-path
      def children_in_order
        sort_children unless @children_sorted
        @children
      end

      # Ruby's sort is not stable, so the insertion counter is compared
      # explicitly. Without it two same-z siblings would swap places between
      # frames, which reads on screen as flicker rather than as a sort problem.
      def sort_children
        @children_sorted = true
        # Nothing to order, and the overwhelmingly common case for a leaf or a
        # node with one visual — worth skipping before touching the array.
        return if @children.size < 2

        @children.sort! do |a, b|
          order = a.z <=> b.z
          order.zero? ? a.sibling_order <=> b.sibling_order : order
        end
      end

      # Resolve this node's absolute transform from the parent origin passed down by the
      # traversal. Relative x/y/angle accumulate, so a nested Node offsets and rotates
      # its whole subtree: a child's local (x, y) is rotated by the parent's accumulated
      # angle before being added to the parent's origin.
      #
      # `z` is **not** among them, and that is the point: depth is decided by
      # where the traversal reaches a node, not by summing what its ancestors
      # picked. See #z= and RGame::Util::Z.
      # Where this node is in the world, from where its parent is and where it
      # sits inside its parent. Called by the `world_*` readers when the cached
      # answer is stale, and by nothing else — reading the parent's `world_x`
      # (the reader, not the ivar) is what walks up to the nearest ancestor still
      # current and recomputes back down from there.
      # hot-path
      def resolve_transform
        @world_current = true
        if @parent.nil?
          @world_x = @world_y = 0
          @world_angle = 0 # root pinned to identity, like its position
          return
        end

        pa = @parent.world_angle
        if pa.zero? # fast path: parent unrotated -> plain translation, no trig
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

      protected

      # Mark this node's world transform stale, and every descendant's with it —
      # they are all somewhere else now. Nothing is recomputed here; the next
      # read of each one pays for that one, and a node nobody asks about pays
      # nothing at all.
      #
      # A subtree that is already stale is left alone, which is what keeps a
      # burst of writes cheap: `node.x += dx` followed by `node.y += dy` walks
      # the subtree once, and the second call stops at this node. That is sound
      # because staleness always covers a whole subtree — the only thing that
      # clears it is a read, and a read of a node clears that node and its
      # ancestors, never a descendant.
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

      # The half of the resolution that is *not* the transform: which player owns
      # this node, and which band it draws in. Both are inherited from the
      # nearest ancestor that declares one, so they have to be walked down the
      # tree even though neither is a coordinate.
      #
      # Its own method because `control` and `draw` need exactly this and nothing
      # more — control reads no coordinates, and draw expresses position by
      # pushing a transform rather than by resolving one. Only `update` still
      # pays for the trig.
      # hot-path
      def resolve_inherited
        if @parent.nil?
          @abs_input_owner = @input_owner
          @abs_band = @band || Util::Z::DEFAULT
          return
        end

        # Ownership accumulates the same way the transform does: this node's own
        # if it has one, otherwise whatever it inherits. Resolved rather than
        # walked on demand so it costs one assignment per phase, and so it is
        # equally available in update and draw — a HUD node drawing in its
        # player's corner wants the same answer `control` used.
        @abs_input_owner = @input_owner || @parent.abs_input_owner
        # The band inherits the same way. A node that declares one overrides it
        # for its whole subtree, which is the only way out of a band and is
        # spelled with a name rather than a number.
        @abs_band = @band || @parent.abs_band
      end
    end
  end
end
