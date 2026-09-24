# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../lib/rgame/rubocop/cop/game/no_block_exit_in_hot_path'

RSpec.describe RuboCop::Cop::Game::NoBlockExitInHotPath, :config do
  def msg(keyword) = format(described_class::MSG, keyword: keyword)

  describe 'on a per-frame path' do
    it 'flags a return that leaves a block' do
      expect_offense(<<~RUBY, msg: msg(:return))
        def _draw(renderer, _view)
          @items.each { |item| return if item.hidden? }
                               ^^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags a break that leaves a block' do
      expect_offense(<<~RUBY, msg: msg(:break))
        def _update(dt)
          @timers.each do |timer|
            break if timer.done?
            ^^^^^ %{msg}
          end
        end
      RUBY
    end

    it 'flags a break out of `loop`, which is a block too' do
      expect_offense(<<~RUBY, msg: msg(:break))
        def _update(dt)
          loop { break if step }
                 ^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags a return from a lambda' do
      expect_offense(<<~RUBY, msg: msg(:return))
        def _update(dt)
          @check = ->(x) { return x if x }
                           ^^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags a return that leaves a block through a `while` inside it' do
      expect_offense(<<~RUBY, msg: msg(:return))
        # hot-path
        def first_solid(rows)
          rows.each do |row|
            col = 0
            while col < row.size
              return col if row[col]
              ^^^^^^ %{msg}
              col += 1
            end
          end
        end
      RUBY
    end

    it 'flags an `it` block and a numbered one' do
      expect_offense(<<~RUBY, first: msg(:return), second: msg(:return))
        def _draw(renderer, _view)
          @a.each { return it if it }
                    ^^^^^^ %{first}
          @b.each { return _1 if _1 }
                    ^^^^^^ %{second}
        end
      RUBY
    end
  end

  describe 'what leaves for free' do
    it 'allows `next`, which stays inside its block' do
      expect_no_offenses(<<~RUBY)
        def _draw(renderer, _view)
          @items.each { |item| next if item.hidden? }
        end
      RUBY
    end

    it 'allows a return from the method itself' do
      expect_no_offenses(<<~RUBY)
        def _update(dt)
          return if @paused

          @items.each { |item| item.update(dt) }
        end
      RUBY
    end

    it 'allows a return or break inside a `while` loop' do
      expect_no_offenses(<<~RUBY)
        def _update(dt)
          index = 0
          while index < @items.size
            break if @items[index].done?
            return if @items[index].stop?

            index += 1
          end
        end
      RUBY
    end

    it 'allows a break from a `while` loop inside a block' do
      expect_no_offenses(<<~RUBY)
        def _update(dt)
          @rows.each do |row|
            index = 0
            while index < row.size
              break if row[index]

              index += 1
            end
          end
        end
      RUBY
    end

    it 'allows a method defined inside a block to return' do
      expect_no_offenses(<<~RUBY)
        def _update(dt)
          @items.each do |item|
            def item.done?
              return true if @finished

              false
            end
          end
        end
      RUBY
    end
  end

  describe 'off the per-frame path' do
    it 'allows a return from a block in a method that does not run every frame' do
      expect_no_offenses(<<~RUBY)
        def load(path)
          @entries.each { |entry| return entry if entry.path == path }
        end
      RUBY
    end
  end

  # rgame's own lib/ is the library a game calls into from its hot path, and no
  # method there can know whether it is called every frame.
  describe 'in a file every method of which counts' do
    let(:cop_config) { { 'EveryMethodIn' => ['lib/engine/**/*.rb'] } }

    it 'flags a block exit in any method' do
      expect_offense(<<~RUBY, 'lib/engine/tile_map.rb', msg: msg(:return))
        def frame_tile(tile, elapsed)
          @frames.each { |shown, ends| return shown if elapsed < ends }
                                       ^^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags one outside any method, in a `define_method` block' do
      expect_offense(<<~RUBY, 'lib/engine/accessors.rb', msg: msg(:return))
        define_method(:ready?) { return false unless @loaded }
                                 ^^^^^^ %{msg}
      RUBY
    end

    it 'leaves a file the option does not name to the per-frame methods' do
      expect_no_offenses(<<~RUBY, 'lib/loader/tiled.rb')
        def load(path)
          @entries.each { |entry| return entry if entry.path == path }
        end
      RUBY
    end
  end
end
