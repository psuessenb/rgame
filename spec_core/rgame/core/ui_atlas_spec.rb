# frozen_string_literal: true

require 'json'

# Descriptor parsing and nothing else — what each entry *draws* is
# RGame::Core::NineSlice's business and is covered there, so this checks only
# what this class decides: which entries exist, what each one is cut from, and
# which scale wins.
RSpec.describe RGame::Core::UiAtlas do
  let(:image) { StubImage.new(64, 64) }
  let(:renderer) { FakeRenderer.new }

  def entry(overrides = {})
    { x: 0, y: 0, w: 12, h: 12, border: 4 }.merge(overrides)
  end

  def atlas(data)
    described_class.new(image, data)
  end

  # The scale a given element ends up drawing its corners at.
  def scale_of(nine_slice)
    nine_slice.draw(renderer, 0, 0, 40, 40)
    renderer.calls_to(:image_at).first.options[:scale_x]
  end

  describe '.new' do
    it 'builds one nine-slice per named element' do
      built = atlas(nine_slices: { button_idle: entry, panel: entry })

      expect(built.nine_slices.keys).to eq(%i[button_idle panel])
      expect(built.nine_slices.values).to all(be_a(RGame::Core::NineSlice))
    end

    it 'has no elements when the descriptor names none' do
      # An atlas of nothing is odd but not an error, and `nil` here would make
      # every caller branch.
      expect(atlas({}).nine_slices).to eq({})
    end

    it 'has no elements when the descriptor sets them to null' do
      # `"nine_slices": null` is what a hand-edited descriptor with the section
      # commented out actually contains, and it is not the same as an absent
      # key: `fetch(:nine_slices, {})` hands back the nil.
      expect(atlas(nine_slices: nil).nine_slices).to eq({})
    end

    it 'cuts each element from its own rectangle of the sheet' do
      built = atlas(nine_slices: { panel: entry(x: 20, y: 30) })
      built.nine_slices[:panel].draw(renderer, 0, 0, 12, 12)

      expect(renderer.calls_to(:image_at).map { |call| call.args.first.region })
        .to include([20, 30, 4, 4])
    end
  end

  describe 'scale' do
    it 'applies the sheet default to every element' do
      built = atlas(scale: 3, nine_slices: { panel: entry })

      expect(scale_of(built.nine_slices[:panel])).to eq(3)
    end

    it 'lets an element override the sheet default' do
      built = atlas(scale: 3, nine_slices: { panel: entry(scale: 2) })

      expect(scale_of(built.nine_slices[:panel])).to eq(2)
    end

    it 'defaults to 1 when the descriptor names no scale at all' do
      expect(scale_of(atlas(nine_slices: { panel: entry }).nine_slices[:panel])).to eq(1)
    end
  end

  describe 'borders' do
    # Normalising a uniform integer is NineSlice's job as of the port; what
    # this checks is that the descriptor's value reaches it untouched, in both
    # shapes a descriptor can write.
    it 'passes a uniform integer border through' do
      built = atlas(nine_slices: { panel: entry(border: 4) })
      built.nine_slices[:panel].draw(renderer, 0, 0, 12, 12)

      expect(renderer.calls_to(:image_at).map { |call| call.args.first.region })
        .to include([0, 0, 4, 4], [8, 8, 4, 4])
    end

    it 'passes a per-side border through' do
      built = atlas(nine_slices: { panel: entry(border: { left: 2, right: 6, top: 4, bottom: 4 }) })
      built.nine_slices[:panel].draw(renderer, 0, 0, 12, 12)

      expect(renderer.calls_to(:image_at).map { |call| call.args.first.region })
        .to include([0, 0, 2, 4], [6, 0, 6, 4])
    end
  end

  describe 'a malformed element' do
    it 'names the element it could not build' do
      # A descriptor holds a dozen of these. Without the name, the failure is
      # arithmetic from inside NineSlice and says nothing about which button is
      # wrong — and finding out means bisecting the JSON by hand.
      expect { atlas(nine_slices: { button_idle: entry.tap { |e| e.delete(:w) } }) }
        .to raise_error(ArgumentError, /ui atlas element :button_idle/)
    end

    it 'keeps the underlying complaint in the message' do
      expect { atlas(nine_slices: { panel: entry(border: 40) }) }
        .to raise_error(ArgumentError, /do not fit in a 12x12 rect/)
    end
  end

  describe '.load' do
    let(:app) { RGame::Core::App.new(width: 32, height: 32, caption: 'ui atlas spec') }

    def write_atlas(overrides = {})
      png = PngFixture.write(12, 12) { [255, 255, 255, 255] }
      data = { image: File.basename(png),
               nine_slices: { panel: { x: 0, y: 0, w: 12, h: 12, border: 4 } } }.merge(overrides)
      path = File.join(PngFixture.directory, "ui_#{PngFixture.next_id}.json")
      File.write(path, JSON.generate(data))
      path
    end

    it 'parses the descriptor and loads the sheet beside it' do
      built = described_class.load(app, write_atlas)

      expect(built.nine_slices[:panel]).to be_a(RGame::Core::NineSlice)
    end

    it 'raises when the descriptor names a sheet that is not there' do
      expect { described_class.load(app, write_atlas(image: 'missing.png')) }
        .to raise_error(RGame::Core::Image::LoadError, /missing\.png/)
    end

    it 'raises when the descriptor itself is not there' do
      expect { described_class.load(app, '/no/such/ui.json') }.to raise_error(Errno::ENOENT)
    end
  end

  describe 'through the asset manager' do
    let(:app) do
      RGame::Core::App.new(width: 32, height: 32, caption: 'ui atlas assets',
                           media_root: PngFixture.directory)
    end

    it 'shares its sheet with a standalone load of the same file' do
      png = PngFixture.write(12, 12) { [255, 255, 255, 255] }
      name = "ui_#{PngFixture.next_id}.json"
      File.write(File.join(PngFixture.directory, name),
                 JSON.generate(image: File.basename(png),
                               nine_slices: { panel: { x: 0, y: 0, w: 12, h: 12, border: 4 } }))

      app.assets.ui_atlas(name)
      cached = app.assets.size

      # Already there, so asking for it adds nothing: the atlas pulled its sheet
      # through the cache rather than loading a second copy of the same PNG.
      app.assets.image(File.basename(png))

      expect(app.assets.size).to eq(cached)
    end
  end
end
