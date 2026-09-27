# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

# `RGame::Game::Configuration`: what `Game.new` builds from it, and what it
# refuses.
#
# `Game` names Engine, and this suite may not load it, so each game is built in
# a child process — see game_locales_spec.rb.
RSpec.describe 'RGame::Game configuration' do # rubocop:disable RSpec/DescribeClass -- the subject is Game, which this suite may not load
  let(:media) { Dir.mktmpdir }

  after { FileUtils.remove_entry(media) }

  # One probe per member: a value other than its default, an expression that
  # reads it back from the game, and what that expression should return. The
  # game runs one tick before any probe reads it, so the input backend has been
  # polled.
  def probes
    controls = 'RGame::Util::Controls'
    {
      width: ['96', 'game.viewports.width', 96],
      height: ['72', 'game.viewports.height', 72],
      scale_mode: [':integer', 'game.scale_mode', 'integer'],
      fullscreen: ['true', 'game.fullscreen?', true],
      media_root: [media.inspect, 'game.media_root', media],
      locales: ["'lang'", 'RGame::Engine::I18n.available', ['fr']],
      players: ['3', 'game.players.count', 3],
      device: ["#{controls}.gamepad(1)", "game.players.primary.device == #{controls}.gamepad(1)", true],
      input_map: ["RGame::Engine::InputMap.new(probe: { buttons: [#{controls}::KEY_P] })",
                  'game.players.primary.input_map.actions.include?(:probe)', true],
      seed: ['0xC0', 'game.random_source.seed', 0xC0],
      input: ['StubInput.new', 'configuration.input.polled', true],
      audio: ['StubAudio.new', 'game.audio.equal?(configuration.audio)', true]
    }
  end

  # Runs `body` in a child that defines a one-tick root and two stubs, and
  # returns what `body` returns, through JSON.
  def in_child(body)
    script = <<~RUBY
      require 'rgame/game'
      require 'json'

      class Root < RGame::Engine::Node2D
        def _update(_dt) = context.close
      end

      class StubInput
        attr_reader :polled

        def down?(_id, device: nil)
          @polled = true
          false
        end

        def axis(_id, device: nil) = 0.0
      end

      class StubAudio
        attr_accessor :assets
      end

      result = (#{body})
      puts JSON.generate(result)
    RUBY
    output, errors, status = ChildRuby.capture(script, env: { 'RGAME_SEED' => nil })
    raise "child failed (#{status}):\n#{output}#{errors}" unless status.success?

    JSON.parse(output.lines.last)
  end

  # The message of the ArgumentError `expression` raises, in a child.
  def refusal(expression)
    in_child("begin\n#{expression}\nnil\nrescue ArgumentError => e\ne.message\nend")
  end

  it 'opens 640x480 under :letterbox, with one player on the keyboard, by default' do
    body = <<~RUBY
      game = RGame::Game.new(root: Root.new)
      [game.width, game.height, game.scale_mode, game.players.count,
       game.players.primary.device == RGame::Util::Controls::KEYBOARD, game.media_root]
    RUBY

    expect(in_child(body)).to eq([640, 480, 'letterbox', 1, true, 'media'])
  end

  it 'probes every member' do
    expect(in_child('RGame::Game::Configuration.members').map(&:to_sym)).to eq(probes.keys)
  end

  it 'hands every member to the game' do
    FileUtils.mkdir_p(File.join(media, 'lang'))
    File.write(File.join(media, 'lang', 'fr.yml'), "fr:\n  title: Menu principal\n")
    members = probes.map { |name, (value, _, _)| "#{name}: #{value}" }.join(', ')
    reads = probes.map { |name, (_, read, _)| "#{name}: (#{read})" }.join(', ')
    body = <<~RUBY
      configuration = RGame::Game::Configuration.new(#{members})
      game = RGame::Game.new(root: Root.new, configuration:)
      game.start
      { #{reads} }
    RUBY

    expect(in_child(body)).to eq(probes.to_h { |name, (_, _, expected)| [name.to_s, expected] })
  end

  it 'refuses a misspelt member, naming it' do
    expect(refusal('RGame::Game::Configuration.new(widht: 96)')).to eq('unknown keyword: :widht')
  end

  it 'refuses a misspelt member in with, naming it' do
    expect(refusal('RGame::Game::Configuration.new.with(sead: 1)')).to eq('unknown keyword: :sead')
  end

  it 'refuses a member passed to Game.new as a keyword' do
    expect(refusal('RGame::Game.new(root: Root.new, width: 800)')).to eq('unknown keyword: :width')
  end
end
