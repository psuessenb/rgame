# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Button do
  # Records every focus change it is told about, which is the hook a button with
  # a focus sound or animation would override.
  let(:recording_class) do
    Class.new(described_class) do
      def changes = @changes ||= []
      def on_focus_changed(focused) = changes << focused
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

    it 'is pressed while it is focused and pressed' do
      button.focused = true
      button.pressed = true
      expect(button.state).to eq(:pressed)
    end

    it 'is not pressed without focus' do
      button.pressed = true
      expect(button.state).to eq(:idle)
    end

    it 'is disabled whatever else is true' do
      button.enabled = false
      button.focused = true
      button.pressed = true
      expect(button.state).to eq(:disabled)
    end
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

  describe '#on_focus_changed' do
    let(:button) { recording_class.new }

    it 'is called with the new value when focus changes' do
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

  it 'needs no label' do
    expect(described_class.new.label).to be_nil
  end

  it 'draws nothing of its own' do
    renderer = FakeRenderer.new
    button.draw(renderer, screen_view)
    expect(renderer.calls).to be_empty
  end
end
