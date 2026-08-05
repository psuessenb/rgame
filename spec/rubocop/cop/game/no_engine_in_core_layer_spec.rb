# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../rubocop/cop/game/no_engine_in_core_layer'

RSpec.describe RuboCop::Cop::Game::NoEngineInCoreLayer, :config do
  it 'registers an offense for naming an Engine class' do
    expect_offense(<<~RUBY)
      def self.load(app, path)
        Engine::TileMap.parse(File.read(path))
        ^^^^^^^^^^^^^^^ RGame::Core must not name `Engine`; take the object and call it by method name, and let the glue layer wire the two together.
      end
    RUBY
  end

  it 'registers an offense for the namespaced spelling' do
    # Both, because the engine layer is `Engine::` until it is ported and
    # `RGame::Engine::` afterwards — and the interim is exactly when a Core
    # class would reach for it.
    expect_offense(<<~RUBY)
      RGame::Engine::Tileset.parse(text, firstgid: 1)
      ^^^^^^^^^^^^^^^^^^^^^^ RGame::Core must not name `RGame::Engine`; take the object and call it by method name, and let the glue layer wire the two together.
    RUBY
  end

  it 'registers one offense for the whole constant path, not one per segment' do
    expect_offense(<<~RUBY)
      Engine::Scene::SceneStack
      ^^^^^^^^^^^^^^^^^^^^^^^^^ RGame::Core must not name `Engine`; take the object and call it by method name, and let the glue layer wire the two together.
    RUBY
  end

  it 'registers an offense for the bare module' do
    expect_offense(<<~RUBY)
      Engine
      ^^^^^^ RGame::Core must not name `Engine`; take the object and call it by method name, and let the glue layer wire the two together.
    RUBY
  end

  it 'registers an offense for requiring the engine layer' do
    expect_offense(<<~RUBY)
      require 'rgame/engine'
      ^^^^^^^^^^^^^^^^^^^^^^ RGame::Core must not require `rgame/engine` — Engine is built on top of Core, not the other way round.
    RUBY
  end

  it 'registers an offense for requiring it relatively' do
    expect_offense(<<~RUBY)
      require_relative '../engine/tile_map'
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ RGame::Core must not require `../engine/tile_map` — Engine is built on top of Core, not the other way round.
    RUBY
  end

  it 'accepts a duck-typed map it was handed' do
    expect_no_offenses(<<~RUBY)
      def initialize(map, tiles)
        @columns = map.width
        @tiles = tiles
      end
    RUBY
  end

  it 'accepts Core and Util constants' do
    expect_no_offenses(<<~RUBY)
      RGame::Core::Image.new(app, path)
      RGame::Util::Color::WHITE
    RUBY
  end

  it 'accepts a constant that merely ends in Engine' do
    # `PhysicsEngine` is not the engine layer, and a cop that could not tell
    # them apart would be one people learn to disable.
    expect_no_offenses(<<~RUBY)
      PhysicsEngine.step(dt)
      RGame::Core::PhysicsEngine
    RUBY
  end

  it 'accepts requiring something that merely contains the word' do
    expect_no_offenses(<<~RUBY)
      require 'engineering/units'
    RUBY
  end
end
