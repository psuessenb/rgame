# frozen_string_literal: true

RSpec.describe RGame::Engine::SealedPrivates do
  # A base class of its own, so the rules are pinned without leaning on which
  # methods Node2D happens to have today.
  let(:base) do
    Class.new do
      extend RGame::Engine::SealedPrivates

      def run = _machinery + seam + _shared

      protected

      def _shared = 100

      private

      def _machinery = 1
      def seam = 10
    end
  end

  describe 'a subclass replacing an underscored method of the base' do
    it 'raises when the method is defined' do
      expect { Class.new(base) { def _machinery = 2 } }.to raise_error(NameError, /#_machinery would replace/)
    end

    it 'names the method on the error' do
      error = begin
        Class.new(base) { def _machinery = 2 }
      rescue NameError => e
        e
      end
      expect(error.name).to eq(:_machinery)
    end

    it 'raises for a protected one as well as a private one' do
      expect { Class.new(base) { def _shared = 2 } }.to raise_error(NameError, /#_shared/)
    end

    it 'raises however the method is private in the subclass' do
      expect { Class.new(base) { private def _machinery = 2 } }.to raise_error(NameError)
    end

    it 'raises for a method made by define_method' do
      expect { Class.new(base) { define_method(:_machinery) { 2 } } }.to raise_error(NameError)
    end

    it 'raises for a method made by an attribute' do
      expect { Class.new(base) { attr_reader :_machinery } }.to raise_error(NameError)
    end

    it 'raises a subclass further down, too' do
      middle = Class.new(base)
      expect { Class.new(middle) { def _machinery = 2 } }.to raise_error(NameError)
    end
  end

  describe 'what it allows' do
    # No underscore: a seam, meant for `super`.
    it 'lets a subclass override a private method with no underscore' do
      subclass = Class.new(base) { def seam = super * 2 }
      expect(subclass.new.run).to eq(121)
    end

    it 'lets a subclass override a public method' do
      expect(Class.new(base) { def run = 3 }.new.run).to eq(3)
    end

    it 'lets a subclass have underscored methods the base does not' do
      expect(Class.new(base) { private def _helper = 3 }.private_method_defined?(:_helper)).to be(true)
    end

    it 'lets a subclass define initialize' do
      expect { Class.new(base) { def initialize(*) = super() } }.not_to raise_error
    end

    # Only the base's own methods are sealed: the convention belongs to the base
    # class, not to everything under it.
    it 'lets a subclass override an underscored method of an intermediate class' do
      middle = Class.new(base) { private def _step = 1 }
      expect { Class.new(middle) { def _step = 2 } }.not_to raise_error
    end

    it 'lets the base itself be reopened' do
      expect { base.class_eval { private def _machinery = 5 } }.not_to raise_error
    end
  end

  it 'lists what it seals' do
    expect(base.sealed_methods).to contain_exactly(:_machinery, :_shared)
  end

  describe 'the classes a game subclasses' do
    it 'seals Node2D' do
      expect { Class.new(RGame::Engine::Node2D) { def _draw_content(_renderer, _view) = nil } }
        .to raise_error(NameError, /Node2D#_draw_content/)
    end

    # The documented seam examples/game_menu uses to hide a closed menu.
    it "leaves Node2D's draw_children open to override" do
      expect { Class.new(RGame::Engine::Node2D) { def draw_children(renderer, view) = (super unless @hidden) } }
        .not_to raise_error
    end

    it 'seals Component' do
      expect(RGame::Engine::Component.singleton_class).to include(described_class)
    end

    # The underscore is a decision, so a non-public method without one has to
    # have been meant as a seam. Adding one fails here until it is either renamed
    # or listed — which is where that decision gets made.
    {
      RGame::Engine::Node2D => %i[draw_children initialize],
      RGame::Engine::Component => %i[]
    }.each do |klass, seams|
      it "has no non-public method on #{klass} without an underscore but its seams" do
        non_public = klass.private_instance_methods(false) + klass.protected_instance_methods(false)
        expect(non_public.reject { |name| name.start_with?('_') }).to match_array(seams)
      end

      it "keeps every underscored method on #{klass} non-public" do
        expect(klass.public_instance_methods(false).grep(/\A_/)).to be_empty
      end
    end
  end
end
