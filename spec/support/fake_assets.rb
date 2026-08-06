# frozen_string_literal: true

# An asset manager that loads nothing and hands back stand-ins.
#
#   assets = FakeAssets.new(sheets: { 'hero.json' => FakeSheet.new(...) })
#   node.context = FakeGame.new(assets: assets)
#
#   expect(assets.lookups).to eq([[:sheet, 'hero.json']])
#
# The engine layer reaches the real `RGame::Core::AssetManager` through
# `node.root.context.assets` and calls it by method name — `assets.sheet(path)`
# is the only one so far, from `Engine::Components::AnimatedSprite`. So a spec
# needs an object that answers those accessors with something usable, with no
# window, no GL context and no files on disk.
#
# What it deliberately does *not* model is the real manager's caching, path
# normalisation and groups. Nothing in the engine layer can observe any of it: a
# node asks for an asset and gets one, and whether it came from a cache is the
# manager's business. `#lookups` records what was asked for instead, which is
# the part a scene's behaviour can actually be wrong about.
#
# Note there is no `nine_slice` accessor, and that is not an omission — the real
# manager has no such loader either. A nine-slice id names an element of an
# atlas rather than a file, so `Renderer#lookup` finds it registered or not at
# all, and `respond_to?(:nine_slice)` being false is what keeps it from being
# offered here. See RGame::Core::Renderer#nine_slice.
class FakeAssets
  # The owner of every ungrouped load, as in the real manager. It is accepted
  # and ignored: a fake caches nothing, so there is nothing for a group to hold
  # or release. It exists so the accessors below have the real arity — a
  # verifying double of this class must reject a call the real manager rejects.
  PERMANENT = :__permanent__

  # Every [type, path] pair asked for, in order, hits included — a scene that
  # resolves an asset once per frame instead of once on attach is visible here
  # and nowhere else.
  attr_reader :lookups

  def initialize(sheets: {}, images: {}, tilemaps: {}, sounds: {}, songs: {}, reads: {})
    @assets = {
      sheet: sheets, image: images, tilemap: tilemaps,
      sound: sounds, song: songs, read: reads
    }
    @lookups = []
  end

  def sheet(path, _group = PERMANENT) = fetch(:sheet, path)
  def image(path, _group = PERMANENT) = fetch(:image, path)
  def tilemap(path, _group = PERMANENT) = fetch(:tilemap, path)
  def sound(path, _group = PERMANENT) = fetch(:sound, path)
  def song(path, _group = PERMANENT) = fetch(:song, path)
  def read(path, _group = PERMANENT) = fetch(:read, path)

  # The types this manager can hand out. The real one answers the same list —
  # its four built-ins plus `sheet`, and `tilemap` from the loader `RGame::Game`
  # installs — because a fake game is what this stands behind.
  def types = @assets.keys

  # How many assets it holds. Only for a spec that wants to say "and nothing
  # else was registered"; a scene has no reason to ask, just as with the real
  # manager's #size.
  def size = @assets.each_value.sum(&:size)

  private

  # Refuses what the real manager refuses, and in the same two ways.
  #
  # A non-String path crosses into `File.expand_path` there and raises
  # TypeError, so a symbol that was meant to be a registration id fails here
  # too rather than quietly resolving. And an unregistered path is a file that
  # is not on disk, which is `Errno::ENOENT` from the loader — not nil, which
  # would surface much later as a NoMethodError inside whatever was handed it.
  # See CLAUDE.md, "A fake must refuse what the real thing refuses".
  def fetch(type, path)
    raise TypeError, "no implicit conversion of #{path.class} into String" unless path.is_a?(String)

    @lookups << [type, path]
    @assets.fetch(type).fetch(path) do
      raise Errno::ENOENT, "no #{type} registered for #{path.inspect}"
    end
  end
end
