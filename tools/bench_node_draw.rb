# frozen_string_literal: true

# Measures what it costs to draw one node, so the scene-graph transform can be
# moved into the renderer on evidence rather than on faith.
#
#   make ext-core
#   xvfb-run -a ruby tools/bench_node_draw.rb     # or without xvfb-run on a desktop
#
# ## What it compares
#
# A node draws in its own local space and Node2D#draw pushes its transform onto
# the renderer -- the arrangement every scene-graph engine uses (Godot's `_draw`,
# Unity's renderers, Bevy), and already how the camera works here, see
# RGame::Engine::WorldView#draw. This measures what that costs against the design
# it replaced, and is the regression guard for the draw path.
#
#   A   the old design: full resolve_origin, on_draw at world_x/world_y
#   B   what shipped: the transform pushed, on_draw at (0, 0)
#   C   B without resolving a transform drawing no longer reads -- what could be
#       saved if culling ever stopped needing a world coordinate at draw time
#   A0/B0  the same trees with every node at (0, 0), where the transform push is
#       skipped entirely and resolve_origin still runs
#
# Every variant puts the identical rects on the queue, and the timing window
# closes before submission, so the delta is transform bookkeeping and not
# rasterisation.
#
# ## Reading it
#
# The number that matters is ns/node-draw, because that is what scales with the
# scene. A frame at 60fps has 16.6 ms; a mid-size scene draws on the order of a
# thousand nodes per frame once split-screen doubles it.
#
# It uses the real RGame::Engine::Node2D, so it stays honest as the refactor
# lands: after each step, rerun it.

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rgame'
require 'rgame/core'

RED = RGame::Util::Color.new(224, 64, 64)

# The old design, kept as the thing to measure against: a node resolved its
# world transform and drew at it. It draws in world space on purpose, which is
# what DrawInLocalSpace exists to stop, so the cop is off for it.
# rubocop:disable Game/DrawInLocalSpace
class WorldSpaceNode < RGame::Engine::Node2D
  def on_draw(renderer, _view) = renderer.rect(world_x, world_y, 8, 8, color: RED)

  def draw(renderer, view)
    resolve_origin
    renderer.layered(abs_band) do
      if world_angle.zero?
        draw_content(renderer, view)
      else
        renderer.rotated(world_angle * 180.0 / Math::PI, world_x, world_y) do
          draw_content(renderer, view)
        end
      end
    end
    draw_children(renderer, view)
  end
end
# rubocop:enable Game/DrawInLocalSpace

# What shipped: stock Node2D#draw pushes the node's transform and the node draws
# at its own origin. No override at all — that is the point.
class LocalSpaceNode < RGame::Engine::Node2D
  def on_draw(renderer, _view) = renderer.rect(0, 0, 8, 8, color: RED)
end

# The cost of resolving a transform that drawing no longer reads. `draw` keeps
# doing it because culling is world-space (see Node2D#draw); this is what it
# would save if that were ever moved off the draw path.
class LocalSpaceNodeNoResolve < LocalSpaceNode
  def draw(renderer, view)
    resolve_inherited
    in_local_space(renderer) do
      renderer.layered(abs_band) { draw_content(renderer, view) }
      draw_children(renderer, view)
    end
  end
end

def build(klass, breadth: [4, 5, 5, 4], offset: true)
  root = klass.new(x: 0, y: 0)
  level = [root]
  breadth.each do |n|
    level = level.flat_map do |parent|
      Array.new(n) { |i| parent.add_node(offset ? klass.new(x: 3 + i, y: 2 + i) : klass.new(x: 0, y: 0)) }
    end
  end
  [root, count(root)]
end

def count(node) = 1 + node.children.sum { count(it) }

class Bench < RGame::Core::App
  FRAMES = 900
  WARMUP = 150
  VIEWPORTS = 2 # split screen: the whole tree is drawn once per player

  def initialize(trees)
    super(width: 320, height: 240, caption: 'transform bench')
    @trees = trees
    @renderer = RGame::Core::Renderer.new(self)
    @times = Hash.new { |h, k| h[k] = [] }
    @frame = 0
    @rng = Random.new(1234)
    @view = RGame::Engine::View.new(x: 0, y: 0, width: 320, height: 240)
  end

  attr_reader :times, :renderer

  def needs_redraw? = true

  def draw
    @frame += 1
    close if @frame > FRAMES

    @trees.to_a.shuffle(random: @rng).each do |name, (root, _n)|
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      VIEWPORTS.times { root.draw(renderer, @view) }
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @times[name] << (t1 - t0) unless @frame <= WARMUP
    end
  end
end

trees = {
  'A  world space (the old design)' => build(WorldSpaceNode),
  'B  local space (what shipped)' => build(LocalSpaceNode),
  'C  local space, no transform resolve' => build(LocalSpaceNodeNoResolve),
  'A0 world space, all nodes at (0,0)' => build(WorldSpaceNode, offset: false),
  'B0 local space, all nodes at (0,0)' => build(LocalSpaceNode, offset: false)
}
nodes = trees.values.first[1]

app = Bench.new(trees)
app.run

puts "#{nodes} nodes/tree, #{Bench::VIEWPORTS} viewports => #{nodes * Bench::VIEWPORTS} node draws/frame"
puts "#{Bench::FRAMES - Bench::WARMUP} timed frames\n\n"
stats = app.times.transform_values do |samples|
  s = samples.sort
  { mean: s.sum / s.size, median: s[s.size / 2] }
end
base = stats.fetch('A  world space (the old design)')[:mean]
draws = nodes * Bench::VIEWPORTS
stats.each do |name, st|
  printf("%-40s mean %6.3f ms   median %6.3f ms   %6.1f ns/node-draw   %+6.1f ns  (%+5.2f%% of a 16.6 ms frame)\n",
         name, st[:mean] * 1000, st[:median] * 1000, st[:mean] / draws * 1e9,
         (st[:mean] - base) / draws * 1e9, (st[:mean] - base) / 0.0166 * 100)
end
