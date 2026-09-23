# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Button do
  # Records every focus change it is told about, which is the hook a button with
  # a focus sound or animation would override.
  let(:recording_class) do
    Class.new(described_class) do
      def changes = @changes ||= []
      def _gain_focus = changes << true
      def _lose_focus = changes << false
    end
  end

  let(:button) { described_class.new(label: 'Resume') }

  describe '#state' do
    it 'is idle when nothing else is true' do
      expect(button.state).to eq(:idle)
    end

    it 'is focused once it has focus' do
      button.focused = true
      expect(button.state).to eq(:focused)
    end

    it 'is pressed while a press is held on it' do
      button.focused = true
      button.press
      expect(button.state).to eq(:pressed)
    end

    # A :press activation stays visible for PRESS_FEEDBACK even once focus has
    # moved on, so the rule cannot require focus.
    it 'is pressed without focus while its feedback runs' do
      pressing = described_class.new(activate_on: :press)
      pressing.focused = true
      pressing.press
      pressing.release
      pressing.focused = false
      expect(pressing.state).to eq(:pressed)
    end

    it 'is disabled whatever else is true' do
      button.focused = true
      button.press
      button.enabled = false
      expect(button.state).to eq(:disabled)
    end
  end

  describe 'activate_on: :release, the default' do
    let(:fired) { [] }

    before do
      button.on_activated { fired << :activated }
      button.focused = true
    end

    it 'is the default' do
      expect(button.activate_on).to eq(:release)
    end

    it 'holds on the press and activates nothing yet' do
      expect([button.press, button.pressed?, fired]).to eq([nil, true, []])
    end

    it 'activates on the release' do
      button.press
      expect([button.release, button.pressed?, fired]).to eq([button, false, [:activated]])
    end

    it 'activates nothing on a release it did not see pressed' do
      expect([button.release, fired]).to eq([nil, []])
    end

    it 'lets go without activating when focus moves away while held' do
      button.press
      button.focused = false
      button.release
      expect([button.pressed?, fired]).to eq([false, []])
    end

    it 'shows no feedback after a release, the hold having been the feedback' do
      button.press
      button.release
      expect(button.state).to eq(:focused)
    end
  end

  describe 'activate_on: :press' do
    let(:button) { described_class.new(activate_on: :press) }
    let(:fired) { [] }

    before do
      button.on_activated { fired << :activated }
      button.focused = true
    end

    it 'activates on the press' do
      expect([button.press, fired]).to eq([button, [:activated]])
    end

    it 'does not activate again on the release' do
      button.press
      button.release
      expect(fired).to eq([:activated])
    end

    # Time enters through update(dt): a spec advances it by passing seconds.
    describe 'the pressed feedback after a tap' do
      before do
        button.press
        button.release
      end

      it 'stays pressed for PRESS_FEEDBACK' do
        button.update(described_class::PRESS_FEEDBACK / 2)
        expect(button.state).to eq(:pressed)
      end

      it 'returns to focused once PRESS_FEEDBACK has passed' do
        2.times { button.update(described_class::PRESS_FEEDBACK / 2) }
        expect(button.state).to eq(:focused)
      end

      it 'does not run down while the button is paused' do
        button.paused = true
        button.update(described_class::PRESS_FEEDBACK)
        button.paused = false
        expect(button.state).to eq(:pressed)
      end
    end

    it 'stays pressed past PRESS_FEEDBACK for as long as it is held' do
      button.press
      button.update(described_class::PRESS_FEEDBACK * 3)
      expect(button.state).to eq(:pressed)
    end

    it 'drops a press whose release it never saw, feedback included' do
      button.press
      button.cancel_press
      expect([button.state, fired]).to eq([:focused, [:activated]])
    end
  end

  # A hold remembers which source started it, so the two sources on one button
  # cannot end each other's press.
  describe 'press sources' do
    let(:fired) { [] }

    before do
      button.on_activated { fired << :activated }
      button.focused = true
    end

    it 'presses from confirm when no source is named' do
      button.press
      expect([button.release(:hotkey), button.pressed?]).to eq([nil, true])
    end

    it 'activates a hotkey press at once under activate_on: :release' do
      expect([button.press(:hotkey), fired]).to eq([button, [:activated]])
    end

    it 'activates nothing on a hotkey release' do
      button.press(:hotkey)
      expect([button.release(:hotkey), fired]).to eq([nil, [:activated]])
    end

    it 'ignores a press from one source while the other holds it' do
      button.press(:confirm)
      expect([button.press(:hotkey), fired]).to eq([nil, []])
    end

    it 'ends no hold another source started' do
      button.press(:hotkey)
      button.release(:confirm)
      button.cancel_press(:confirm)
      expect(button.pressed?).to be(true)
    end

    it 'drops a hotkey hold, feedback included, on a cancel from the hotkey' do
      button.press(:hotkey)
      button.cancel_press(:hotkey)
      expect(button.state).to eq(:focused)
    end

    it 'keeps a hotkey hold when focus is lost' do
      button.press(:hotkey)
      button.update(described_class::PRESS_FEEDBACK * 2)
      button.focused = false
      expect(button.state).to eq(:pressed)
    end

    it 'refuses a source it does not know' do
      expect { button.press(:mouse) }.to raise_error(ArgumentError, /:confirm or :hotkey/)
    end
  end

  # The instant press with nothing holding the button — how a press that ends
  # somewhere else hands its activation over.
  describe '#activate_with_feedback' do
    it 'activates and shows pressed for PRESS_FEEDBACK with no hold' do
      fired = []
      button.on_activated { fired << :activated }
      button.activate_with_feedback
      states = [button.state]
      button.update(described_class::PRESS_FEEDBACK)
      expect([states << button.state, fired]).to eq([%i[pressed idle], [:activated]])
    end

    it 'does nothing while disabled' do
      button.enabled = false
      expect([button.activate_with_feedback, button.pressed?]).to eq([nil, false])
    end
  end

  it 'has no hotkey unless given one' do
    expect([button.hotkey, described_class.new(hotkey: :skill1).hotkey]).to eq([nil, :skill1])
  end

  it 'refuses an activate_on: it does not know' do
    expect { described_class.new(activate_on: :hold) }.to raise_error(ArgumentError, /:release or :press/)
  end

  it 'ignores a press while disabled' do
    button.enabled = false
    expect([button.press, button.pressed?]).to eq([nil, false])
  end

  describe '#activate' do
    it 'emits and returns the button when it is enabled' do
      fired = false
      button.on_activated { fired = true }
      expect([button.activate, fired]).to eq([button, true])
    end

    # A caller never has to check first, and no route can activate a disabled
    # button.
    it 'returns nil and emits nothing when it is disabled' do
      fired = false
      button.enabled = false
      button.on_activated { fired = true }
      expect([button.activate, fired]).to eq([nil, false])
    end
  end

  describe '#_gain_focus and #_lose_focus' do
    let(:button) { recording_class.new }

    it 'calls the one for the new value when focus changes' do
      button.focused = true
      button.focused = false
      expect(button.changes).to eq([true, false])
    end

    # A menu may reassert focus every frame; a focus sound must not replay.
    it 'is not called for a repeated assignment' do
      3.times { button.focused = true }
      button.focused = false
      button.focused = false
      expect(button.changes).to eq([true, false])
    end

    it 'is not called for the initial unfocused state' do
      button.focused = false
      expect(button.changes).to be_empty
    end
  end

  it 'answers nil to adjust, having nothing to change' do
    expect(button.adjust(1)).to be_nil
  end

  describe '#adjustable?' do
    it 'is false on a button with nothing to adjust' do
      expect(button.adjustable?).to be(false)
    end

    it 'is false on every shipped button that does not override adjust' do
      classes = [RGame::Engine::UI::TextButton, RGame::Engine::UI::PanelButton, RGame::Engine::UI::IconButton]
      expect(classes.map(&:adjustable?)).to eq([false, false, false])
    end

    it 'is true on a game\'s button that overrides adjust, with nothing else said' do
      slider = Class.new(described_class) { def adjust(delta) = delta }
      expect(slider.new.adjustable?).to be(true)
    end

    it 'is true on a subclass of a button that overrides adjust' do
      slider = Class.new(described_class) { def adjust(delta) = delta }
      expect(Class.new(slider).new.adjustable?).to be(true)
    end

    it 'is true on a button whose adjust comes from a module' do
      adjusting = Module.new { def adjust(delta) = delta }
      expect(Class.new(described_class) { include adjusting }.new.adjustable?).to be(true)
    end
  end

  it 'needs no label' do
    expect(described_class.new.label).to be_nil
  end

  describe 'the label' do
    let(:text) { RGame::Engine::Text }

    it 'is a Text for the key it was given' do
      expect([button.label.class, button.label.key]).to eq([text, 'Resume'])
    end

    it 'takes a Symbol as a key' do
      expect(described_class.new(label: :resume).label.key).to eq('resume')
    end

    it 'keeps a Text it is given, as it is' do
      literal = text.literal('Ada')
      expect(described_class.new(label: literal).label).to be(literal)
    end

    it 'makes a Text of a key assigned later' do
      button.label = 'quit'
      expect(button.label.key).to eq('quit')
    end

    it 'can be cleared' do
      button.label = nil
      expect(button.label).to be_nil
    end

    describe 'label_scope' do
      it 'starts nil' do
        expect(button.label_scope).to be_nil
      end

      it 'scopes a label given as a key' do
        button.label_scope = 'pause'
        expect(button.label.scope).to eq('pause')
      end

      it 'scopes a key assigned after it' do
        button.label_scope = 'pause'
        button.label = 'quit'
        expect(button.label.scope).to eq('pause')
      end

      it 'leaves a label given as a Text alone' do
        own = text.new('quit', scope: 'common')
        button.label = own
        button.label_scope = 'pause'
        expect(own.scope).to eq('common')
      end
    end

    it 'takes a Text that declares variables' do
      score = text.new('hud.score', :score)
      expect(described_class.new(label: score).label).to be(score)
    end
  end

  it 'draws nothing of its own' do
    renderer = FakeRenderer.new
    button.draw(renderer, screen_view)
    expect(renderer.calls).to be_empty
  end
end
