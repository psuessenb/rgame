# frozen_string_literal: true

module RGame
  module Engine
    module Scene
      # The scenes of a game, one on top of another, on a host node.
      #
      #   stack = root.add_component(Engine::Scene::SceneStack.new)
      #   stack.define(:title) { TitleScene.new }
      #   stack.define(:game_over) { |score:| GameOverScene.new(score:) }
      #   stack.define(:village) { |hero:| VillageScene.new(hero:) }
      #
      #   stack.push(:title)                     # a name, or a Node2D
      #   stack.replace(:game_over, score: 12)   # keywords reach the builder
      #   stack.replace(:village, carry: { hero: hero })
      #   stack.pop
      #   stack.on_changed { |scene| ... }       # the top scene, once a switch lands
      #   stack.on_requested { |scene, transition| ... }   # as a switch is asked for
      #
      #   stack.transition = Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)
      #   stack.push(:pause, transition: nil)    # this switch without one
      #
      # **A switch lands in the sweep**, after the tick that asked for it, as a
      # `queue_free` does. A menu item asks during `control`, in the middle of a
      # walk over the scene the switch takes apart, so `push`, `replace` and
      # `pop` only record what was asked. `current` changes when the switch
      # lands. Two switches asked for before a sweep keep only the last.
      #
      # **Only the top scene is controlled and updated. Every scene draws**,
      # bottom to top, so a menu pushed over the world keeps the world on screen
      # and frozen.
      #
      # The scenes live off the host's child list. Each one names the host as its
      # `parent`, so it moves with the host and enters and leaves the tree with
      # it. Each is marked as its own `scene`, which is where scene-lifetime
      # systems are found.
      #
      # **`carry:` takes a node from one scene to the next.** As the switch
      # lands, the stack takes each node from its parent, before the old scene
      # leaves the tree, and hands it to the builder under its key. Its
      # components leave the old scene's systems as it goes, and join the new
      # one's when the builder puts it in the new scene.
      #
      # **A transition covers the view, switches, and reveals it.** With a
      # Scene::Fade, a switch covers the host's view in `:overlay`, lands in the
      # sweep after the cover ends, and reveals the new scene. No scene is
      # controlled until the reveal ends. The scene leaving is not updated
      # under the cover, and the scene arriving is updated from the tick after
      # it lands. So a scene's first press after a transition began after it.
      #
      # A switch asked for during a cover replaces the one waiting, and one
      # asked for during a reveal covers again from where the reveal got to.
      # Either joins the transition under way when it has none of its own. A
      # push onto an empty stack starts covered, since there is nothing to
      # cover.
      class SceneStack < Engine::Component
        # Fired once for each switch that lands, after the new top scene entered
        # the tree. It carries that scene, or nil once the stack is empty.
        signal :changed, :scene

        # Fired as a switch is asked for, before it lands: with the name or the
        # node asked for, or nil for a pop, and the Scene::Fade it runs, or nil.
        # A crossfade over the cover starts here, since `changed` fires after it.
        signal :requested, :scene, :transition

        KEPT = %i[carry transition].freeze
        POSITIONAL = %i[req opt rest].freeze
        KEYWORDS = %i[key keyreq].freeze
        NONE = {}.freeze
        Switch = Data.define(:kind, :scene, :keywords, :carry)
        Named = Data.define(:builder, :required, :accepted, :open)
        private_constant :KEPT, :POSITIONAL, :KEYWORDS, :NONE, :Switch, :Named

        # The Scene::Fade a switch runs unless it names its own, or nil, the
        # default, for none.
        sealed_reader :transition

        def initialize
          super
          @rgame_stack = []
          @rgame_players = nil
          @rgame_builders = {}
          @rgame_request = nil
          @rgame_transition = nil
          @rgame_curtain = nil
        end

        # Sets the transition every switch runs unless it names its own. Anything
        # but a Scene::Fade or nil raises `TypeError`.
        def transition=(transition)
          @rgame_transition = checked_transition(transition)
        end

        # See #control: the scenes this holds need the input source, and a
        # component is only handed one player's snapshot.
        def _attach = @rgame_players = node.system(Engine::Players)

        # Names a scene, so a switch can ask for it by name. The block builds a
        # new scene each time a switch to it lands, and takes the keywords that
        # switch was given. A name is defined once.
        #
        # `carry` and `transition` are the stack's own keywords, so a builder
        # that declares either raises here. So does one that takes positional
        # parameters: a builder takes keywords only.
        def define(name, &builder)
          raise TypeError, "a scene's name is a Symbol, not #{name.inspect}" unless name.is_a?(Symbol)
          raise ArgumentError, "define(#{name.inspect}) needs a block that builds the scene" unless builder
          if @rgame_builders.key?(name)
            raise ArgumentError, "a scene named #{name.inspect} is already defined on this stack"
          end

          @rgame_builders[name] = named(name, builder)
          self
        end

        # Asks for `scene` on top of the current one, which stays underneath. A
        # scene is a node, or a name given to #define with the keywords its
        # builder takes. A name the stack was not given raises `KeyError` here.
        #
        # `carry:` is a Hash of nodes to take into the new scene, each handed to
        # the builder under its key. It needs a name, not a node.
        #
        # `transition:` is a Scene::Fade for this switch in place of the
        # stack's, or nil for none.
        def push(scene, carry: NONE, transition: @rgame_transition, **)
          ask(:push, scene, carry, transition, **)
        end

        # Asks for `scene` in place of the current one.
        def replace(scene, carry: NONE, transition: @rgame_transition, **)
          ask(:replace, scene, carry, transition, **)
        end

        # Asks for the top scene to go. Landing on an empty stack changes nothing.
        def pop(transition: @rgame_transition)
          transition = checked_transition(transition)
          start(transition)
          @rgame_request = Switch.new(:pop, nil, NONE, NONE)
          requested_signal.emit(scene: nil, transition:)
          self
        end

        # The top scene, once a switch has landed: nil on an empty stack.
        def current
          @rgame_stack.last
        end

        # Whether a switch was asked for and has not landed.
        def pending? = !@rgame_request.nil?

        # Whether a transition is covering or revealing.
        def transitioning? = curtain.running?

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
        def _control(actions)
          return if curtain.running?
          return unless (current_scene = current)

          current_scene.control(@rgame_players || actions)
        end

        def _update(dt)
          curtain.update(dt)
          return unless (current_scene = current)

          current_scene.update(dt) unless curtain.covering?
        end

        # Every scene in the stack, not just the current one — that asymmetry
        # with control/update is what lets a menu pushed on top keep the world
        # visible underneath while freezing it. A transition's fade draws over
        # them all.
        def _draw(renderer, view)
          @rgame_stack.each do |scene|
            scene.draw(renderer, view)
          end
          curtain.draw(renderer, view)
        end

        # Scenes live in @rgame_stack, off the host's child list, so the host's
        # #sweep_freed cannot reach them. The sweep goes into the top scene's
        # subtree, and then the switch asked for lands, once any cover is done.
        def _sweep_freed
          current&.sweep_freed
          return unless @rgame_request && curtain.ready?

          land
          curtain.open
        end

        private

        def ask(kind, scene, carry, transition, **keywords)
          if scene.is_a?(Symbol)
            check_carry(carry, keywords)
            check_keywords(scene, keywords, carry)
          elsif !scene.respond_to?(:enter_tree)
            raise TypeError, "a scene is a node or a name given to define, not #{scene.inspect}"
          elsif !keywords.empty? || !carry.empty?
            raise ArgumentError, "keywords and carry: go to a named scene's builder, and #{scene.class} is a " \
                                 "node: #{(keywords.keys + carry.keys).join(', ')}"
          end
          transition = checked_transition(transition)
          start(transition)
          @rgame_request = Switch.new(kind, scene, keywords, carry)
          requested_signal.emit(scene:, transition:)
          self
        end

        def start(transition) = curtain.close(transition, at_once: current.nil?)

        def curtain = @rgame_curtain ||= Curtain.new(node)

        def checked_transition(transition)
          return transition if transition.nil? || transition.is_a?(Fade)

          raise TypeError, "a transition is a #{Fade} or nil, not #{transition.inspect}"
        end

        def land
          switch = @rgame_request
          @rgame_request = nil
          return if switch.kind == :pop && @rgame_stack.empty?

          switch.carry.each_value { |carried| carried.parent&.remove_node(carried) }
          scene = built(switch) unless switch.kind == :pop
          land_pop unless switch.kind == :push
          land_push(scene) if scene
          changed_signal.emit(current)
        end

        def built(switch)
          return switch.scene unless switch.scene.is_a?(Symbol)

          @rgame_builders.fetch(switch.scene).builder.call(**switch.keywords, **switch.carry)
        end

        def land_push(scene)
          @rgame_stack.push(scene)
          scene.parent = node
          scene.scene = scene
          scene.enter_tree
        end

        def land_pop
          scene = @rgame_stack.pop
          return unless scene

          scene.exit_tree
          scene.scene = nil
          scene.parent = nil
        end

        def named_for(name)
          @rgame_builders.fetch(name) do
            raise KeyError.new("this stack has no scene named #{name.inspect}. Name it first: " \
                               "define(#{name.inspect}) { ... }", receiver: @rgame_builders, key: name)
          end
        end

        def named(name, builder)
          parameters = builder.parameters
          if parameters.any? { |type, _| POSITIONAL.include?(type) }
            raise ArgumentError, "the builder for #{name.inspect} takes positional parameters. A builder takes " \
                                 'keywords only, the ones a switch passes: define(:name) { |score:| ... }'
          end

          accepted = parameters.filter_map { |type, key| key if KEYWORDS.include?(type) }
          taken = accepted & KEPT
          unless taken.empty?
            raise ArgumentError, "the builder for #{name.inspect} declares #{taken.join(' and ')}, which the " \
                                 'stack keeps for itself. Give the keyword another name'
          end

          required = parameters.filter_map { |type, key| key if type == :keyreq }
          Named.new(builder, required.freeze, accepted.freeze, parameters.any? { |type, _| type == :keyrest })
        end

        def check_carry(carry, keywords)
          return if carry.equal?(NONE)

          unless carry.is_a?(Hash) && carry.all? { |key, carried| key.is_a?(Symbol) && carried.respond_to?(:parent) }
            raise TypeError, "carry: is a Hash of names to nodes, as in carry: { hero: hero }, not #{carry.inspect}"
          end

          both = carry.keys & keywords.keys
          raise ArgumentError, "#{both.join(', ')} given both as a keyword and in carry:" unless both.empty?
        end

        def check_keywords(name, keywords, carry)
          named = named_for(name)
          return if keywords.empty? && carry.empty? && named.required.empty?

          given = keywords.keys + carry.keys
          missing = named.required - given
          raise ArgumentError, "scene #{name.inspect} needs #{missing.join(', ')}" unless missing.empty?
          return if named.open

          unknown = given - named.accepted
          raise ArgumentError, "scene #{name.inspect} takes no #{unknown.join(', ')}" unless unknown.empty?
        end
      end
    end
  end
end
