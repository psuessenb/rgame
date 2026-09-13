# frozen_string_literal: true

require_relative '../../tools/strip_comments'

RSpec.describe CommentStripper do
  def strip(source) = described_class.strip(source)

  describe 'comments that are kept' do
    it 'keeps the shebang and magic comments' do
      source = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true

        x = 1
      RUBY

      expect(strip(source)).to eq(source)
    end

    it 'keeps the description above a class, a module and a built class' do
      source = <<~RUBY
        # A module.
        module Outer
          # A class.
          class Inner; end

          # A value.
          Point = Data.define(:x, :y)
        end
      RUBY

      expect(strip(source)).to eq(source)
    end

    it 'keeps the description above public methods of every kind' do
      source = <<~RUBY
        class Thing
          # An instance method.
          def a; end

          # A class method.
          def self.b; end

          # An attribute.
          attr_reader :c

          class << self
            # A singleton method.
            def d; end
          end
        end
      RUBY

      expect(strip(source)).to eq(source)
    end

    it 'keeps the description above a public DSL declaration in a class body' do
      source = <<~RUBY
        class Thing
          # Fires when hit.
          signal :on_hit, Signal.define(:other)

          Built = Class.new do
            # Fires when built.
            signal :on_built
          end
        end
      RUBY

      expect(strip(source)).to eq(source)
    end

    it 'keeps rubocop directives with the lines that continue their reason, and hot-path tags' do
      source = <<~RUBY
        class Thing
          private

          # hot-path
          # rubocop:disable Style/Foo -- a reason that
          # runs over two lines
          def a; end
          # rubocop:enable Style/Foo

          def b = 1 # rubocop:disable Style/Bar
        end
      RUBY

      expect(strip(source)).to eq(source)
    end

    it 'keeps the comment above a class_eval, and never touches its heredoc' do
      source = <<~RUBY
        Class.new do
          # For [:x] this generates: def x = 1
          class_eval(<<~CODE, __FILE__, __LINE__ + 1)
            # def x = 1
            def x = 1
          CODE
        end
      RUBY

      expect(strip(source)).to eq(source)
    end
  end

  describe 'comments that are deleted' do
    it 'deletes comments inside method bodies, and trailing ones' do
      expect(strip(<<~RUBY)).to eq(<<~RUBY)
        class Thing
          def a
            # explains
            x = '# not a comment' # trailing
            x
          end
        end
      RUBY
        class Thing
          def a
            x = '# not a comment'
            x
          end
        end
      RUBY
    end

    it 'deletes the description of private and protected methods, however they became so' do
      expect(strip(<<~RUBY)).to eq(<<~RUBY)
        class Thing
          # public
          def a; end

          # retracted
          def b; end
          private :b

          # inline
          private def c; end

          protected

          # protected
          def d; end
        end
      RUBY
        class Thing
          # public
          def a; end

          def b; end
          private :b

          private def c; end

          protected

          def d; end
        end
      RUBY
    end

    it 'deletes the description above a DSL-like call that declares nothing public' do
      expect(strip(<<~RUBY)).to eq(<<~RUBY)
        class Thing
          # constant
          private_constant :X

          def a
            # inside a method
            signal :on_hit
          end

          private

          # private
          signal :on_secret
        end
      RUBY
        class Thing
          private_constant :X

          def a
            signal :on_hit
          end

          private

          signal :on_secret
        end
      RUBY
    end

    it 'deletes a comment separated from its method by a blank line' do
      expect(strip(<<~RUBY)).to eq(<<~RUBY)
        class Thing
          # Section header

          def a; end
        end
      RUBY
        class Thing
          def a; end
        end
      RUBY
    end

    it 'deletes top-level method descriptions and =begin blocks' do
      expect(strip(<<~RUBY)).to eq(<<~RUBY)
        =begin
        a block
        =end
        # a script helper
        def helper; end
      RUBY
        def helper; end
      RUBY
    end
  end

  describe 'blank lines left behind' do
    it 'collapses the two blank lines a deleted comment sat between' do
      expect(strip("a = 1\n\n# gone\n\nb = 2\n")).to eq("a = 1\n\nb = 2\n")
    end

    it 'drops a blank line that would now hug the end of a body' do
      expect(strip("def a\n  x = 1\n\n  # gone\nend\n")).to eq("def a\n  x = 1\nend\n")
    end
  end

  it 'refuses a file it cannot parse' do
    expect { strip("def (\n") }.to raise_error(described_class::ParseError)
  end

  describe '.excluded?' do
    %w[examples/a/main.rb spec/x_spec.rb spec_core/y.rb tools/drive/examples/z.rb].each do |path|
      it "excludes #{path}" do
        expect(described_class.excluded?(path)).to be(true)
      end
    end

    it 'includes everything else' do
      expect(described_class.excluded?('lib/rgame/engine/specimen.rb')).to be(false)
    end
  end
end
