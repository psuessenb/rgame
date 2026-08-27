# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../rubocop/cop/game/draw_in_local_space'

RSpec.describe RuboCop::Cop::Game::DrawInLocalSpace, :config do
  # Build the exact message the cop emits, so the expectations track the constant
  # rather than duplicating its (long) text.
  def msg(name:, method:, distance:)
    format(described_class::MSG, name: name, method: method, distance: distance)
  end

  def world(name, method) = msg(name: name, method: method, distance: 'on the map')
  def local(name, method) = msg(name: name, method: method, distance: 'inside its parent')

  describe 'the world transform' do
    it 'flags a bare world_x read in on_draw' do
      expect_offense(<<~RUBY, x: world(:world_x, :on_draw))
        def on_draw(renderer, _view)
          renderer.rect(world_x, 0, width, height)
                        ^^^^^^^ %{x}
        end
      RUBY
    end

    it 'flags the ivar spelling too' do
      expect_offense(<<~RUBY, y: world(:world_y, :on_draw))
        def on_draw(renderer, _view)
          renderer.text(@label, 0, @world_y)
                                   ^^^^^^^^ %{y}
        end
      RUBY
    end

    # The one legitimate world read on this path, and what makes it legitimate is
    # that it is somebody else's coordinate, asked for by name.
    it 'does not flag a component asking its node for a cull box' do
      expect_no_offenses(<<~RUBY)
        def draw(renderer, view)
          return if culled?(view, node.world_x, node.world_y, node.width, node.height)

          renderer.image(@id, 0, 0)
        end
      RUBY
    end
  end

  describe 'the parent-relative transform' do
    # The subtler half: `x` looks harmless and is off by less, which is exactly
    # what makes it survive a spec written at the origin.
    it 'flags a bare x read in on_draw' do
      x = local(:x, :on_draw)
      y = local(:y, :on_draw)
      expect_offense(<<~RUBY, x: x, y: y)
        def on_draw(renderer, _view)
          renderer.rect(x, y, width, height)
                        ^ %{x}
                           ^ %{y}
        end
      RUBY
    end

    it 'flags the storage ivar, whose short name it is' do
      expect_offense(<<~RUBY, a: local(:angle, :on_draw))
        def on_draw(renderer, _view)
          renderer.sprite(@sheet, 0, 0, angle: @rel_angle)
                                               ^^^^^^^^^^ %{a}
        end
      RUBY
    end

    it 'does not flag a size, which is not a position' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, _view)
          renderer.rect(0, 0, width, height)
        end
      RUBY
    end

    it 'does not flag somebody else transform' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, view)
          renderer.text(@label, view.width - PAD, camera.y)
        end
      RUBY
    end

    it 'does not flag a local or a block parameter named x' do
      expect_no_offenses(<<~RUBY)
        def on_draw(renderer, _view)
          x = @columns * CELL
          @rows.each { |y| renderer.line(0, y, x, y) }
        end
      RUBY
    end
  end

  describe 'the methods it covers' do
    it 'flags draw_content, which runs once per viewport' do
      expect_offense(<<~RUBY, x: world(:world_x, :draw_content))
        def draw_content(renderer, view)
          renderer.sprite(@sheet, world_x, 0)
                                  ^^^^^^^ %{x}
        end
      RUBY
    end

    it 'flags a Component draw, which is on the same path' do
      expect_offense(<<~RUBY, x: local(:x, :draw))
        def draw(renderer, _view)
          renderer.rect(x, 0, 8, 8)
                        ^ %{x}
        end
      RUBY
    end

    # `update` is deliberately unpoliced. A node moving itself in its parent's
    # frame wants `x`; one measuring a distance to something else wants
    # `world_x`; and the cop cannot tell those apart. Guessing would make the
    # commonest movement idiom in the engine an offence.
    it 'does not flag update, where both spellings are legitimate' do
      expect_no_offenses(<<~RUBY)
        def on_update(dt)
          self.x = x + (@speed * dt)
          @target = @world.nearest(world_x, world_y, @range)
        end
      RUBY
    end

    it 'does not flag a method outside the draw path' do
      expect_no_offenses(<<~RUBY)
        def aabb
          [world_x, world_y, world_x + width, world_y + height]
        end
      RUBY
    end
  end
end
