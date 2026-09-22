# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::ActionTrigger do
  subject(:trigger) { described_class.new(fire: 0.22) }

  let(:fired) { [] }

  before { trigger.on_triggered { |action| fired << action } }

  def hold(action) = RGame::Engine::Actions.new(held: { action => true })

  describe '#control' do
    it 'emits the action name when the action is held and the cooldown is ready' do
      trigger._control(hold(:fire))
      expect(fired).to eq([:fire])
    end

    it 'does not emit when the action is not held' do
      trigger._control(RGame::Engine::Actions.new(held: { fire: false }))
      expect(fired).to be_empty
    end

    it 'rate-limits repeats within the cooldown window' do
      trigger._control(hold(:fire)) # fires
      trigger._update(0.1)          # still on cooldown (< 0.22)
      trigger._control(hold(:fire)) # blocked
      expect(fired).to eq([:fire])
    end

    it 'fires again once the cooldown has elapsed' do
      trigger._control(hold(:fire))
      trigger._update(0.25) # past the 0.22 cooldown
      trigger._control(hold(:fire))
      expect(fired).to eq(%i[fire fire])
    end
  end
end
