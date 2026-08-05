# frozen_string_literal: true

require 'json'

# Almost all of this runs against injected loaders — the caching, the path
# resolution and the reference counting are pure bookkeeping, and the loaders
# are injectable precisely so that they can be checked with no window, no GL
# context and no files. A handful of examples at the end use the real ones, to
# confirm that what is being cached is what a game would get.
RSpec.describe RGame::Core::AssetManager do
  # Counts what it was asked to load, so "loaded once" is a number rather than
  # an inference.
  def counting_loader
    calls = []
    [lambda { |path|
      calls << path
      yield(path)
    }, calls]
  end

  let(:image_loader) { counting_loader { |_path| StubImage.new(64, 32) } }
  let(:loaders) { { image: image_loader.first, read: ->(path) { descriptors.fetch(path) } } }
  let(:descriptors) { {} }

  # `app: nil` throughout this section: the injected loaders never touch it, and
  # saying so is better than opening a window that nothing looks at.
  def manager(root: '/media', loaders: self.loaders)
    described_class.new(root: root, app: nil, loaders: loaders)
  end

  describe 'paths' do
    it 'resolves every path against the root' do
      manager.image('sprites/hero.png')

      expect(image_loader.last).to eq(['/media/sprites/hero.png'])
    end

    it 'uses an absolute path as it stands' do
      # A loader can hand one back — the tile-map loader's tileset image comes
      # out of a .tsx that was itself found on disk — and joining it onto the
      # root would give <root>/<root>/tiles.png.
      manager.image('/elsewhere/tiles.png')

      expect(image_loader.last).to eq(['/elsewhere/tiles.png'])
    end

    it 'treats two spellings of one path as one entry' do
      assets = manager
      assets.image('sprites/hero.png')
      assets.image('sprites/../sprites/./hero.png')
      assets.image('/media/sprites/hero.png')

      expect(image_loader.last.length).to eq(1)
      expect(assets.size).to eq(1)
    end
  end

  describe 'caching' do
    it 'loads a path once and hands back the same object' do
      assets = manager
      first = assets.image('hero.png')

      expect(assets.image('hero.png')).to equal(first)
      expect(image_loader.last.length).to eq(1)
    end

    it 'keys by type as well as path' do
      # image('x') and read('x') are different assets that happen to share a
      # name, and collapsing them would hand a caller a String where it wanted
      # an image.
      descriptors['/media/x'] = 'raw bytes'
      assets = manager

      expect(assets.image('x')).to be_a(StubImage)
      expect(assets.read('x')).to eq('raw bytes')
    end

    it 'does not cache a load that failed' do
      # Tagging the owner *after* the load is what makes a retry a clean retry,
      # rather than leaving a permanently half-registered asset behind.
      attempts = 0
      flaky = lambda do |path|
        attempts += 1
        raise RGame::Core::Image::LoadError, path if attempts == 1

        StubImage.new(1, 1)
      end
      assets = manager(loaders: { image: flaky })

      expect { assets.image('hero.png') }.to raise_error(RGame::Core::Image::LoadError)
      expect(assets.image('hero.png')).to be_a(StubImage)
      expect(assets.size).to eq(1)
    end

    it 'leaves no owner behind when a load fails' do
      # Tagging before the load rather than after looks harmless — the cache
      # entry is still absent — but the phantom owner never goes away, so the
      # asset a *later* group successfully loads can never be released: a group
      # that got nothing is recorded as holding it forever.
      attempts = 0
      flaky = lambda do |path|
        attempts += 1
        raise RGame::Core::Image::LoadError, path if attempts == 1

        StubImage.new(1, 1)
      end
      assets = manager(loaders: { image: flaky })

      expect { assets.image('hero.png', :level1) }.to raise_error(RGame::Core::Image::LoadError)
      assets.image('hero.png', :level2)
      assets.release(:level2)

      expect(assets.size).to be_zero
    end
  end

  describe 'groups' do
    it 'releases what only that group held' do
      assets = manager
      assets.preload(:level1, image: ['a.png', 'b.png'])
      assets.release(:level1)

      expect(assets.size).to be_zero
    end

    it 'keeps an asset a second group still holds' do
      assets = manager
      assets.image('shared.png', :level1)
      assets.image('shared.png', :level2)
      assets.release(:level1)

      expect(assets.size).to eq(1)
    end

    it 'tags a cache hit with the new group, not only a fresh load' do
      # The failure this catches is subtle and one-way: level 2 reuses level 1's
      # asset, level 1 releases, and level 2's asset vanishes underneath it.
      assets = manager
      assets.image('shared.png', :level1)
      first = assets.image('shared.png', :level2)
      assets.release(:level1)

      expect(assets.image('shared.png', :level2)).to equal(first)
      expect(image_loader.last.length).to eq(1)
    end

    it 'keeps an ungrouped asset through every release' do
      assets = manager
      assets.image('ui.png')
      assets.release(:level1)
      assets.release(:level2)

      expect(assets.size).to eq(1)
    end

    it 'refuses to release the ungrouped ones by naming the sentinel' do
      # Otherwise this empties every ungrouped asset's owner set and drops the
      # lot — the opposite of what PERMANENT promises, and silent.
      expect { manager.release(described_class::PERMANENT) }
        .to raise_error(ArgumentError, /#clear, not #release/)
    end

    it 'drops even the permanent ones on clear' do
      assets = manager
      assets.image('ui.png')

      expect(assets.clear.size).to be_zero
    end

    it 'refuses a preload manifest naming a type it has no accessor for' do
      # `assets.preload(:level1, images: [...])` — a plural typo. Without this
      # it is a NoMethodError from inside a public_send, which names the typo
      # but not what was being attempted.
      expect { manager.preload(:level1, images: ['a.png']) }
        .to raise_error(ArgumentError, /unknown asset type :images/)
    end
  end

  describe '#add_loader' do
    it 'teaches it a new type and gives it an accessor' do
      assets = manager
      assets.add_loader(:level) { |path| "level at #{path}" }

      expect(assets.level('one.json')).to eq('level at /media/one.json')
    end

    it 'caches and groups an added type like any other' do
      loader, calls = counting_loader { |path| path }
      assets = manager
      assets.add_loader(:level, &loader)

      2.times { assets.level('one.json', :chapter1) }
      assets.release(:chapter1)

      expect(calls.length).to eq(1)
      expect(assets.size).to be_zero
    end

    it 'does not answer to a type it has not been taught' do
      # `Renderer#resolve_asset` asks exactly this before offering an id, so
      # that an unregistered tilemap id is a KeyError naming the id rather than
      # a NoMethodError from in here.
      assets = manager

      expect(assets).not_to respond_to(:tilemap)
      assets.add_loader(:tilemap) { |path| path }
      expect(assets).to respond_to(:tilemap)
    end

    it 'teaches only the manager it was called on' do
      # Two games in one process, or a spec and the app it is testing: a type
      # one manager knows is not a type another one does.
      taught = manager
      untaught = manager
      taught.add_loader(:level) { |path| path }

      expect(untaught).not_to respond_to(:level)
    end

    it 'lists the types it knows' do
      expect(manager.types).to contain_exactly(:image, :read)
    end
  end

  describe 'composites' do
    let(:descriptors) do
      { '/media/sheets/hero.json' => JSON.generate(image: 'hero.png',
                                                   frame_width: 16, frame_height: 16) }
    end

    it 'assembles a sheet from a cached descriptor and a cached image' do
      expect(manager.sheet('sheets/hero.json')).to be_a(RGame::Core::SpriteSheet)
    end

    it 'resolves the descriptor image next to the descriptor' do
      manager.sheet('sheets/hero.json')

      expect(image_loader.last).to eq(['/media/sheets/hero.png'])
    end

    it 'shares its backing image with a standalone load of the same file' do
      # One decode and one upload between the two, which is the whole reason
      # composites go through the cache rather than loading their own parts.
      assets = manager
      sheet = assets.sheet('sheets/hero.json')
      assets.image('sheets/hero.png')

      expect(sheet).to be_a(RGame::Core::SpriteSheet)
      expect(image_loader.last.length).to eq(1)
    end

    it 'releases the backing image with the composite group' do
      assets = manager
      assets.sheet('sheets/hero.json', :level1)
      assets.release(:level1)

      expect(assets.size).to be_zero
    end
  end

  describe 'the real loaders' do
    let(:app) do
      RGame::Core::App.new(width: 32, height: 32, caption: 'assets spec',
                           media_root: PngFixture.directory)
    end

    it 'loads an image into the app that owns it' do
      png = File.basename(PngFixture.write(4, 2) { [255, 255, 255, 255] })

      expect(app.assets.image(png)).to be_a(RGame::Core::Image)
    end

    it 'loads a sound through the app device' do
      sounds = RGame::Core::App.new(width: 8, height: 8, caption: 'sounds',
                                    media_root: File.dirname(AudioFixture::OGG))

      expect(sounds.assets.sound(File.basename(AudioFixture::OGG))).to be_a(RGame::Core::Sample)
    end

    it 'raises the loader error, naming the file' do
      expect { app.assets.image('nope.png') }
        .to raise_error(RGame::Core::Image::LoadError, /nope\.png/)
    end
  end

  describe 'RGame::Core::App#assets' do
    let(:app) do
      RGame::Core::App.new(width: 32, height: 32, caption: 'assets spec',
                           media_root: PngFixture.directory)
    end

    it 'is built once and memoised' do
      expect(app.assets).to equal(app.assets)
    end

    it 'is rooted at the app media_root' do
      png = File.basename(PngFixture.write(2, 2) { [255, 255, 255, 255] })

      expect(app.assets.image(png)).to be_a(RGame::Core::Image)
    end

    it 'defaults media_root when the app did not name one' do
      other = RGame::Core::App.new(width: 8, height: 8, caption: 'default root')

      expect(other.media_root).to eq('media')
    end

    it 'opens no sound device to load an image' do
      # The reason the loaders reach `app.audio` inside the proc rather than
      # capturing it: a game that draws and never plays anything should not have
      # a sound card open.
      allow(app).to receive(:audio).and_call_original
      app.assets.image(File.basename(PngFixture.write(2, 2) { [255, 255, 255, 255] }))

      expect(app).not_to have_received(:audio)
    end
  end
end
