# frozen_string_literal: true

RSpec.describe RGame::Engine::Hooks do
  let(:node) { RGame::Engine::Node2D }
  let(:component) { RGame::Engine::Component }

  it 'guards Node2D and Component' do
    expect([node, component].map(&:singleton_class)).to all(include(described_class))
  end

  describe '.hooks' do
    it 'lists what a node subclass may override' do
      expect(Class.new(node).hooks).to eq(%i[_control _draw _enter_tree _exit_tree _update])
    end

    it 'lists what a component subclass may override' do
      expect(Class.new(component).hooks).to eq(%i[_attach _control _detach _draw _sweep_freed _update])
    end

    it 'includes the hooks an engine subclass declares' do
      expect(Class.new(RGame::Engine::UI::Button).hooks).to include(:_gain_focus, :_lose_focus)
    end
  end

  describe 'what it refuses' do
    it 'raises on a misspelled hook, naming it and listing the hooks' do
      stub_const('Hop', Class.new(node))
      expect { Hop.class_eval { def _updte(dt) = dt } }
        .to raise_error(NameError,
                        /\AHop#_updte is no hook of RGame::Engine::Node2D.*_enter_tree, _exit_tree, _update\./)
    end

    it "raises on a component's hook in a node" do
      expect { Class.new(node) { def _attach = nil } }.to raise_error(NameError, /#_attach is no hook/)
    end

    it 'raises on a helper named with a leading _, however it is made' do
      expect { Class.new(component) { private def _helper = nil } }.to raise_error(NameError)
      expect { Class.new(component) { attr_accessor :_count } }.to raise_error(NameError)
    end

    it 'says how to declare a new hook' do
      expect { Class.new(node) { def _die = nil } }.to raise_error(NameError, /declare a new hook first: hook :_die\./)
    end

    it 'refuses to declare a hook whose name has no _' do
      expect { Class.new(node) { hook :die } }.to raise_error(ArgumentError, "hook :die: a hook's name starts with _")
    end
  end

  describe 'what it allows' do
    it "lets a subclass override its ancestor's hook" do
      expect { Class.new(node) { def _update(dt) = dt } }.not_to raise_error
    end

    it 'lets a class define a hook it declared, and its subclasses override it' do
      declaring = Class.new(node) do
        hook :_die
        def _die = :base
      end

      expect(Class.new(declaring) { def _die = :override }.new._die).to eq(:override)
    end

    it 'lets a subclass override a hook an engine subclass declared' do
      expect { Class.new(RGame::Engine::UI::Button) { def _gain_focus = nil } }.not_to raise_error
    end

    it 'lets a subclass name a method with no leading _' do
      expect { Class.new(node) { private def helper = nil } }.not_to raise_error
    end
  end
end
