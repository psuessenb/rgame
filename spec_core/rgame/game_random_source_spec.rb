# frozen_string_literal: true

require 'json'

# `RGame::Game`'s random source: the seed it picks, and the root it mounts on.
#
# `Game` names Engine, and this suite may not load it, so the game is built in
# a child process — see game_locales_spec.rb. The child is also what lets an
# example set `RGAME_SEED` without changing it for the rest of the suite.
RSpec.describe 'RGame::Game random source' do # rubocop:disable RSpec/DescribeClass -- the subject is Game, which this suite may not load
  # Builds a Game with `options`, under `RGAME_SEED=env_seed` or with it unset,
  # and returns what `body` returns against it as `game`, through JSON.
  def with_game(body, env_seed: nil, options: '')
    script = <<~RUBY
      require 'rgame/game'
      require 'json'

      class Root < RGame::Engine::Node2D
        def _update(_dt) = context.close
      end

      game = RGame::Game.new(root: Root.new, width: 64, height: 48, caption: 'random source spec'#{options})
      result = (#{body})
      game.close
      puts JSON.generate(result)
    RUBY
    output, errors, status = ChildRuby.capture(script, env: { 'RGAME_SEED' => env_seed })
    raise "child failed (#{status}):\n#{output}#{errors}" unless status.success?

    JSON.parse(output.lines.last)
  end

  it 'seeds from seed:' do
    expect(with_game('game.random_source.seed', options: ', seed: 0xC0')).to eq(0xC0)
  end

  it 'seeds from RGAME_SEED over seed:' do
    expect(with_game('game.random_source.seed', env_seed: '7', options: ', seed: 0xC0')).to eq(7)
  end

  it 'picks a fresh seed with neither, and reads it back' do
    seeds = Array.new(2) { with_game('game.random_source.seed') }

    expect(seeds.uniq.size).to eq(2)
  end

  it 'refuses an RGAME_SEED that is not an Integer' do
    expect { with_game('game.random_source.seed', env_seed: 'abc') }.to raise_error(/invalid value for Integer/)
  end

  it 'mounts the source on the root when the game starts' do
    body = 'game.start; game.root.system(RGame::Engine::Components::RandomSource).equal?(game.random_source)'

    expect(with_game(body)).to be(true)
  end
end
