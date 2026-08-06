# frozen_string_literal: true

# The game object a headless scene is given as its context.
#
#   node.context = FakeGame.new
#   node.enter_tree
#
#   expect(node.context.assets.lookups).to eq([[:sheet, 'hero.json']])
#
# `RGame::Game` is what a live tree gets as `root.context`, and it is the seam
# through which a node reaches the platform — the asset manager, the renderer,
# the sound device — without any of that being threaded through its
# constructor. The engine layer may not name a `RGame::Core` class, so it only
# ever asks that object for those pieces by method name, which is precisely what
# lets this stand in its place with no window and no SDL in the process.
#
# Everything it hands out is itself a stand-in, built by default, so a spec that
# only needs a live tree says `FakeGame.new` and a spec that wants to assert on
# one part passes that part in.
#
# It answers the seams the engine layer actually uses, and stops there. When a
# node starts asking context for something new, add it here at the same time —
# a fake that answers questions the real `RGame::Game` does not is drift in the
# more dangerous direction, since a spec would pass against something no game
# can provide.
class FakeGame
  attr_reader :assets, :renderer, :audio, :width, :height

  def initialize(assets: FakeAssets.new, renderer: nil, audio: FakeAudio.new,
                 width: 640, height: 480)
    @assets = assets
    # `RGame::Core::Renderer.new(app)` resolves an unregistered id through the
    # app's own asset manager, so the renderer built here shares this game's —
    # otherwise a scene that draws by path would resolve on attach and fail on
    # the very next line, at draw. An injected renderer is left exactly as it
    # was handed over.
    @renderer = renderer || FakeRenderer.new(assets: assets)
    @audio = audio
    @width = width
    @height = height
  end
end
