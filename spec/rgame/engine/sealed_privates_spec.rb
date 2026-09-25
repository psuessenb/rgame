# frozen_string_literal: true

RSpec.describe RGame::Engine::SealedPrivates do
  # A base class of its own, so the rules are pinned without leaning on which
  # methods Node2D happens to have today.
  let(:base) do
    Class.new do
      extend RGame::Engine::SealedPrivates

      def run = rgame_machinery + seam + rgame_shared

      protected

      def rgame_shared = 100

      private

      def rgame_machinery = 1
      def seam = 10
    end
  end

  describe 'a subclass replacing a prefixed method of the base' do
    it 'raises when the method is defined' do
      expect { Class.new(base) { def rgame_machinery = 2 } }.to raise_error(NameError, /#rgame_machinery would replace/)
    end

    it 'names the method on the error' do
      error = begin
        Class.new(base) { def rgame_machinery = 2 }
      rescue NameError => e
        e
      end
      expect(error.name).to eq(:rgame_machinery)
    end

    it 'raises for a protected one as well as a private one' do
      expect { Class.new(base) { def rgame_shared = 2 } }.to raise_error(NameError, /#rgame_shared/)
    end

    it 'raises however the method is private in the subclass' do
      expect { Class.new(base) { private def rgame_machinery = 2 } }.to raise_error(NameError)
    end

    it 'raises for a method made by define_method' do
      expect { Class.new(base) { define_method(:rgame_machinery) { 2 } } }.to raise_error(NameError)
    end

    it 'raises for a method made by an attribute' do
      expect { Class.new(base) { attr_reader :rgame_machinery } }.to raise_error(NameError)
    end

    it 'raises a subclass further down, too' do
      middle = Class.new(base)
      expect { Class.new(middle) { def rgame_machinery = 2 } }.to raise_error(NameError)
    end
  end

  describe 'what it allows' do
    # No prefix: a seam, meant for `super`.
    it 'lets a subclass override a private method with no prefix' do
      subclass = Class.new(base) { def seam = super * 2 }
      expect(subclass.new.run).to eq(121)
    end

    it 'lets a subclass override a public method' do
      expect(Class.new(base) { def run = 3 }.new.run).to eq(3)
    end

    it 'lets a subclass have methods the base does not seal' do
      expect(Class.new(base) { private def helper = 3 }.private_method_defined?(:helper)).to be(true)
    end

    it 'lets a subclass define initialize' do
      expect { Class.new(base) { def initialize(*) = super() } }.not_to raise_error
    end

    # Only the base's own methods are sealed: the convention belongs to the base
    # class, not to everything under it.
    it 'lets a subclass override a prefixed method of an intermediate class' do
      middle = Class.new(base) { private def rgame_step = 1 }
      expect { Class.new(middle) { def rgame_step = 2 } }.not_to raise_error
    end

    it 'lets the base itself be reopened' do
      expect { base.class_eval { private def rgame_machinery = 5 } }.not_to raise_error
    end
  end

  describe 'the attribute macros' do
    let(:node_class) do
      Class.new(RGame::Engine::Node2D) do
        sealed_reader :shade
        sealed_writer :tint
        sealed_accessor :glow

        def fill(shade:, tint:, glow:)
          @rgame_shade = shade
          @rgame_tint = tint
          @rgame_glow = glow
          self
        end
      end
    end

    it 'reads the prefixed ivar with sealed_reader' do
      expect(node_class.new.fill(shade: 1, tint: 2, glow: 3).shade).to eq(1)
    end

    it 'writes the prefixed ivar with sealed_writer' do
      node = node_class.new
      node.tint = 4
      expect(node.instance_variable_get(:@rgame_tint)).to eq(4)
    end

    it 'reads and writes the prefixed ivar with sealed_accessor' do
      node = node_class.new
      node.glow = 5
      expect([node.glow, node.instance_variable_get(:@rgame_glow)]).to eq([5, 5])
    end

    it 'makes the attribute public and its prefixed methods private' do
      expect([node_class.public_method_defined?(:shade), node_class.public_method_defined?(:tint=),
              node_class.private_method_defined?(:rgame_shade), node_class.private_method_defined?(:rgame_tint=)])
        .to eq([true, true, true, true])
    end

    # A bare `private` sets the visibility of what the class body defines, and
    # the macro defines its methods from inside a method of its own.
    it 'makes the attribute public below a bare private' do
      below_private = Class.new(RGame::Engine::Node2D) do
        private # rubocop:disable Lint/UselessAccessModifier -- the modifier the example shows has no effect

        sealed_reader :shade
      end
      expect(below_private.public_method_defined?(:shade)).to be(true)
    end

    it 'returns the names' do
      names = nil
      Class.new(RGame::Engine::Node2D) { names = sealed_accessor(:shade, :tint) }
      expect(names).to eq(%i[shade tint])
    end

    describe 'on the base class' do
      let(:attributed_base) do
        Class.new do
          extend RGame::Engine::SealedPrivates

          sealed_reader :shade
          sealed_writer :tint
          sealed_accessor :glow
        end
      end

      { sealed_reader: :rgame_shade, sealed_writer: :rgame_tint=, sealed_accessor: :rgame_glow }.each do |macro, sealed|
        it "seals the private method #{macro} makes" do
          expect { Class.new(attributed_base) { define_method(sealed) { |*| nil } } }
            .to raise_error(NameError, /##{Regexp.escape(sealed)} would replace/)
        end
      end
    end
  end

  it 'lists what it seals' do
    expect(base.sealed_methods).to contain_exactly(:rgame_machinery, :rgame_shared)
  end

  describe 'the classes a game subclasses' do
    it 'seals Node2D' do
      expect { Class.new(RGame::Engine::Node2D) { def rgame_draw_content(_renderer, _view) = nil } }
        .to raise_error(NameError, /Node2D#rgame_draw_content/)
    end

    # The documented seam examples/game_menu uses to hide a closed menu.
    it "seals Node2D's press gate" do
      expect { Class.new(RGame::Engine::Node2D) { def rgame_gate(actions) = actions } }
        .to raise_error(NameError, /Node2D#rgame_gate/)
    end

    it "seals the reader behind Node2D's opacity" do
      expect { Class.new(RGame::Engine::Node2D) { def rgame_opacity = 0 } }
        .to raise_error(NameError, /Node2D#rgame_opacity/)
    end

    it "leaves Node2D's draw_children open to override" do
      expect { Class.new(RGame::Engine::Node2D) { def draw_children(renderer, view) = (super unless @hidden) } }
        .not_to raise_error
    end

    it 'seals Component' do
      expect(RGame::Engine::Component.singleton_class).to include(described_class)
    end

    # The prefix is a decision, so a non-public method without one has to
    # have been meant as a seam. Adding one fails here until it is either renamed
    # or listed — which is where that decision gets made.
    {
      RGame::Engine::Node2D => %i[draw_children initialize],
      RGame::Engine::Component => %i[]
    }.each do |klass, seams|
      it "has no non-public method on #{klass} without the prefix but its seams" do
        non_public = klass.private_instance_methods(false) + klass.protected_instance_methods(false)
        expect(non_public.reject { |name| name.start_with?(described_class::PREFIX) }).to match_array(seams)
      end

      it "keeps every prefixed method on #{klass} non-public" do
        expect(klass.public_instance_methods(false).grep(/\Argame_/)).to be_empty
      end
    end
  end
end
