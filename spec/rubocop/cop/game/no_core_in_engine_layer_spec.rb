# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../rubocop/cop/game/no_core_in_engine_layer'

RSpec.describe RuboCop::Cop::Game::NoCoreInEngineLayer, :config do
  it 'registers an offense for naming a Core class' do
    expect_offense(<<~RUBY)
      def draw(_renderer)
        RGame::Core::Renderer.new
        ^^^^^^^^^^^^^^^^^^^^^ The engine layer must not name `RGame::Core`; receive the object and call it by method name instead.
      end
    RUBY
  end

  it 'registers one offense for the whole constant path, not one per segment' do
    expect_offense(<<~RUBY)
      RGame::Core::Input::KEY_LEFT
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ The engine layer must not name `RGame::Core`; receive the object and call it by method name instead.
    RUBY
  end

  it 'registers an offense for the short spelling that resolves through RGame' do
    # `RGame::Engine::Node` naming `Core::Image` gets `RGame::Core::Image`, so
    # this is the same offence — and the one that is easy to write by accident,
    # because it reads like a local reference.
    expect_offense(<<~RUBY)
      Core::Image.new(app, path)
      ^^^^^^^^^^^ The engine layer must not name `RGame::Core`; receive the object and call it by method name instead.
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
      ^^^^^^^^^^^ The engine layer must not name `RGame::Core`; receive the object and call it by method name instead.
    RUBY
  end

  it 'registers an offense for requiring the Core loader' do
    expect_offense(<<~RUBY)
      require 'rgame/core'
      ^^^^^^^^^^^^^^^^^^^^ The engine layer must not require `rgame/core` — that loads SDL/OpenGL and breaks headless specs.
    RUBY
  end

  it 'registers an offense for requiring the compiled extension directly' do
    expect_offense(<<~RUBY)
      require 'rgame/core_ext'
      ^^^^^^^^^^^^^^^^^^^^^^^^ The engine layer must not require `rgame/core_ext` — that loads SDL/OpenGL and breaks headless specs.
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
