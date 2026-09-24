# frozen_string_literal: true

module RGame
  module Engine
    module Scene
      # The scenes of a game, one on top of another, on a host node.
      #
      #   stack = root.add_component(Engine::Scene::SceneStack.new)
      #   stack.define(:title) { TitleScene.new }
      #   stack.define(:game_over) { |score:| GameOverScene.new(score:) }
      #
      #   stack.push(:title)                     # a name, or a Node2D
      #   stack.replace(:game_over, score: 12)   # keywords reach the builder
      #   stack.pop
      #   stack.on_changed { |scene| ... }       # the top scene, once a switch lands
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
      class SceneStack < Engine::Component
        # Fired once for each switch that lands, after the new top scene entered
        # the tree. It carries that scene, or nil once the stack is empty.
        signal :changed, :scene

        KEPT = %i[carry transition].freeze
        POSITIONAL = %i[req opt rest].freeze
        KEYWORDS = %i[key keyreq].freeze
        NONE = {}.freeze
        Switch = Data.define(:kind, :scene, :keywords)
        private_constant :KEPT, :POSITIONAL, :KEYWORDS, :NONE, :Switch

        def initialize
          super
          @stack = []
          @players = nil
          @builders = {}
          @request = nil
        end

        # See #control: the scenes this holds need the input source, and a
        # component is only handed one player's snapshot.
        def _attach = @players = node.system(Engine::Players)

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
          raise ArgumentError, "a scene named #{name.inspect} is already defined on this stack" if @builders.key?(name)

          check_builder(name, builder.parameters)
          @builders[name] = builder
          self
        end

        # Asks for `scene` on top of the current one, which stays underneath. A
        # scene is a node, or a name given to #define with the keywords its
        # builder takes. A name the stack was not given raises `KeyError` here.
        def push(scene, **) = ask(:push, scene, **)

        # Asks for `scene` in place of the current one.
        def replace(scene, **) = ask(:replace, scene, **)

        # Asks for the top scene to go. Landing on an empty stack changes nothing.
        def pop
          @request = Switch.new(:pop, nil, NONE)
          self
        end

        # The top scene, once a switch has landed: nil on an empty stack.
        def current
          @stack.last
        end

        # Whether a switch was asked for and has not landed.
        def pending? = !@request.nil?

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
          return unless (current_scene = current)

          current_scene.control(@players || actions)
        end

        def _update(dt)
          return unless (current_scene = current)

          current_scene.update(dt)
        end

        # Every scene in the stack, not just the current one — that asymmetry
        # with control/update is what lets a menu pushed on top keep the world
        # visible underneath while freezing it.
        def _draw(renderer, view)
          @stack.each do |scene|
            scene.draw(renderer, view)
          end
        end

        # Scenes live in @stack, off the host's child list, so the host's
        # #sweep_freed cannot reach them. The sweep goes into the top scene's
        # subtree, and then the switch asked for lands.
        def _sweep_freed
          current&.sweep_freed
          land if @request
        end

        private

        def ask(kind, scene, **keywords)
          if scene.is_a?(Symbol)
            check_keywords(scene, keywords.keys)
          elsif !scene.respond_to?(:enter_tree)
            raise TypeError, "a scene is a node or a name given to define, not #{scene.inspect}"
          elsif !keywords.empty?
            raise ArgumentError, "keywords go to a named scene's builder, and #{scene.class} is a node: " \
                                 "#{keywords.keys.join(', ')}"
          end
          @request = Switch.new(kind, scene, keywords)
          self
        end

        def land
          switch = @request
          @request = nil
          return if switch.kind == :pop && @stack.empty?

          scene = built(switch) unless switch.kind == :pop
          land_pop unless switch.kind == :push
          land_push(scene) if scene
          changed_signal.emit(current)
        end

        def built(switch)
          return switch.scene unless switch.scene.is_a?(Symbol)

          @builders.fetch(switch.scene).call(**switch.keywords)
        end

        def land_push(scene)
          @stack.push(scene)
          scene.parent = node
          scene.scene = scene
          scene.enter_tree
        end

        def land_pop
          scene = @stack.pop
          return unless scene

          scene.exit_tree
          scene.scene = nil
          scene.parent = nil
        end

        def builder_for(name)
          @builders.fetch(name) do
            raise KeyError.new("this stack has no scene named #{name.inspect}. Name it first: " \
                               "define(#{name.inspect}) { ... }", receiver: @builders, key: name)
          end
        end

        def check_builder(name, parameters)
          if parameters.any? { |type, _| POSITIONAL.include?(type) }
            raise ArgumentError, "the builder for #{name.inspect} takes positional parameters. A builder takes " \
                                 'keywords only, the ones a switch passes: define(:name) { |score:| ... }'
          end

          taken = parameters.filter_map { |type, key| key if KEYWORDS.include?(type) } & KEPT
          return if taken.empty?

          raise ArgumentError, "the builder for #{name.inspect} declares #{taken.join(' and ')}, which the " \
                               'stack keeps for itself. Give the keyword another name'
        end

        def check_keywords(name, given)
          parameters = builder_for(name).parameters
          required = parameters.filter_map { |type, key| key if type == :keyreq }
          missing = required - given
          raise ArgumentError, "scene #{name.inspect} needs #{missing.join(', ')}" unless missing.empty?
          return if parameters.any? { |type, _| type == :keyrest }

          unknown = given - parameters.filter_map { |type, key| key if KEYWORDS.include?(type) }
          raise ArgumentError, "scene #{name.inspect} takes no #{unknown.join(', ')}" unless unknown.empty?
        end
      end
    end
  end
end
