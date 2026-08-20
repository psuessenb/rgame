# frozen_string_literal: true

# A recording stand-in for RGame::Core::Input, for specs of the engine layer's
# input path.
#
# The whole backend contract is two methods — `down?(id, device:)` and
# `axis(axis_id, device:)` — so this is small. What it must get right is the
# property every binding table depends on: **a device only answers for its own
# kind of input**. State is stored per device, so a key held "on the keyboard"
# is invisible to a gamepad, exactly as the real one behaves.
#
# It also refuses what the real one refuses. `RGame::Core::Input` hands ids
# straight to the C layer, where `NUM2INT` raises `TypeError` for anything that
# is not a number — so a Symbol id (which is what the binding map used to hold,
# before physical ids replaced it) fails here rather than quietly reading false
# forever. See CLAUDE.md, "A fake must refuse what the real thing refuses".
class FakeInputBackend
  KEYBOARD = RGame::Util::Controls::KEYBOARD

  def initialize
    @held = Hash.new { |hash, device| hash[device] = {} }
    @axes = Hash.new { |hash, device| hash[device] = {} }
  end

  def hold(*ids, device: KEYBOARD)
    ids.each { |id| @held[device][check(id)] = true }
    self
  end

  def release(*ids, device: KEYBOARD)
    ids.each { |id| @held[device].delete(check(id)) }
    self
  end

  def set_axis(axis_id, value, device: KEYBOARD)
    @axes[device][check(axis_id)] = Float(value)
    self
  end

  def clear
    @held.clear
    @axes.clear
    self
  end

  def down?(id, device: KEYBOARD)
    @held[check(device)].fetch(check(id), false)
  end

  def axis(axis_id, device: KEYBOARD)
    @axes[check(device)].fetch(check(axis_id), 0.0)
  end

  private

  def check(id)
    raise TypeError, "no implicit conversion of #{id.class} into Integer" unless id.is_a?(Integer)

    id
  end
end
