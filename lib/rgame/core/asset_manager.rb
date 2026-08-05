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
    # Every accessor takes a path **relative to the media root** and returns the
    # same object every time, so a file asked for twice is read, decoded and
    # uploaded once. That is the whole point: loading stops being scattered
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
      # Owner of every ungrouped load. Never released, only cleared.
      PERMANENT = :__permanent__

      # `app` is what images are loaded into and where the audio device comes
      # from; `root` is what every path is resolved against.
      def initialize(root:, app:, loaders: nil)
        @root = root
        @app = app
        @loaders = loaders || default_loaders
        @cache = {}
        @owners = {} # cache key => Set of groups holding it
      end

      # Each takes a path relative to the media root.
      def image(path, group = PERMANENT) = leaf(:image, path, group)
      def sound(path, group = PERMANENT) = leaf(:sound, path, group)
      def song(path, group = PERMANENT) = leaf(:song, path, group)
      def read(path, group = PERMANENT) = leaf(:read, path, group)

      # A sprite sheet, assembled through the cache: its descriptor is a cached
      # `read` and its image a cached `image`, so nothing is loaded twice.
      def sheet(path, group = PERMANENT)
        fetch(:sheet, path, group) { build_sprite_sheet(path, group) }
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
        # Without this, `release(PERMANENT)` would empty every ungrouped
        # asset's owner set and drop the lot — the exact opposite of what the
        # constant's name promises, and silent. It is only reachable by naming
        # the sentinel, so saying what to use instead beats ignoring the call.
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

      # The app is reached through the ivar rather than captured, so
      # `app.audio` is not called until a sound is actually asked for — loading
      # an image opens no sound device.
      def default_loaders
        {
          image: ->(path) { Image.new(@app, path) },
          sound: ->(path) { @app.audio.sample(path) },
          song: ->(path) { @app.audio.song(path) },
          read: ->(path) { File.read(path) }
        }.freeze
      end

      def leaf(type, path, group)
        fetch(type, path, group) { @loaders.fetch(type).call(File.join(@root, path)) }
      end

      # Memoise on miss, then record the owning group — so a cache *hit* under a
      # new group is tagged too. Tagging after the load rather than before is
      # what leaves a failed load with no owner behind it, which makes a retry a
      # clean retry rather than a permanently half-registered asset.
      def fetch(type, path, group)
        key = [type, path]
        object = (@cache[key] ||= yield)
        (@owners[key] ||= Set.new) << group
        object
      end

      def build_sprite_sheet(relative_path, group)
        data = JSON.parse(read(relative_path, group), symbolize_names: true)
        SpriteSheet.new(image(sibling(relative_path, data[:image]), group), data)
      end

      # A path next to `relative_path`, still relative to the root — so a
      # descriptor's image lands on the same `[:image, path]` cache key a
      # standalone `image` of that file would.
      def sibling(relative_path, name)
        directory = File.dirname(relative_path)
        directory == '.' ? name : File.join(directory, name)
      end
    end
  end
end
