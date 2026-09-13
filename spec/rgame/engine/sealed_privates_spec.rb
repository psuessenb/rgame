# frozen_string_literal: true

RSpec.describe RGame::Engine::SealedPrivates do
  # A base class of its own, so the rules are pinned without leaning on which
  # private methods Node2D happens to have today.
  let(:base) do
    Class.new do
      extend RGame::Engine::SealedPrivates

      def run = machinery + seam

      unsealed :seam

      private

      def machinery = 1
      def seam = 10
    end
  end

  describe 'a subclass replacing a private method of the base' do
    it 'raises when the method is defined' do
      expect { Class.new(base) { def machinery = 2 } }.to raise_error(NameError, /#machinery would replace/)
    end

    it 'names the method on the error' do
      error = begin
        Class.new(base) { def machinery = 2 }
      rescue NameError => e
        e
      end
      expect(error.name).to eq(:machinery)
    end

    it 'raises however the method is private in the subclass' do
      expect { Class.new(base) { private def machinery = 2 } }.to raise_error(NameError)
    end

    it 'raises for a method made by define_method' do
      expect { Class.new(base) { define_method(:machinery) { 2 } } }.to raise_error(NameError)
    end

    it 'raises for a method made by an attribute' do
      expect { Class.new(base) { attr_reader :machinery } }.to raise_error(NameError)
    end

    it 'raises a subclass further down, too' do
      middle = Class.new(base)
      expect { Class.new(middle) { def machinery = 2 } }.to raise_error(NameError)
    end
  end

  describe 'what it allows' do
    it 'lets a subclass override a public method' do
      expect(Class.new(base) { def run = 3 }.new.run).to eq(3)
    end

    it 'lets a subclass have private methods of its own' do
      expect(Class.new(base) { private def helper = 3 }.private_method_defined?(:helper)).to be(true)
    end

    it 'lets a subclass define initialize' do
      expect { Class.new(base) { def initialize(*) = super() } }.not_to raise_error
    end

    # A private hook meant for super — the seam the base declared.
    it 'lets a subclass override a private method the base unsealed' do
      subclass = Class.new(base) { def seam = super * 2 }
      expect(subclass.new.run).to eq(21)
    end

    # Only the base's own privates are sealed: a private hook written by one
    # engine subclass for the next, like TextButton#draw_foreground, stays usable.
    it 'lets a subclass override a private method of an intermediate class' do
      middle = Class.new(base) { private def step = 1 }
      expect { Class.new(middle) { def step = 2 } }.not_to raise_error
    end

    it 'lets the base itself be reopened' do
      expect { base.class_eval { private def machinery = 5 } }.not_to raise_error
    end
  end

  it 'refuses unsealed from a subclass, which could otherwise unseal anything' do
    expect { Class.new(base) { unsealed :machinery } }.to raise_error(NameError, /only/)
  end

  describe 'the classes a game subclasses' do
    it 'seals Node2D' do
      expect { Class.new(RGame::Engine::Node2D) { def draw_content(_renderer, _view) = nil } }
        .to raise_error(NameError, /Node2D#draw_content/)
    end

    # The documented seam examples/game_menu uses to hide a closed menu.
    it "leaves Node2D's draw_children open to override" do
      expect { Class.new(RGame::Engine::Node2D) { def draw_children(renderer, view) = (super unless @hidden) } }
        .not_to raise_error
    end

    it 'seals Component' do
      expect(RGame::Engine::Component.singleton_class).to include(described_class)
    end

    # A declaration naming nothing would unseal nothing and say nothing.
    [RGame::Engine::Node2D, RGame::Engine::Component].each do |klass|
      it "unseals only private methods #{klass} actually has" do
        expect(klass.unsealed_privates).to all(satisfy { |name| klass.private_method_defined?(name, false) })
      end
    end
  end
end
