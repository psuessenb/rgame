# frozen_string_literal: true

module Engine
  # A reuse-don't-allocate pool for many short-lived, homogeneous objects —
  # bullets, particles, transient enemies. Acquired objects come from a free list
  # (or the factory when the list is empty) so steady-state spawning allocates
  # nothing. Pure logic; no Gosu.
  #
  #   pool = Engine::Pool.new { Bullet.new }
  #   b = pool.acquire        # recycled or freshly built
  #   pool.each { |b| b.update(dt) }
  #   pool.reclaim_if(&:dead?) # sweep dead → free list, once per frame
  #
  # The factory builds a blank object; callers re-initialise it after `acquire`.
  class Pool
    def initialize(&factory)
      @factory = factory
      @free = []
      @active = []
    end

    attr_reader :active

    def acquire
      obj = @free.empty? ? @factory.call : @free.pop
      @active.push(obj)
      obj
    end

    def each(&) = @active.each(&)

    def size = @active.size

    # No live (acquired, not-yet-reclaimed) objects.
    def empty? = @active.empty?

    # Deferred removal: sweep the active list once, moving every object for which
    # the block returns true onto the free list. Safe to call after iterating with
    # `each` — never mutate the active list mid-iteration; mark objects dead during
    # the frame and reclaim them here.
    def reclaim_if
      @active.reject! do |obj|
        dead = yield(obj)
        @free.push(obj) if dead
        dead
      end
    end
  end
end
