# frozen_string_literal: true

# The two ways a menu presses a button — `ui_confirm` on the focused one, and a
# button's own hotkey — go through one rule, so the rules they share are one
# group run once for each. What legitimately differs is passed in: whether a
# press under `activate_on: :release` is instant, and whether losing focus ends
# the hold.
RSpec.describe RGame::Engine::UI::Menu do
  let(:root) { RGame::Engine::Node2D.new }
  let(:column) { RGame::Engine::UI::Column.new(item_width: 200, item_height: 40) }
  let(:menu) { root.add_node(described_class.new(layout: column)) }
  let(:snapshot) do
    reads = %i[ui_up ui_down ui_left ui_right ui_confirm skill1 skill2]
    held = reads.to_h { |name| [name, false] }
    previous = reads.to_h { |name| [name, false] }
    actions = RGame::Engine::Actions.new(held: held, axes: {}, prev_held: previous)

    lambda do |*down|
      held.each { |name, state| previous[name] = state }
      reads.each { |name| held[name] = down.include?(name) }
      actions
    end
  end

  def poll(*down) = root.control(snapshot.call(*down))

  def fired_on(button)
    [].tap { |log| button.on_activated { log << button.label } }
  end

  # The focused first button answers both sources: confirm reaches it by focus,
  # and `skill1` is its hotkey. The second has a hotkey of its own.
  def build(activate_on:)
    menu.add(RGame::Engine::UI::Button.new(label: 'One', hotkey: :skill1, activate_on: activate_on))
    menu.add(RGame::Engine::UI::Button.new(label: 'Two', hotkey: :skill2, activate_on: activate_on))
    root.enter_tree
    poll
    menu.buttons.first
  end

  shared_examples 'a press source' do |action:, other_action:, instant_under_release:, survives_focus_loss:|
    # Rule 1.
    describe 'the press edge' do
      it 'activates under activate_on: :press' do
        fired = fired_on(build(activate_on: :press))
        poll(action)
        expect(fired).to eq(['One'])
      end

      it 'activates under activate_on: :release only if this source is instant' do
        fired = fired_on(build(activate_on: :release))
        poll(action)
        expect(fired).to eq(instant_under_release ? ['One'] : [])
      end

      it 'does not move focus' do
        build(activate_on: :press)
        poll(action)
        expect(menu.focused_index).to eq(0)
      end
    end

    # Rule 2.
    describe 'the pressed look' do
      it 'shows while held, past PRESS_FEEDBACK' do
        target = build(activate_on: :press)
        poll(action)
        root.update(RGame::Engine::UI::Button::PRESS_FEEDBACK * 3)
        poll(action)
        expect(target.state).to eq(:pressed)
      end

      it 'outlasts a tap by PRESS_FEEDBACK, then ends' do
        target = build(activate_on: :press)
        poll(action)
        poll
        states = [target.state]
        root.update(RGame::Engine::UI::Button::PRESS_FEEDBACK)
        expect(states << target.state).to eq(%i[pressed focused])
      end
    end

    # Rule 3.
    %i[press release].each do |activate_on|
      it "activates once over a press and its release under activate_on: :#{activate_on}" do
        fired = fired_on(build(activate_on: activate_on))
        poll(action)
        poll
        poll
        expect(fired).to eq(['One'])
      end
    end

    # Rule 4.
    describe 'a menu added by an activation' do
      it 'does not fire from the same press, or its release' do
        opener = build(activate_on: :press)
        submenu = described_class.new(layout: column)
        back = submenu.add(RGame::Engine::UI::Button.new(label: 'Back', hotkey: :skill1, activate_on: :press))
        fired = fired_on(back)
        opener.on_activated { root.add_node(submenu) }
        3.times { poll(action) }
        poll
        expect([back.in_tree?, back.state, fired]).to eq([true, :focused, []])
      end
    end

    # Rule 5.
    describe 'a release the menu never saw' do
      it 'cancels the press and its feedback' do
        target = build(activate_on: :press)
        fired = fired_on(target)
        poll(action)
        menu.paused = true
        poll
        menu.paused = false
        poll
        expect([target.state, fired]).to eq([:focused, ['One']])
      end
    end

    # Rule 6.
    it 'is ignored by a disabled button' do
      target = build(activate_on: :press)
      fired = fired_on(target)
      target.enabled = false
      poll(action)
      target.enabled = true
      expect([target.pressed?, fired]).to eq([false, []])
    end

    # Rule 7. Whichever source holds the button first owns the hold: the
    # other's press and release change nothing, and the button activates once.
    describe 'a second source on a button this one holds' do
      it 'neither ends the hold nor activates it again' do
        target = build(activate_on: :release)
        fired = fired_on(target)
        poll(action)
        poll(action, other_action)
        poll(action)
        states = [target.state]
        poll
        expect([states, fired]).to eq([[:pressed], ['One']])
      end
    end

    # Rule 8. Past PRESS_FEEDBACK, so what is left pressed is the hold.
    it 'keeps or drops the hold when focus moves, as this source does' do
      target = build(activate_on: :release)
      poll(action)
      root.update(RGame::Engine::UI::Button::PRESS_FEEDBACK * 2)
      poll(action, :ui_down)
      expect(target.pressed?).to eq(survives_focus_loss)
    end

    # Rule 9.
    %i[press release].each do |activate_on|
      it "activates once when pressed with the other source on the same tick, under :#{activate_on}" do
        fired = fired_on(build(activate_on: activate_on))
        poll(action, other_action)
        poll
        poll
        expect(fired).to eq(['One'])
      end
    end
  end

  describe 'confirm' do
    it_behaves_like 'a press source',
                    action: :ui_confirm, other_action: :skill1, instant_under_release: false, survives_focus_loss: false
  end

  describe 'a hotkey' do
    it_behaves_like 'a press source',
                    action: :skill1, other_action: :ui_confirm, instant_under_release: true, survives_focus_loss: true

    it 'presses a button that is not focused, and shows it' do
      build(activate_on: :release)
      second = menu.buttons.last
      fired = fired_on(second)
      poll(:skill2)
      expect([menu.focused_index, second.state, fired]).to eq([0, :pressed, ['Two']])
    end

    it 'activates nothing on its release' do
      target = build(activate_on: :release)
      poll(:skill1)
      fired = fired_on(target)
      poll
      expect(fired).to eq([])
    end

    it 'never presses a button added while it is down' do
      build(activate_on: :press)
      poll(:skill1)
      late = menu.add(RGame::Engine::UI::Button.new(label: 'Late', hotkey: :skill1, activate_on: :press))
      fired = fired_on(late)
      2.times { poll(:skill1) }
      poll
      expect([late.state, fired]).to eq([:idle, []])
    end

    it 'presses a button added while it was up, once seen up' do
      build(activate_on: :press)
      late = menu.add(RGame::Engine::UI::Button.new(label: 'Late', hotkey: :skill2, activate_on: :press))
      fired = fired_on(late)
      poll
      poll(:skill2)
      expect(fired).to eq(['Late'])
    end
  end
end
