# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../rubocop/cop/game/no_literal_text'

RSpec.describe RuboCop::Cop::Game::NoLiteralText, :config do
  describe 'a literal label' do
    it 'flags a String literal drawn with text' do
      expect_offense(<<~RUBY, msg: described_class::MSG)
        renderer.text('Press Space', 12, 12)
                      ^^^^^^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags an interpolated String, which is a literal with words in it too' do
      expect_offense(<<~'RUBY', msg: described_class::MSG)
        renderer.text("Lives: #{lives}", 12, 34)
                      ^^^^^^^^^^^^^^^^^ %{msg}
      RUBY
    end

    it 'flags a String literal measured with text_width' do
      expect_offense(<<~RUBY, msg: described_class::MSG)
        width = renderer.text_width('Play')
                                    ^^^^^^ %{msg}
      RUBY
    end

    it 'flags it on any receiver, outside a draw method as well' do
      expect_offense(<<~RUBY, msg: described_class::MSG)
        def draw
          @renderer.text('Score', 10, 10)
                         ^^^^^^^ %{msg}
        end
      RUBY
    end

    it 'flags a safe-navigation call' do
      expect_offense(<<~RUBY, msg: described_class::MSG)
        renderer&.text('Score', 10, 10)
                       ^^^^^^^ %{msg}
      RUBY
    end
  end

  describe 'what it passes' do
    it 'passes a Text in an ivar' do
      expect_no_offenses('renderer.text(@help, 12, 12)')
    end

    it 'passes a constant, which it cannot see into' do
      expect_no_offenses('renderer.text(LEFT_CHEVRON, left, y)')
    end

    it 'passes a method call' do
      expect_no_offenses('renderer.text(@score.with(score: @points), 12, 10)')
    end

    it 'passes a text call with no arguments' do
      expect_no_offenses('node.text')
    end

    it 'passes a String literal that is not the label' do
      expect_no_offenses("renderer.text(@help, 12, 12, font: 'mono')")
    end
  end
end
