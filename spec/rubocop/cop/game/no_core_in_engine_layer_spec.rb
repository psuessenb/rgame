# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../lib/rgame/rubocop/cop/game/no_core_in_engine_layer'

RSpec.describe RuboCop::Cop::Game::NoCoreInEngineLayer, :config do
  it 'registers an offense for naming a Core class' do
    expect_offense(<<~RUBY)
      def draw(_renderer)
        RGame::Core::Renderer.new
        ^^^^^^^^^^^^^^^^^^^^^ Headless code must not name `RGame::Core`; receive the object and call it by method name instead.
      end
    RUBY
  end

  it 'registers one offense for the whole constant path, not one per segment' do
    expect_offense(<<~RUBY)
      RGame::Core::Input::KEY_LEFT
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Headless code must not name `RGame::Core`; receive the object and call it by method name instead.
    RUBY
  end

  it 'registers an offense for the short spelling that resolves through RGame' do
    # `RGame::Engine::Node` naming `Core::Image` gets `RGame::Core::Image`, so
    # this is the same offence — and the one that is easy to write by accident,
    # because it reads like a local reference.
    expect_offense(<<~RUBY)
      module RGame
        module Engine
          Core::Image.new(app, path)
          ^^^^^^^^^^^ Headless code must not name `RGame::Core`; receive the object and call it by method name instead.
        end
      end
    RUBY
  end

  it 'registers an offense for the short spelling in a class opened through RGame' do
    expect_offense(<<~RUBY)
      class RGame::Engine::Sprite
        Core::Image
        ^^^^^^^^^^^ Headless code must not name `RGame::Core`; receive the object and call it by method name instead.
      end
    RUBY
  end

  # Outside RGame a bare `Core` is the project's own constant, which a game is
  # free to have.
  it 'accepts the short spelling outside RGame' do
    expect_no_offenses(<<~RUBY)
      class Root < RGame::Engine::Node2D
        Core::Rules.new
      end
    RUBY
  end

  it 'accepts a constant that merely starts with the same letters' do
    expect_no_offenses(<<~RUBY)
      CoreData.load
      Physics::Core.step(dt)
    RUBY
  end

  it 'registers an offense for the bare module' do
    expect_offense(<<~RUBY)
      RGame::Core
      ^^^^^^^^^^^ Headless code must not name `RGame::Core`; receive the object and call it by method name instead.
    RUBY
  end

  it 'registers an offense for requiring the Core loader' do
    expect_offense(<<~RUBY)
      require 'rgame/core'
      ^^^^^^^^^^^^^^^^^^^^ Headless code must not require `rgame/core` — that loads SDL/OpenGL and breaks headless specs.
    RUBY
  end

  it 'registers an offense for requiring the compiled extension directly' do
    expect_offense(<<~RUBY)
      require 'rgame/core_ext'
      ^^^^^^^^^^^^^^^^^^^^^^^^ Headless code must not require `rgame/core_ext` — that loads SDL/OpenGL and breaks headless specs.
    RUBY
  end

  it 'registers an offense for requiring the game entry point, which loads Core too' do
    expect_offense(<<~RUBY)
      require 'rgame/game'
      ^^^^^^^^^^^^^^^^^^^^ Headless code must not require `rgame/game` — that loads SDL/OpenGL and breaks headless specs.
    RUBY
  end

  it 'accepts duck-typed calls on a renderer it was handed' do
    expect_no_offenses(<<~RUBY)
      def draw(renderer)
        renderer.sprite(:hero, 0, 0, @world_x, @world_y)
      end
    RUBY
  end

  it 'accepts RGame::Util, which is exactly what the engine may hold' do
    expect_no_offenses(<<~RUBY)
      @grid = RGame::Util::Tensor.new(4, 4, 4)
      require 'rgame'
    RUBY
  end

  it 'accepts an unrelated constant that merely ends in Core' do
    expect_no_offenses(<<~RUBY)
      MyGame::Core.new
    RUBY
  end
end
