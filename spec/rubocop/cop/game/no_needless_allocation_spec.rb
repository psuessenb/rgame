# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../rubocop/cop/game/no_needless_allocation'

RSpec.describe RuboCop::Cop::Game::NoNeedlessAllocation, :config do
  def receiver_msg(kind:, method:)
    format(described_class::MSG_RECEIVER, kind: kind, method: method)
  end

  def hot_path_msg(kind:)
    format(described_class::MSG_HOT_PATH, kind: kind)
  end

  describe 'a literal used as a method receiver (flagged anywhere)' do
    it 'flags an array literal built just to call a method on it' do
      expect_offense(<<~RUBY, msg: receiver_msg(kind: 'array', method: 'max'))
        def span(a, b)
          [a, b].max
          ^^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags a (parenthesised) range literal built just to iterate it' do
      expect_offense(<<~RUBY, msg: receiver_msg(kind: 'range', method: 'any?'))
        def solid?(a, b)
          (a..b).any? { |i| check(i) }
           ^^^^ %{msg}
        end
      RUBY
    end
  end

  describe 'any literal inside a per-frame method' do
    it 'flags an array literal returned from a lifecycle method' do
      expect_offense(<<~RUBY, msg: hot_path_msg(kind: 'array'))
        def on_draw(r)
          r.text([@a, @b])
                 ^^^^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags an array literal in a method tagged `# hot-path`' do
      expect_offense(<<~RUBY, msg: hot_path_msg(kind: 'array'))
        # hot-path
        def aabb(x, y)
          [x, y, @w, @h]
          ^^^^^^^^^^^^^^ %{msg}
        end
      RUBY
    end
  end

  describe 'allowed cases' do
    it 'allows an empty array (mutable-state seed)' do
      expect_no_offenses(<<~RUBY)
        def on_add
          @items = []
        end
      RUBY
    end

    it 'allows a frozen array literal' do
      expect_no_offenses(<<~RUBY)
        def draw(r)
          colors = [1, 2, 3].freeze
        end
      RUBY
    end

    it 'allows the right-hand side of a parallel assignment' do
      expect_no_offenses(<<~RUBY)
        def draw(r)
          a, b = 1, 2
        end
      RUBY
    end

    it 'allows a range used as a value (not iterated)' do
      expect_no_offenses(<<~RUBY)
        def initialize(interval: 1.0..3.0)
          @interval = interval
        end
      RUBY
    end

    it 'allows an array literal in an ordinary method that is not a receiver' do
      expect_no_offenses(<<~RUBY)
        def corners
          [@a, @b]
        end
      RUBY
    end
  end
end
