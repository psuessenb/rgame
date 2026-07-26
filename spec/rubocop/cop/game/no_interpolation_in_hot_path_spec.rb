# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../rubocop/cop/game/no_interpolation_in_hot_path'

RSpec.describe RuboCop::Cop::Game::NoInterpolationInHotPath, :config do
  it 'flags string interpolation in draw (a per-frame allocation)' do
    expect_offense(<<~'RUBY', msg: described_class::MSG)
      def draw(renderer)
        renderer.text("Score: #{@score}", 10, 10)
                      ^^^^^^^^^^^^^^^^^^ %{msg}
      end
    RUBY
  end

  it 'flags interpolation in every lifecycle method, not just draw' do
    %i[update control on_update on_draw on_control].each do |method|
      expect_offense(<<~RUBY, msg: described_class::MSG)
        def #{method}(renderer)
          renderer.text("Score: \#{@score}", 10, 10)
                        ^^^^^^^^^^^^^^^^^^ %{msg}
        end
      RUBY
    end
  end

  it 'flags interpolation in a method tagged `# hot-path`' do
    expect_offense(<<~'RUBY', msg: described_class::MSG)
      # hot-path
      def label(renderer)
        renderer.text("Score: #{@score}", 10, 10)
                      ^^^^^^^^^^^^^^^^^^ %{msg}
      end
    RUBY
  end

  it 'does not flag a cached, pre-built string' do
    expect_no_offenses(<<~RUBY)
      def draw(renderer)
        renderer.text(@score_label, 10, 10)
      end
    RUBY
  end

  it 'does not flag a plain (non-interpolated) string literal' do
    expect_no_offenses(<<~RUBY)
      def draw(renderer)
        renderer.text("Game Over", 10, 10)
      end
    RUBY
  end

  it 'does not flag adjacent string literals concatenated by the parser' do
    expect_no_offenses(<<~'RUBY')
      def draw(renderer)
        renderer.text("Press " \
                      "Start", 10, 10)
      end
    RUBY
  end

  it 'does not flag interpolation in an ordinary (non per-frame) method' do
    expect_no_offenses(<<~'RUBY')
      def refresh_label
        @label = "Score: #{@score}"
      end
    RUBY
  end
end
