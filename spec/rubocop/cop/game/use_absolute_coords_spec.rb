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

  describe 'the methods it covers' do
    it 'flags every relative coord read in on_draw — what a Node2D subclass overrides' do
      x = msg(abs: :@abs_x, rel: :@x, method: :on_draw)
      y = msg(abs: :@abs_y, rel: :@y, method: :on_draw)
      expect_offense(<<~RUBY, x: x, y: y)
        def on_draw(renderer, _view)
          renderer.a(@x)
                     ^^ %{x}
          renderer.b(@y)
                     ^^ %{y}
        end
      RUBY
    end

    it 'flags a relative coord read in draw — what a Component overrides' do
      expect_offense(<<~RUBY, y: msg(abs: :@abs_y, rel: :@y, method: :draw))
        def draw(renderer, _view)
          renderer.rect(@abs_x, @y, @width, @height)
                                ^^ %{y}
        end
      RUBY
    end

    it 'flags a relative coord read in on_update' do
      expect_offense(<<~RUBY, x: msg(abs: :@abs_x, rel: :@x, method: :on_update))
        def on_update(dt)
          @drift = @x * dt
                   ^^ %{x}
        end
      RUBY
    end

    it 'flags a relative coord read in on_control' do
      expect_offense(<<~RUBY, x: msg(abs: :@abs_x, rel: :@x, method: :on_control))
        def on_control(actions)
          @facing = actions.axis(:move_x) + @x
                                            ^^ %{x}
        end
      RUBY
    end

    it 'flags a relative coord read in draw_content, which runs once per viewport' do
      expect_offense(<<~RUBY, x: msg(abs: :@abs_x, rel: :@x, method: :draw_content))
        def draw_content(renderer, view)
          renderer.sprite(@sheet, @x, @abs_y)
                                  ^^ %{x}
        end
      RUBY
    end

    it 'does not flag reads outside the node lifecycle' do
      expect_no_offenses(<<~RUBY)
        def aabb
          [@x, @y, @x + @width, @y + @height]
        end
      RUBY
    end

    # The allocation guards extend their method list with a `# hot-path` comment;
    # this cop deliberately does not, because a tagged helper can belong to any
    # class and only a node has a relative transform to confuse with a resolved one.
    it 'does not flag a `# hot-path` helper, whose @x is nobody\'s parent-relative anything' do
      expect_no_offenses(<<~RUBY)
        # hot-path
        def offset_x
          @x - origin_x
        end
      RUBY
    end
  end

  describe 'what counts as a relative read' do
    it 'flags the attr_reader, which is the same read spelled without the @' do
      x = msg(abs: :abs_x, rel: :x, method: :on_draw)
      y = msg(abs: :abs_y, rel: :y, method: :on_draw)
      expect_offense(<<~RUBY, x: x, y: y)
        def on_draw(renderer, _view)
          renderer.line(x, y, x + width, y)
                        ^ %{x}
                           ^ %{y}
                              ^ %{x}
                                         ^ %{y}
        end
      RUBY
    end

    it 'flags the relative @angle, which a rotated parent has already been folded into' do
      expect_offense(<<~RUBY, a: msg(abs: :@abs_angle, rel: :@angle, method: :on_draw))
        def on_draw(renderer, _view)
          renderer.sprite(@sheet, @abs_x, @abs_y, angle: @angle)
                                                         ^^^^^^ %{a}
        end
      RUBY
    end

    it 'does not flag a coordinate belonging to somebody else' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, view)
          renderer.rect(@abs_x - view.x, @abs_y - view.camera.y, @width, @height)
        end
      RUBY
    end

    it 'does not flag a local or a parameter named x' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, _view)
          x = @abs_x + @width
          @cells.each { |y| renderer.line(x, y, x, y + 1) }
        end
      RUBY
    end

    it 'does not flag assignments — a node may reposition itself in parent space' do
      expect_no_offenses(<<~RUBY)
        def on_update(dt)
          @x = 10
          @y += dt
          self.angle += dt
        end
      RUBY
    end

    it 'does not flag the resolved @abs_* transform' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, _view)
          renderer.nine_slice(:t, @abs_x, @abs_y, @width, @height, angle: @abs_angle)
        end
      RUBY
    end

    it 'does not flag @z, which orders a node against its siblings and resolves to nothing' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, _view)
          renderer.rect(@abs_x, @abs_y, @width, @height, z: @z)
        end
      RUBY
    end

    it 'does not flag unrelated names that merely start with x/y/z' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, _view)
          renderer.text(@xs, @y_label, @zoom, x_offset, angle_of(:north))
        end
      RUBY
    end
  end
end
