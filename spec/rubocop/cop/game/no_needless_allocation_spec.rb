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
    # Deliberately not `.max`: that one compiles to `opt_newarray_send` and builds
    # no Array, so it belongs among the allowed cases below rather than here.
    it 'flags an array literal built just to call a method on it' do
      expect_offense(<<~RUBY, msg: receiver_msg(kind: 'array', method: 'sum'))
        def span(a, b)
          [a, b].sum
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

    # These four are the sends the VM rewrites to `opt_newarray_send`, which reads
    # the operands off the stack and builds no Array. Measured: 0 allocations over
    # 200,000 calls. Flagging them put this cop in direct conflict with
    # Style/MinMaxComparison, which asks for exactly this form.
    it 'allows the sends the VM optimises into opt_newarray_send' do
      expect_no_offenses(<<~RUBY)
        def draw(r)
          a = [@x, LIMIT].min
          b = [@x, LIMIT].max
          c = [@x, @y].hash
          d = [@x, @y].include?(@z)
        end
      RUBY
    end

    it 'allows the optimised sends with more than two elements' do
      expect_no_offenses(<<~RUBY)
        def draw(r)
          [@a, @b, @c].max
        end
      RUBY
    end

    # The optimisation is narrow, and the cop has to be too, or it stops catching
    # the allocations it exists for.
    it 'still flags an optimised send once it takes a block' do
      expect_offense(<<~RUBY, msg: receiver_msg(kind: 'array', method: 'min'))
        def draw(r)
          [@a, @b].min { |x, y| x <=> y }
          ^^^^^^^^ %{msg}
        end
      RUBY
    end

    it 'still flags an optimised send once it takes an argument' do
      expect_offense(<<~RUBY, msg: receiver_msg(kind: 'array', method: 'min'))
        def draw(r)
          [@a, @b].min(1)
          ^^^^^^^^ %{msg}
        end
      RUBY
    end

    it 'still flags a send the VM does not optimise' do
      expect_offense(<<~RUBY, msg: receiver_msg(kind: 'array', method: 'sum'))
        def draw(r)
          [@a, @b].sum
          ^^^^^^^^ %{msg}
        end
      RUBY
    end

    it 'still flags a splat, which is assembled at runtime and does allocate' do
      expect_offense(<<~RUBY, msg: receiver_msg(kind: 'array', method: 'min'))
        def draw(r)
          [*@a, @b].min
          ^^^^^^^^^ %{msg}
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
