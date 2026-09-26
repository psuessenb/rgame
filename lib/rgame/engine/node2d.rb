# frozen_string_literal: true

module RGame
  module Engine
    # A node in a scene graph. We currently have only 2D nodes, but the
    # name reflects this should there ever be a 3D space. Nodes are
    # containers for both containers and nodes. They extend the signal
    # DSL to allow for easy signal usage.
    class Node2D
      extend Engine::Signal::DSL
      extend Engine::SealedPrivates
      extend Engine::Hooks

      # This node's transform **in its parent's space** — where it sits inside
      # whatever contains it, and the only position a node ever sets. `x`, `y`
      # and `angle` are the short spelling of the same three, because that is
      # what reads well where a node moves itself:
      #
      #   def _update(dt) = self.x += @speed * dt
      #
      # Not for drawing, though it is tempting: `_draw` runs with the renderer
      # already on this node (see #rgame_in_local_space), so drawing at `x`
      # offsets by this node's own position a second time. `Game/DrawInLocalSpace`
      # says so.
      #
      # `@x` is not the position. The ivar is `@rgame_rel_x`, as every ivar the
      # engine keeps on a node starts with `rgame_`, so a subclass's `@x` is its
      # own.
      sealed_reader :rel_x, :rel_y, :rel_angle
      alias x rel_x
      alias y rel_y
      alias angle rel_angle

      sealed_accessor :width, :height

      # Height above the ground in pixels, for a top-down view: how far this
      # node's picture is drawn above the spot it stands on. Positive is up.
      #
      # It is **not** part of the transform. `y`, `world_y`, colliders, cameras
      # and children all ignore it, which is what lets a character leave the
      # ground without its feet box leaving too. Components::Sprite and
      # Components::AnimatedSprite draw lifted by it, in the node's local space;
      # Components::Hop is one thing that writes it.
      sealed_accessor :elevation
      sealed_writer :scene, :context

      # The other way a node moves, and the only one that does not go through a
      # coordinate writer: its `x`/`y` do not change, but they are now an offset
      # from somewhere else. Set by #add_node and #remove_node — a game does not
      # call this — and it invalidates the subtree for the same reason a move
      # does.
      #
      # It is also how a node joins the ones its parent invalidates when it
      # moves. A container that holds nodes off its child list, as
      # Scene::SceneStack holds its scenes, sets `parent` and needs nothing
      # more: a move of the container reaches every node that names it as
      # parent, child or not. A node keeps that list from the first node that
      # names it, so a leaf a game spawns allocates nothing for it.
      def parent=(value)
        @rgame_parent&.rgame_unplace(self)
        @rgame_parent = value
        value&.rgame_place(self)
        rgame_soil
      end

      # Moving a node invalidates the world transform of the node *and its whole
      # subtree* — every one of them is now somewhere else — but computes none of
      # them. Whoever reads one next pays for that one.
      #
      # `node.x += dx` from a component (Components::Velocity does exactly that)
      # is two writes and so two invalidations, which is why #rgame_soil returns
      # immediately on a subtree that is already stale.
      def rel_x=(value)
        @rgame_rel_x = value
        rgame_soil
      end

      def rel_y=(value)
        @rgame_rel_y = value
        rgame_soil
      end

      def rel_angle=(value)
        @rgame_rel_angle = value
        rgame_soil
      end

      alias x= rel_x=
      alias y= rel_y=
      alias angle= rel_angle=

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
      # subtree stale (see #rgame_soil); the next read walks up to the nearest node
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
        rgame_resolve_transform unless @rgame_world_current
        @rgame_world_x
      end

      # hot-path
      def world_y
        rgame_resolve_transform unless @rgame_world_current
        @rgame_world_y
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
      # A node with no parent is pinned to the origin (see #rgame_resolve_transform),
      # so there is no local position that would put it anywhere else, and this
      # changes nothing.
      # hot-path
      def world_x=(value)
        return if @rgame_parent.nil?

        pa = @rgame_parent.world_angle
        if pa.zero?
          self.rel_x = value - @rgame_parent.world_x
        else
          rgame_place_in_rotated_parent(value - @rgame_parent.world_x, world_y - @rgame_parent.world_y, pa)
        end
      end

      # hot-path
      def world_y=(value)
        return if @rgame_parent.nil?

        pa = @rgame_parent.world_angle
        if pa.zero?
          self.rel_y = value - @rgame_parent.world_y
        else
          rgame_place_in_rotated_parent(world_x - @rgame_parent.world_x, value - @rgame_parent.world_y, pa)
        end
      end

      # hot-path
      def world_angle
        rgame_resolve_transform unless @rgame_world_current
        @rgame_world_angle
      end

      sealed_reader :children, :components, :parent, :abs_input_owner, :z, :band, :abs_band

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
        @rgame_z = value
        @rgame_parent&.rgame_children_unsorted!
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
        @rgame_band = value
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
      # Not `player`: a game's scene usually has a `player` of its own, its hero
      # node. Not `controller` either: a controller is the component that
      # produces movement intent, see Components::PlayerController.
      sealed_accessor :input_owner

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
      #
      # `paused` is the game's own switch. The engine stops a node with
      # `suspend` instead, so neither undoes the other.
      sealed_reader :paused

      def paused=(value)
        @rgame_paused = value
        @rgame_stopped = value || @rgame_suspensions.positive?
      end

      # Stops the node as `paused` does, until a `resume` for each `suspend`.
      # The calls count, so two owners can each stop the same node and give it
      # back in any order, and the game's own `paused` is left alone. A door's
      # move and a cutscene stop a node this way. Returns self.
      #
      #   hero.suspend    # a cutscene starts
      #   hero.suspend    # a door moves the hero under it
      #   hero.resume     # the cutscene ends; the move still holds the hero
      #   hero.resume     # the move's reveal ends, and the hero walks
      def suspend
        @rgame_suspensions += 1
        @rgame_stopped = true
        self
      end

      # Ends one `suspend`. Raises `RuntimeError` when none is left to end.
      # Returns self.
      def resume
        raise 'resume called with no suspend to end' if @rgame_suspensions.zero?

        @rgame_suspensions -= 1
        @rgame_stopped = @rgame_paused || @rgame_suspensions.positive?
        self
      end

      # Whether a `suspend` holds the node.
      def suspended? = @rgame_suspensions.positive?

      # How much of this node and everything under it shows: from 0, which
      # draws none of it, to 1, the default, which changes nothing.
      #
      #   node.opacity = 0.5   # the node, its components and its children, at half their alpha
      #
      # `draw` applies it around the node's own drawing and its children's, as
      # it applies the node's transform, so a `_draw` cannot miss it and a child
      # cannot escape it. A child's own opacity multiplies with it: 0.5 under
      # 0.5 draws at a quarter. Each node's reader answers only what was set on
      # it.
      #
      # Only drawing changes. A node at 0 still takes part in `control` and
      # `update`, and its colliders still collide.
      sealed_reader :opacity

      # Refuses what `renderer.faded` refuses, here rather than at the next
      # draw: a number outside 0..1, or anything that is not a number.
      def opacity=(value)
        @rgame_opacity = Util::Blend.opacity(value)
      end

      # How large this node and everything under it draws, about its origin: 0
      # draws none of it, and 1, the default, changes nothing.
      #
      #   node.scale = 0.5   # the node, its components and its children, at half size
      #
      # `draw` applies it around the node's own drawing and its children's, as
      # it applies `opacity`, so a `_draw` cannot miss it and a child cannot
      # escape it. A child's own scale multiplies with it. A character stands on
      # its origin, so it shrinks toward its feet.
      #
      # Only drawing changes. Positions, colliders and the transform keep their
      # size, so `world_x` of a child is where it stands, not where it draws.
      sealed_reader :scale

      # Refuses a negative number, NaN or infinity with ArgumentError, and
      # anything that is not a number with TypeError, here rather than at the
      # next draw.
      def scale=(value)
        raise TypeError, "no implicit conversion of #{value.class} into Float" unless value.is_a?(Numeric)
        raise ArgumentError, "scale #{value} is not a finite number of 0 or more" unless value >= 0 && value.finite?

        @rgame_scale = value
      end

      # Whether this node draws its children by where they stand: by `z` first,
      # then the child standing further down the screen later, then in the order
      # they were added. Off by default. TileMapLayer.mount turns it on for the
      # slots it leaves between tile layers, which is where a top-down game's
      # actors live.
      #
      #   actors = Node2D.new(y_sort: true)   # whoever is lower on screen draws in front
      #
      # A child stands at the bottom edge of its Components::BoxCollider box, a
      # feet box included, or at its `y` if it has none. `elevation` plays no
      # part, so a character mid-hop sorts by the spot they left. A child's
      # subtree sorts as one unit with it.
      #
      # **Only drawing follows it.** `control` and `update` visit the children in
      # the order they would without it, so an actor walking north never changes
      # who moves first, and a run does not depend on how often it was drawn.
      sealed_reader :y_sort

      def y_sort=(value)
        @rgame_y_sort = value
        @rgame_draw_order = value ? @rgame_children.dup : nil
      end

      # The id of the map object a map built this node from, or `nil` for a
      # node built in code. An id is unique within its map. It is all a node
      # keeps of its object: Components::Facts keys the node's record by it.
      sealed_reader :map_object_id

      def initialize(x: 0, y: 0, z: 0, angle: 0, width: 0, height: 0, input_owner: nil,
                     band: nil, y_sort: false, map_object_id: nil)
        @rgame_map_object_id = map_object_id
        @rgame_input_owner = input_owner
        @rgame_paused = false
        @rgame_suspensions = 0
        @rgame_stopped = false
        @rgame_opacity = 1
        @rgame_scale = 1
        @rgame_rel_x = x
        @rgame_rel_y = y
        @rgame_z = z
        self.band = band
        @rgame_rel_angle = angle
        @rgame_width = width
        @rgame_height = height
        @rgame_elevation = 0
        @rgame_world_current = false
        @rgame_world_x = @rgame_world_y = @rgame_world_angle = 0
        @rgame_abs_input_owner = @rgame_input_owner
        @rgame_abs_band = @rgame_band || Util::Z::DEFAULT
        @rgame_children = []
        @rgame_placed = nil
        @rgame_child_seq = 0
        @rgame_children_sorted = true
        @rgame_components = []
        @rgame_component_slots = {}
        @rgame_parent = nil
        @rgame_scene = nil
        @rgame_in_tree = false
        @rgame_freed = false
        @rgame_press_gate = nil
        @rgame_sort_box = nil
        @rgame_sort_box_known = false
        self.y_sort = y_sort
      end

      # Adds `node` as the last child, and answers it. A node that already has
      # a parent leaves it first, so it is never in two child lists. A node
      # that is already this node's child stays where it is: nothing leaves the
      # tree, and its components keep their systems.
      def add_node(node)
        if (old = node.parent)
          return node if old.equal?(self) && @rgame_children.include?(node)

          old.remove_node(node)
        end
        @rgame_children_sorted = false unless rgame_sorts_last?(node)
        @rgame_children << node
        @rgame_draw_order&.push(node)
        node.parent = self
        node.rgame_sibling_order = (@rgame_child_seq += 1)
        node.enter_tree if @rgame_in_tree
        node
      end

      def remove_node(node)
        node.exit_tree if @rgame_in_tree
        @rgame_children.delete(node)
        @rgame_draw_order&.delete(node)
        node.parent = nil
        node
      end

      # Look a component up by its slot. A Class/Module is matched by ancestry across every
      # component (so a base class finds a subclass instance); a Symbol names a specific slot
      # (see #add_component's `as:`). A class lookup raises when it's ambiguous — two
      # components share that type — so the caller reaches for the name instead. The scan is
      # allocation-free, so it's safe to call on the per-frame path.
      def get_component(key)
        return @rgame_component_slots[key] unless key.is_a?(Module)

        found = nil
        @rgame_components.each do |component|
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
        raise ArgumentError, "Node already has a component in slot #{slot.inspect}" if @rgame_component_slots.key?(slot)

        @rgame_components << component
        @rgame_component_slots[slot] = component
        component.node = self
        @rgame_sort_box_known = false
        component._attach if @rgame_in_tree
        component
      end

      def remove_component(key)
        component = get_component(key)
        return nil unless component

        component._detach if @rgame_in_tree
        @rgame_components.delete(component)
        @rgame_component_slots.delete(@rgame_component_slots.key(component))
        component.node = nil
        @rgame_sort_box_known = false
        component
      end

      # The top-most node — a node with no parent is its own root. Global,
      # program-lifetime systems live here as components.
      def root
        @rgame_parent ? @rgame_parent.root : self
      end

      # The nearest enclosing scene node, marked as a boundary by SceneStack
      # (#scene= self). Scene-lifetime systems live on it as components.
      def scene
        @rgame_scene || @rgame_parent&.scene
      end

      def context
        @rgame_context ||= root.context
      end

      # The nearest system of a class: this node's scene first, then each scene
      # that encloses it, then the root. A room held inside a world scene finds
      # its own `CollisionWorld`, and the world's `Scene::Rooms` beyond it.
      # hot-path
      def system(klass)
        around = scene
        while around
          found = around.get_component(klass)
          return found if found

          around = around.parent&.scene
        end
        root.get_component(klass)
      end

      # The same lookup, for a caller that cannot work without the system: it
      # raises `KeyError` naming the class and where it looked, rather than
      # returning nil for the next call to fail on.
      def system!(klass)
        system(klass) || raise(KeyError, rgame_missing_system(klass))
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
      #
      # **A node reads only the presses it saw start.** Its components and
      # `_control` read through a gate of the node's own, where `pressed?` and
      # `released?` are false for a press that began before the node resumed.
      # A node resumes on the first poll it is controlled after one it was not:
      # its first control, and its first after a pause, after a scene above it
      # was popped, or after its page was hidden. It also resumes when its
      # `input_owner` changes. So an E tapped in a bag and released after it
      # closes opens no chest. `held?`, `axis` and `held_for` pass through, and
      # a snapshot built by hand, which has no `poll_count`, is handed on as it
      # is.
      def control(input)
        return if @rgame_stopped

        rgame_resolve_inherited
        actions = rgame_gate(input.actions_for(@rgame_abs_input_owner))
        @rgame_components.each { it._control(actions) }
        _control(actions)
        rgame_children_in_order.each { it.control(input) }
      end

      # update game logic and physics (might become two calls with
      # time, but for now works in one step). This runs second in a
      # game tick
      def update(dt)
        return if @rgame_stopped

        @rgame_components.each { it._update(dt) }
        _update(dt)
        rgame_children_in_order.each { it.update(dt) }
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
        return if @rgame_opacity.zero? || @rgame_scale.zero?

        rgame_resolve_inherited
        rgame_in_local_space(renderer) do
          rgame_as_shown(renderer) do
            renderer.layered(@rgame_abs_band) { rgame_draw_content(renderer, view) }
            draw_children(renderer, view)
          end
        end
      end

      def in_tree? = @rgame_in_tree

      # Deferred removal (à la Godot's queue_free): mark this node for removal
      # instead of detaching it now. A node that removes itself or a sibling
      # mid-traversal would change the parent's child list while it's being iterated;
      # marking instead and sweeping once after the tick (see #sweep_freed, flushed by
      # the platform loop) keeps removal safe and allocation-free.
      def queue_free = @rgame_freed = true
      def freed? = @rgame_freed

      # Detach every node marked by #queue_free, depth-first, from a point outside the
      # update traversal. Components get a hook too, so a container-style component
      # (e.g. SceneStack) can flush the subtree it owns off the normal child list.
      def sweep_freed
        @rgame_components.each(&:_sweep_freed)
        i = 0
        while i < @rgame_children.size
          child = @rgame_children[i]
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
      # own _enter_tree, and the whole subtree enters depth-first. The engine fires this
      # — the user never calls it — so registration can't be forgotten. Idempotent.
      #
      # A node whose parent is outside the tree stays out, and enters when the
      # parent does. The cascade reaches every node that names this one as
      # `parent`, so a node a container holds off its child list, as
      # Scene::SceneStack holds its scenes, enters and leaves with the
      # container.
      def enter_tree
        return if @rgame_in_tree || (@rgame_parent && !@rgame_parent.in_tree?)

        @rgame_in_tree = true
        @rgame_freed = false
        @rgame_components.each(&:_attach)
        _enter_tree
        rgame_children_in_order.each(&:enter_tree)
        @rgame_placed&.each(&:enter_tree)
      end

      # Leaving-tree cascade: mirror of #enter_tree (children first, then this
      # node's _exit_tree, then component _detach to release registrations).
      def exit_tree
        return unless @rgame_in_tree

        rgame_children_in_order.each(&:exit_tree)
        @rgame_placed&.each(&:exit_tree)
        _exit_tree
        @rgame_components.each(&:_detach)
        @rgame_in_tree = false
      end

      # The hooks a subclass overrides, each empty here and named after the step
      # that calls it: `control`, `update` and `draw` call the first three after
      # the node's components, and `enter_tree` and `exit_tree` the other two.
      # The leading `_` marks a method the engine calls and a game does not; `on_`
      # is kept for signals.
      def _control(actions); end
      def _update(dt); end
      def _draw(renderer, view); end
      def _enter_tree; end
      def _exit_tree; end

      private

      # hot-path
      # rubocop:disable Style/ExplicitBlockArgument -- an explicit &block would
      # allocate a Proc for every node, every frame, per viewport. `yield` is
      # what keeps this path allocation-free, which culling_spec asserts.
      def rgame_in_local_space(renderer)
        return yield if @rgame_parent.nil?
        return yield if @rgame_rel_x.zero? && @rgame_rel_y.zero? && @rgame_rel_angle.zero?

        renderer.translated(@rgame_rel_x, @rgame_rel_y) do
          if @rgame_rel_angle.zero?
            yield
          else
            renderer.rotated(@rgame_rel_angle * 180.0 / Math::PI, 0, 0) { yield }
          end
        end
      end
      # rubocop:enable Style/ExplicitBlockArgument

      # hot-path
      # rubocop:disable Style/ExplicitBlockArgument -- as in rgame_in_local_space,
      # `yield` from the nested block allocates nothing where a captured &block would.
      def rgame_as_shown(renderer)
        if @rgame_scale == 1
          return yield if @rgame_opacity == 1

          renderer.faded(@rgame_opacity) { yield }
        elsif @rgame_opacity == 1
          renderer.scaled(@rgame_scale) { yield }
        else
          renderer.scaled(@rgame_scale) { renderer.faded(@rgame_opacity) { yield } }
        end
      end
      # rubocop:enable Style/ExplicitBlockArgument

      # hot-path
      def rgame_draw_content(renderer, view)
        @rgame_components.each { it._draw(renderer, view) }
        _draw(renderer, view)
      end

      # hot-path
      def draw_children(renderer, view)
        rgame_children_in_draw_order.each { it.draw(renderer, view) }
      end

      # hot-path
      def rgame_children_in_draw_order
        return rgame_children_in_order unless @rgame_draw_order

        rgame_sort_by_y(@rgame_draw_order)
        @rgame_draw_order
      end

      # hot-path
      def rgame_sort_by_y(order)
        i = 1
        while i < order.size
          node = order[i]
          j = i
          while j.positive? && rgame_draws_after?(order[j - 1], node)
            order[j] = order[j - 1]
            j -= 1
          end
          order[j] = node
          i += 1
        end
      end

      # hot-path
      def rgame_draws_after?(one, other)
        return one.z > other.z unless one.z == other.z

        one_y = one.rgame_sort_y
        other_y = other.rgame_sort_y
        return one_y > other_y unless one_y == other_y

        one.rgame_sibling_order > other.rgame_sibling_order
      end

      def rgame_find_sort_box
        @rgame_sort_box_known = true
        @rgame_sort_box = get_component(Components::BoxCollider)
      end

      # hot-path
      def rgame_children_in_order
        rgame_sort_children unless @rgame_children_sorted
        @rgame_children
      end

      def rgame_sorts_last?(node) = @rgame_children.empty? || @rgame_children.last.z <= node.z

      def rgame_sort_children
        @rgame_children_sorted = true
        return if @rgame_children.size < 2

        @rgame_children.sort! do |a, b|
          order = a.z <=> b.z
          order.zero? ? a.rgame_sibling_order <=> b.rgame_sibling_order : order
        end
      end

      # hot-path
      def rgame_resolve_transform
        @rgame_world_current = true
        if @rgame_parent.nil?
          @rgame_world_x = @rgame_world_y = 0
          @rgame_world_angle = 0
          return
        end

        pa = @rgame_parent.world_angle
        if pa.zero?
          @rgame_world_x = @rgame_parent.world_x + @rgame_rel_x
          @rgame_world_y = @rgame_parent.world_y + @rgame_rel_y
        else
          cos = Math.cos(pa)
          sin = Math.sin(pa)
          @rgame_world_x = @rgame_parent.world_x + (@rgame_rel_x * cos) - (@rgame_rel_y * sin)
          @rgame_world_y = @rgame_parent.world_y + (@rgame_rel_x * sin) + (@rgame_rel_y * cos)
        end
        @rgame_world_angle = pa + @rgame_rel_angle
      end

      def rgame_place_in_rotated_parent(offset_x, offset_y, pa)
        cos = Math.cos(pa)
        sin = Math.sin(pa)
        self.rel_x = (offset_x * cos) + (offset_y * sin)
        self.rel_y = (offset_y * cos) - (offset_x * sin)
      end

      protected

      attr_accessor :rgame_sibling_order

      def rgame_place(node) = (@rgame_placed ||= []) << node
      def rgame_unplace(node) = @rgame_placed&.delete(node)

      def rgame_children_unsorted! = @rgame_children_sorted = false

      # hot-path
      def rgame_sort_y
        rgame_find_sort_box unless @rgame_sort_box_known
        return @rgame_rel_y unless @rgame_sort_box

        box = @rgame_sort_box.box
        @rgame_rel_y + box.offset_y + box.height
      end

      # hot-path
      def rgame_soil
        return unless @rgame_world_current

        @rgame_world_current = false
        # rubocop:disable Style/SymbolProc -- `&:rgame_soil` would call through
        # Symbol#to_proc, which dispatches publicly and so cannot reach a
        # protected method. An explicit receiver is the only form that works
        # here, and it allocates no more than the symbol would.
        @rgame_placed&.each { it.rgame_soil }
        # rubocop:enable Style/SymbolProc
      end

      private

      # hot-path
      def rgame_stopped? = @rgame_stopped

      def rgame_missing_system(klass)
        where = scene ? 'its scenes or the root' : 'the root'
        message = "#{self.class} found no #{klass} system on #{where}"
        if @rgame_parent.nil?
          return "#{message}. It has no parent, so it is the root: add it to the tree first, " \
                 'or mount the system on it'
        end

        "#{message}. Mount one there with add_component"
      end

      # hot-path
      def rgame_gate(actions)
        poll = actions.poll_count
        return actions if poll.nil?

        (@rgame_press_gate ||= PressGate.new).read(actions, poll)
      end

      # hot-path
      def rgame_resolve_inherited
        if @rgame_parent.nil?
          @rgame_abs_input_owner = @rgame_input_owner
          @rgame_abs_band = @rgame_band || Util::Z::DEFAULT
          return
        end

        @rgame_abs_input_owner = @rgame_input_owner || @rgame_parent.abs_input_owner
        @rgame_abs_band = @rgame_band || @rgame_parent.abs_band
      end
    end
  end
end
