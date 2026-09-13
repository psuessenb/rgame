# frozen_string_literal: true

require 'json'

module RGame
  module Core
    # The one place file-backed assets are loaded and cached.
    #
    #   app.assets.image('space.png')
    #   app.assets.sheet('example 09/player.json')
    #   app.assets.preload(:level1, image: ['lvl1/bg.png'], sound: ['lvl1/hit.ogg'])
    #   app.assets.release(:level1)
    #
    # The built-in types are `image`, `sound`, `song` and `read`, plus the
    # composites `sheet` and `ui_atlas`. A game or its glue adds more with
    # {#add_loader}, which is how a tile map gets loaded without Core having to
    # know what one is.
    #
    # Every accessor takes a path **relative to the media root** — or an
    # absolute one, which is used as it stands — and returns the same object
    # every time, so a file asked for twice is read, decoded and uploaded once.
    # Two spellings of one path are one entry, not two. That is the whole point: loading stops being scattered
    # across a game's setup code, building paths ad hoc and constructing images
    # inline, and becomes one object that knows what is loaded.
    #
    # A game does not build one of these. `App#assets` does, rooted at the
    # app's `media_root:`, on first use — see RGame::Core::App.
    #
    # ## Groups, and what `release` frees
    #
    # Each cached asset remembers the **set of groups** that asked for it.
    # Ungrouped loads belong to {PERMANENT} and survive every `release`; only
    # `clear` drops those. A grouped load is reference counted, so an asset two
    # levels both loaded stays until both release it:
    #
    #   assets.image('ui/buttons.png')                    # PERMANENT
    #   assets.preload(:level1, image: ['lvl1/bg.png'])   # :level1
    #   assets.release(:level1)                           # drops lvl1/bg.png only
    #
    # Releasing drops this cache's reference. The GPU texture goes when the last
    # reference anywhere goes, which is the collector's business, not this
    # class's — see `Image.debug_live_textures` if you need to watch it happen.
    #
    # ## Composites share their parts
    #
    # A sprite sheet is a descriptor plus an image, and both are pulled *through
    # this same cache*. So `assets.sheet('hero.json')` and
    # `assets.image('hero.png')` hand back one upload between them, and the
    # sheet's PNG is released with the sheet's group.
    #
    # ## Loaders are injectable, and that is deliberate
    #
    # Each asset type maps to a proc, and the defaults name `Image`, `Audio` and
    # friends only *inside* their bodies — never at load time. Passing your own
    # `loaders:` is what lets the caching, path resolution and grouping be
    # specced with no window, no GL context and no files at all.
    class AssetManager
      PERMANENT = :__permanent__

      # `app` is what images are loaded into and where the audio device comes
      # from; `root` is what every path is resolved against.
      def initialize(root:, app:, loaders: nil)
        @root = root
        @app = app
        @loaders = {}
        @cache = {}
        @owners = {}

        (loaders || default_loaders).each { |type, loader| add_loader(type, &loader) }
      end

      # Teaches this manager a new asset type, and gives it an accessor:
      #
      #   assets.add_loader(:tilemap) { |path| ... }
      #   assets.tilemap('map/island.tmx')
      #
      # The built-in types go through this too, at construction — there is one
      # mechanism, not a privileged set plus an extension point.
      #
      # It exists because some asset types cannot be built from inside
      # `RGame::Core` at all. A tile map is the case that forced it: parsing a
      # `.tmx` belongs to the engine layer, and Core may not name that layer
      # (see CLAUDE.md, "The rule points both ways"). So the glue installs the
      # loader, and Core never learns what a tile map is.
      #
      # Defining the accessor rather than routing everything through a generic
      # `load(type, path)` keeps `assets.tilemap(path)` reading like the
      # built-ins — and makes `respond_to?(:tilemap)` false until a loader
      # exists, which is exactly what `Renderer#resolve_asset` asks before
      # offering it an id.
      def add_loader(type, &loader)
        @loaders[type] = loader
        define_singleton_method(type) { |path, group = PERMANENT| leaf(type, path, group) }
        self
      end

      # The types this manager can load. `:image`, `:sound`, `:song` and `:read`
      # are built in; anything else came from #add_loader.
      def types = @loaders.keys

      # A sprite sheet, assembled through the cache: its descriptor is a cached
      # `read` and its image a cached `image`, so nothing is loaded twice.
      def sheet(path, group = PERMANENT)
        fetch(:sheet, path, group) { build_sprite_sheet(path, group) }
      end

      # A UI atlas, assembled the same way.
      def ui_atlas(path, group = PERMANENT)
        fetch(:ui_atlas, path, group) { build_ui_atlas(path, group) }
      end

      # Loads a set of assets under one group, so they can be released together:
      #
      #   assets.preload(:level1, image: ['lvl1/bg.png'], sheet: ['lvl1/foes.json'])
      def preload(group, **manifest)
        manifest.each do |type, paths|
          unless respond_to?(type)
            raise ArgumentError, "unknown asset type #{type.inspect} in preload(#{group.inspect})"
          end

          Array(paths).each { |path| public_send(type, path, group) }
        end
        self
      end

      # Takes `group` off every asset's owner set and drops whatever no group
      # still holds.
      def release(group)
        raise ArgumentError, 'ungrouped assets are dropped by #clear, not #release' if group == PERMANENT

        @owners.each_value { |groups| groups.delete(group) }
        @owners.reject! do |key, groups|
          next false unless groups.empty?

          @cache.delete(key)
          true
        end
        self
      end

      # Drops everything, PERMANENT included.
      def clear
        @cache.clear
        @owners.clear
        self
      end

      # How many assets are cached. For tests and for a debug overlay; a game
      # has no reason to ask.
      def size = @cache.size

      private

      def default_loaders
        {
          image: ->(path) { Image.new(@app, path) },
          sound: ->(path) { @app.audio.sample(path) },
          song: ->(path) { @app.audio.song(path) },
          read: ->(path) { File.read(path) }
        }.freeze
      end

      def leaf(type, path, group)
        fetch(type, path, group) { @loaders.fetch(type).call(resolve(path)) }
      end

      def resolve(path) = File.expand_path(path, @root)

      def fetch(type, path, group)
        key = [type, resolve(path)]
        object = (@cache[key] ||= yield)
        (@owners[key] ||= Set.new) << group
        object
      end

      def build_sprite_sheet(relative_path, group)
        SpriteSheet.new(*composite_parts(relative_path, group))
      end

      def build_ui_atlas(relative_path, group)
        UiAtlas.new(*composite_parts(relative_path, group))
      end

      def composite_parts(relative_path, group)
        data = JSON.parse(read(relative_path, group), symbolize_names: true)
        [image(sibling(relative_path, data[:image]), group), data]
      end

      def sibling(relative_path, name)
        directory = File.dirname(relative_path)
        directory == '.' ? name : File.join(directory, name)
      end
    end
  end
end
