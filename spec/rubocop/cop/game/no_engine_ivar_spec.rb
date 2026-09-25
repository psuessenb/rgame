# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../lib/rgame/rubocop/cop/game/no_engine_ivar'

RSpec.describe RuboCop::Cop::Game::NoEngineIvar, :config do
  def message(name) = format(described_class::MSG, name: name)

  describe 'an engine ivar' do
    it 'flags a read' do
      expect_offense(<<~RUBY, msg: message('@rgame_opacity'))
        def _draw(renderer, _view)
          renderer.rect(0, 0, 4, 4, alpha: @rgame_opacity)
                                           ^^^^^^^^^^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags a write' do
      expect_offense(<<~RUBY, msg: message('@rgame_paused'))
        @rgame_paused = true
        ^^^^^^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags each compound assignment' do
      expect_offense(<<~RUBY, msg: message('@rgame_z'))
        @rgame_z += 1
        ^^^^^^^^ %{msg}
        @rgame_z ||= 0
        ^^^^^^^^ %{msg}
        @rgame_z &&= 2
        ^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags a target of a multiple assignment' do
      expect_offense(<<~RUBY, msg: message('@rgame_width'))
        @size, @rgame_width = 4, 8
               ^^^^^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags an ivar tested with defined?' do
      expect_offense(<<~RUBY, msg: message('@rgame_player'))
        defined?(@rgame_player)
                 ^^^^^^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags a literal Symbol given to instance_variable_get' do
      expect_offense(<<~RUBY, msg: message('@rgame_paused'))
        node.instance_variable_get(:@rgame_paused)
                                   ^^^^^^^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags a literal String given to instance_variable_set' do
      expect_offense(<<~RUBY, msg: message('@rgame_width'))
        node&.instance_variable_set('@rgame_width', 8)
                                    ^^^^^^^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags instance_variable_defined? and remove_instance_variable' do
      expect_offense(<<~RUBY, msg: message('@rgame_node'))
        instance_variable_defined?(:@rgame_node)
                                   ^^^^^^^^^^^^ %{msg}
        remove_instance_variable(:@rgame_node)
                                 ^^^^^^^^^^^^ %{msg}
      RUBY
    end
  end

  describe 'what it passes' do
    it 'passes an ivar that only starts with the same letters' do
      expect_no_offenses(<<~RUBY)
        @rgame = 1
        @rgamer_x += @rgame
      RUBY
    end

    it 'passes a method and a local named with the prefix' do
      expect_no_offenses(<<~RUBY)
        rgame_x = node.rgame_x
      RUBY
    end

    it 'passes a name built at runtime' do
      expect_no_offenses(<<~'RUBY')
        instance_variable_get(:"@rgame_#{name}")
      RUBY
    end

    it 'passes a literal given to another method' do
      expect_no_offenses(<<~RUBY)
        expect(node.instance_variables).to include(:@rgame_pulled_signal)
      RUBY
    end
  end
end
