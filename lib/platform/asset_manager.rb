# frozen_string_literal: true

require 'json'

module Platform
  # The single loader and cache for file-backed assets. Resolves relative paths
  # against one root, loads each through a typed loader, and memoises the result —
  # so an asset requested twice is loaded once and the same instance is shared.
  #
  #   assets = Platform::AssetManager.new(root: MEDIA)
  #   renderer.register_image(:space, assets.image('space.png'))
  #   assets.preload(:level1, image: ['lvl1/bg.png'], sound: ['lvl1/hit.ogg'])
  #   assets.release(:level1)   # frees lvl1/* unless another group still holds it
  #
  # Assets carry the set of groups that loaded them. Plain (ungrouped) loads are
  # owned by PERMANENT and survive every #release (only #clear drops them); grouped
  # loads are reference counted, so an asset two groups loaded is freed only once
  # both release it. Composite assets (sheet/ui_atlas) pull their descriptor and
  # backing image through this same cache, so a sheet's PNG is shared with a
  # standalone #image of that file (and released with the composite's group).
  #
  # Loaders are injectable so the cache/grouping logic is testable without Gosu: the
  # defaults reference Gosu/Platform only inside the procs, never at load time, so
  # requiring this file pulls in no window/context.
  class AssetManager
    # Owner of ungrouped loads; never released, only dropped by #clear.
    PERMANENT = :__permanent__

    DEFAULT_LOADERS = {
      image: ->(path) { Gosu::Image.new(path, retro: true) },
      sound: ->(path) { Gosu::Sample.new(path) },
      song: ->(path) { Gosu::Song.new(path) },
      tilemap: ->(path) { Platform::TileMapRenderer.load(path) },
      read: ->(path) { File.read(path) }
    }.freeze

    def initialize(root:, loaders: DEFAULT_LOADERS)
      @root = root
      @loaders = loaders
      @cache = {}
      @owners = {} # cache key => Set of groups holding it
    end

    # Each takes a root-relative path.
    def image(path, group = PERMANENT)   = leaf(:image, path, group)
    def sound(path, group = PERMANENT)   = leaf(:sound, path, group)
    def song(path, group = PERMANENT)    = leaf(:song, path, group)
    def tilemap(path, group = PERMANENT) = leaf(:tilemap, path, group)
    def read(path, group = PERMANENT)    = leaf(:read, path, group)

    # Composites assemble through the cache (shared descriptor read + backing image).
    def sheet(path, group = PERMANENT)
      fetch(:sheet, path, group) { build_sprite_sheet(path, group) }
    end

    def ui_atlas(path, group = PERMANENT)
      fetch(:ui_atlas, path, group) { build_ui_atlas(path, group) }
    end

    # Batch-load a set under a group:
    #   preload(:level1, image: ['lvl1/bg.png'], sheet: ['lvl1/enemies.json'])
    def preload(group, **manifest)
      manifest.each { |type, paths| Array(paths).each { |path| public_send(type, path, group) } }
      self
    end

    # Remove `group` from every asset's owner set, then drop any asset no group (nor
    # PERMANENT) still holds — releasing the reference for GC/Gosu to free.
    def release(group)
      @owners.each_value { |groups| groups.delete(group) }
      @owners.reject! do |key, groups|
        next false unless groups.empty?

        @cache.delete(key)
        true
      end
      self
    end

    # Drop everything, including PERMANENT assets.
    def clear
      @cache.clear
      @owners.clear
      self
    end

    private

    def leaf(type, path, group)
      fetch(type, path, group) { @loaders.fetch(type).call(File.join(@root, path)) }
    end

    # Memoise on miss, then record the owning group (so a cache hit under a new group
    # still tags it). Tagging after the load means a failed load leaves no owner.
    def fetch(type, path, group)
      key = [type, path]
      object = (@cache[key] ||= yield)
      (@owners[key] ||= Set.new) << group
      object
    end

    def build_sprite_sheet(relpath, group)
      data = JSON.parse(read(relpath, group), symbolize_names: true)
      img  = image(sibling(relpath, data[:image]), group)
      Platform::SpriteSheet.new(img, data)
    end

    def build_ui_atlas(relpath, group)
      data = JSON.parse(read(relpath, group), symbolize_names: true)
      img  = image(sibling(relpath, data[:image]), group)
      Platform::UiAtlas.new(img, data)
    end

    # A path next to `relpath` (root-relative), so a descriptor's image shares the
    # same image cache key as a standalone #image of that file.
    def sibling(relpath, name)
      dir = File.dirname(relpath)
      dir == '.' ? name : File.join(dir, name)
    end
  end
end
