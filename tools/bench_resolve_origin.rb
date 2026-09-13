# frozen_string_literal: true

module Tree
  attr_reader :children, :parent

  def initialize(x, y)
    @x = x
    @y = y
    @children = []
    @parent = nil
  end

  def add(child)
    child.instance_variable_set(:@parent, self)
    @children << child
    child
  end
end

# A — today. One top-down pass per phase; abs_* is then an ivar read.
class EagerNode
  include Tree

  attr_reader :world_x, :world_y
  attr_accessor :x, :y

  def resolve_tree
    if @parent
      @world_x = @parent.world_x + @x
      @world_y = @parent.world_y + @y
    else
      @world_x = @x
      @world_y = @y
    end
    @children.each(&:resolve_tree)
  end
end

# B — no stored absolute at all: walk to the root on every query.
class LazyNode
  include Tree

  attr_accessor :x, :y

  def world_x = @parent ? @parent.world_x + @x : @x
  def world_y = @parent ? @parent.world_y + @y : @y
  def resolve_tree; end
end

# C — Godot/Unity: cached, invalidated down the subtree when a transform is written.
class CachedNode
  include Tree

  attr_reader :x, :y

  def initialize(x, y)
    super
    @clean = false
  end

  def x=(value)
    @x = value
    soil
  end

  def y=(value)
    @y = value
    soil
  end

  def world_x
    resolve unless @clean
    @world_x
  end

  def world_y
    resolve unless @clean
    @world_y
  end

  def resolve_tree; end

  private

  def resolve
    if @parent
      @world_x = @parent.world_x + @x
      @world_y = @parent.world_y + @y
    else
      @world_x = @x
      @world_y = @y
    end
    @clean = true
  end

  def soil
    return unless @clean

    @clean = false
    @children.each { it.send(:soil) }
  end
end

VARIANTS = [['Eager x2 (before)', EagerNode, 2], ['Eager x1', EagerNode, 1],
            ['Lazy uncached', LazyNode, 1], ['Cached (shipped)', CachedNode, 1]].freeze
BASELINE = 'Eager x2 (before)'
CHECKED = [EagerNode, LazyNode, CachedNode].freeze

def build(klass, breadth)
  root = klass.new(0, 0)
  level = [root]
  breadth.each { |n| level = level.flat_map { |p| Array.new(n) { |i| p.add(klass.new(i + 1, i + 2)) } } }
  root
end

def flatten(node, acc = [])
  (acc << node
   node.children.each { flatten(it, acc) }
   acc)
end

def run(label, breadth, movers_pct, queries_per_tick, ticks: 2000)
  results = {}
  VARIANTS.each do |label, klass, passes|
    root = build(klass, breadth)
    nodes = flatten(root)
    rng = Random.new(99)
    movers = nodes.sample(nodes.size * movers_pct / 100, random: rng)
    targets = Array.new(queries_per_tick) { nodes.sample(random: rng) }
    sink = 0.0

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ticks.times do
      passes.times { root.resolve_tree }
      movers.each { |n| n.x = n.x + 1 }
      targets.each { |n| sink += n.world_x + n.world_y }
    end
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @sink = sink

    results[label] = (t1 - t0) / ticks
  end

  base = results.fetch(BASELINE)
  puts label
  results.each do |name, per_tick|
    printf("    %-18s %8.1f µs/tick   %s\n", name, per_tick * 1e6,
           name == BASELINE ? '(baseline)' : format('%+.1f%%', (per_tick - base) / base * 100))
  end
  puts
end

def check(breadth)
  trees = CHECKED.map { |k| build(k, breadth) }
  trees.each(&:resolve_tree)
  flat = trees.map { flatten(it) }
  flat[0].each_index do |i|
    vals = flat.map { |ns| [ns[i].world_x, ns[i].world_y] }
    raise "disagreement at node #{i}: #{vals.inspect}" unless vals.uniq.size == 1
  end
  flat.each { |ns| ns[3].x = 99 }
  trees[0].resolve_tree
  flat[0].each_index do |i|
    vals = flat.map { |ns| [ns[i].world_x, ns[i].world_y] }
    raise "stale after write at node #{i}: #{vals.inspect}" unless vals.uniq.size == 1
  end
  puts 'correctness: all strategies agree on every node, before and after a write'
  puts "(the eager tree needed a second resolve pass to see the write at all)\n\n"
end

DEEP = Array.new(20, 1).freeze
WIDE = [4, 5, 5, 4].freeze

n = flatten(build(EagerNode, WIDE)).size
puts "525-node tree (#{n} nodes, depth 4) unless noted; per-tick cost, 2000 ticks\n\n"

check(WIDE)
run('collision-ish: 20% of nodes move, 1200 world reads/tick', WIDE, 20, 1200)
run('typical: 10% move, 200 world reads/tick',                 WIDE, 10, 200)
run('draw-only world: 10% move, 0 world reads/tick',           WIDE, 10, 0)
run('query-heavy: 2% move, 4000 world reads/tick',             WIDE, 2, 4000)
run("deep chain (#{DEEP.size + 1} nodes, depth #{DEEP.size}): 20% move, 1200 reads", DEEP, 20, 1200)
