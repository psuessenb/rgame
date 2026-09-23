# frozen_string_literal: true

# The world transform is computed when read and cached until something moves,
# so its correctness is not a property of any one call — it is a property of
# *sequences* of moves, reparentings and reads, and of an invariant about which
# nodes are stale at any moment (see Node2D#rgame_soil).
#
# The examples elsewhere cover the cases someone thought of. This one covers the
# ones nobody did: it drives random sequences against a from-scratch walk of the
# parent chain, which caches nothing and so cannot be wrong in the same way.
#
# It is a fuzz test with a **fixed seed**, so it is as reproducible as any other
# example here — the randomness generates the shapes, it does not make the run
# vary. Three deliberate breakages were each caught by it: dropping the
# invalidation from `parent=` (611 mismatches), stopping the invalidation at the
# node instead of walking its subtree (2733), and inverting the already-stale
# guard (4295). The second example holds a third of its nodes off the child
# list, and walking `children` instead of every node that names this one as
# parent fails it.
RSpec.describe RGame::Engine::Node2D do
  describe 'the cached world transform' do
    # The truth to compare against: accumulate down from the root every time,
    # storing nothing. Deliberately the naive implementation.
    def walked(node)
      return [0.0, 0.0, 0.0] if node.parent.nil?

      px, py, pa = walked(node.parent)
      cos = Math.cos(pa)
      sin = Math.sin(pa)
      [px + (node.x * cos) - (node.y * sin),
       py + (node.x * sin) + (node.y * cos),
       pa + node.angle]
    end

    # `held` is the share of nodes attached by setting `parent` alone, off the
    # child list, as Scene::SceneStack attaches its scenes.
    def random_tree(rng, size, held: 0.0)
      root = described_class.new
      nodes = [root]
      size.times do
        node = described_class.new(x: rng.rand(-50.0..50.0), y: rng.rand(-50.0..50.0),
                                   angle: rng.rand(-3.0..3.0))
        attach(rng, node, nodes.sample(random: rng), held)
        nodes << node
      end
      nodes
    end

    def attach(rng, node, parent, held)
      if rng.rand < held
        node.parent = parent
      else
        parent.add_node(node)
      end
    end

    def detach(node)
      if node.parent.children.include?(node)
        node.parent.remove_node(node)
      else
        node.parent = nil
      end
    end

    # Reparenting a node under its own descendant would build a cycle, which is
    # not a thing the engine allows and not what this is testing.
    def inside?(node, candidate)
      walk = candidate
      walk = walk.parent until walk.nil? || walk.equal?(node)
      !walk.nil?
    end

    def reparent(rng, nodes, held)
      node = nodes[1..].sample(random: rng)
      target = nodes.sample(random: rng)
      return if node.equal?(target) || target.equal?(node.parent) || inside?(node, target)

      detach(node)
      attach(rng, node, target, held)
    end

    # Random moves, reparentings and reads, each read checked against the walk.
    # Returns how many reads it compared.
    def fuzz(rng, held: 0.0)
      compared = 0
      20.times do
        nodes = random_tree(rng, 30, held: held)

        600.times do
          case rng.rand(5)
          when 0 then nodes.sample(random: rng).x = rng.rand(-99.0..99.0)
          when 1 then nodes.sample(random: rng).y = rng.rand(-99.0..99.0)
          when 2 then nodes.sample(random: rng).angle = rng.rand(-3.14..3.14)
          when 3 then reparent(rng, nodes, held)
          else
            node = nodes.sample(random: rng)
            compared += 1
            cached = [node.world_x, node.world_y, node.world_angle]
            walked(node).each_with_index do |want, i|
              expect(cached[i]).to be_within(1e-9).of(want)
            end
          end
        end
      end
      compared
    end

    # Guards the guard, in both examples: if the generator ever stops producing
    # reads, an example would pass by doing nothing.
    it 'agrees with a from-scratch walk through any sequence of moves and reparentings' do
      expect(fuzz(Random.new(20_260_827))).to be > 1000
    end

    # A third of the nodes hang off their parent by `parent` alone, as a scene
    # hangs off the node holding its SceneStack.
    it 'agrees with it for nodes held off the child list too' do
      expect(fuzz(Random.new(20_260_923), held: 0.3)).to be > 1000
    end
  end
end
