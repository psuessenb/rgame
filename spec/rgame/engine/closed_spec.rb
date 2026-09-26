# frozen_string_literal: true

# rubocop:disable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration, RSpec/RemoveConst -- the guard is
# about the class and module keywords, so these examples write them, and remove what a refused definition leaves behind
RSpec.describe RGame::Engine::Closed do
  # A game's module, as the convention writes it. stub_const takes it away again.
  before do
    stub_const('ClosedSpecGame', Module.new)
    ClosedSpecGame.const_set(:Engine, RGame::Engine)
    ClosedSpecGame.const_set(:Util, RGame::Util)
    ClosedSpecGame.const_set(:Components, RGame::Engine::Components)
  end

  # A refused definition has already happened when the guard raises. Undo it,
  # so rgame's classes leave each example as they entered it.
  after do
    components = RGame::Engine::Components
    components.send(:remove_const, :ClosedSpecSpin) if components.const_defined?(:ClosedSpecSpin, false)
    RGame::Engine.send(:remove_const, :ClosedSpecCar) if RGame::Engine.const_defined?(:ClosedSpecCar, false)
    timer = components::Timer
    timer.send(:remove_method, :closed_spec_probe) if timer.method_defined?(:closed_spec_probe, false)
    engine_timer = RGame::Engine::Timer
    engine_timer.send(:remove_method, :closed_spec_probe) if engine_timer.method_defined?(:closed_spec_probe, false)
    RGame::Util.singleton_class.send(:remove_method, :closed_spec_probe) if RGame::Util.respond_to?(:closed_spec_probe)
  end

  it 'closes the classes and modules under RGame::Engine and RGame::Util' do
    closed = [RGame::Engine, RGame::Engine::Timer, RGame::Engine::Components::Timer, RGame::Engine::UI::Menu,
              RGame::Engine::Scene::Rooms, RGame::Util, RGame::Util::Color]

    expect(closed.reject { described_class.closed?(it) }).to be_empty
  end

  describe "a module of the game's own named like rgame's" do
    it 'refuses a class written inside it, naming the file and the line' do
      expect do
        module ClosedSpecGame
          module Components
            class ClosedSpecSpin < Engine::Component
              def spin = nil
            end
          end
        end
      end.to raise_error(NameError, /closed_spec\.rb:\d+ would change RGame::Engine::Components::ClosedSpecSpin/)
    end

    # Components::Timer and Engine::Timer are two classes. The game's own
    # `Components` module reopens the first, and its `Timer` is rgame's.
    it 'refuses a method on a class of rgame it reopens, such as Components::Timer' do
      expect do
        module ClosedSpecGame
          module Components
            class Timer < Engine::Component
              def closed_spec_probe = nil
            end
          end
        end
      end.to raise_error(NameError, /would change RGame::Engine::Components::Timer#closed_spec_probe/)
    end

    it 'refuses a singleton method on Util' do
      expect do
        module ClosedSpecGame
          module Util
            def self.closed_spec_probe = nil
          end
        end
      end.to raise_error(NameError, /would change RGame::Util\.closed_spec_probe/)
    end

    it 'refuses a class written inside Engine itself' do
      expect do
        module ClosedSpecGame
          module Engine
            class ClosedSpecCar
              def drive = nil
            end
          end
        end
      end.to raise_error(NameError, /would change RGame::Engine::ClosedSpecCar/)
    end
  end

  describe 'what stays open' do
    it "leaves a game's own class alone, even one named like rgame's" do
      expect do
        module ClosedSpecGame
          class Timer < Engine::Component
            LIMIT = 3
            def _update(_dt) = nil
          end
        end
      end.not_to raise_error

      expect(ClosedSpecGame::Timer).not_to equal(RGame::Engine::Components::Timer)
    end

    it 'lets a spec stub a method on an rgame module' do
      allow(RGame::Engine::I18n).to receive(:locale).and_return(:xx)

      expect(RGame::Engine::I18n.locale).to eq(:xx)
    end

    it 'lets define_method through, which says what it reopens' do
      RGame::Engine::Timer.define_method(:closed_spec_probe) { :probe }

      expect(RGame::Engine::Timer.new(1.0).closed_spec_probe).to eq(:probe)
    end
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration, RSpec/RemoveConst
