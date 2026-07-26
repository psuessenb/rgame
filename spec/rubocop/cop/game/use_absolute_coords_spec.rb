# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../rubocop/cop/game/use_absolute_coords'

RSpec.describe RuboCop::Cop::Game::UseAbsoluteCoords, :config do
  # Build the exact message the cop emits, so the expectations track the constant
  # rather than duplicating its (long) text.
  def msg(abs:, rel:, method:)
    format(described_class::MSG, abs: abs, rel: rel, method: method)
  end

  it 'flags every relative coord read in draw (the render path)' do
    x = msg(abs: :@abs_x, rel: :@x, method: :draw)
    y = msg(abs: :@abs_y, rel: :@y, method: :draw)
    z = msg(abs: :@abs_z, rel: :@z, method: :draw)
    expect_offense(<<~RUBY, x: x, y: y, z: z)
      def draw(r)
        r.a(@x)
            ^^ %{x}
        r.b(@y)
            ^^ %{y}
        r.c(@z)
            ^^ %{z}
      end
    RUBY
  end

  it 'flags a relative coord read in update (the hit-test path)' do
    expect_offense(<<~RUBY, y: msg(abs: :@abs_y, rel: :@y, method: :update))
      def update(_dt, actions)
        @hovered = actions.pointer_y >= @y
                                        ^^ %{y}
      end
    RUBY
  end

  it 'flags a relative coord read in contains?' do
    expect_offense(<<~RUBY, x: msg(abs: :@abs_x, rel: :@x, method: :contains?))
      def contains?(px, _py)
        px >= @x
              ^^ %{x}
      end
    RUBY
  end

  it 'does not flag assignments — a node may reposition itself in parent space' do
    expect_no_offenses(<<~RUBY)
      def update(dt, _actions)
        @x = 10
        @y += dt
        @z -= 1
      end
    RUBY
  end

  it 'does not flag the resolved @abs_* coords' do
    expect_no_offenses(<<~RUBY)
      def draw(renderer)
        renderer.nine_slice(:t, @abs_x, @abs_y, @width, @height, z: @abs_z)
      end
    RUBY
  end

  it 'does not flag reads outside draw/update/contains?' do
    expect_no_offenses(<<~RUBY)
      def aabb
        [@x, @y, @x + @width, @y + @height]
      end
    RUBY
  end

  it 'does not flag unrelated ivars that merely start with x/y/z' do
    expect_no_offenses(<<~RUBY)
      def draw(renderer)
        renderer.text(@xs, @y_label, @zoom)
      end
    RUBY
  end
end
