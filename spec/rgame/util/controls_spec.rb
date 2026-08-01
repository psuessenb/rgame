# frozen_string_literal: true

RSpec.describe RGame::Util::Controls do
  # The same ids exist twice: as Ruby constants here, and as #defines in the C
  # engine's public header (the standalone binary includes only that header and
  # cannot see Ruby). The C side is pinned to SDL's own numbering by
  # _Static_assert at compile time; this closes the other half of the chain by
  # reading the header and comparing every value.
  #
  # It is a text comparison, so it needs neither SDL nor a window and belongs in
  # the fast suite. Nothing here names RGame::Core.
  def header_path
    File.expand_path('../../../ext/rgame_core/include/rgame/core.h', __dir__)
  end

  # Object-like #defines only: a name followed by whitespace. Function-like
  # macros such as RGAME_INPUT_GAMEPAD(slot) have a '(' straight after the name
  # and are skipped, which is what we want — they are not constants.
  def c_defines
    File.read(header_path).scan(/^#define\s+(RGAME_\w+)\s+(\S.*?)\s*$/).to_h
  end

  # Values in the header are decimal, hex, or a sum of other defines and
  # integers — enough of an expression grammar to resolve without a compiler.
  def resolve(expr, table, seen = [])
    term = expr.strip
    term = term[1..-2].strip while term.start_with?('(') && term.end_with?(')')

    term.split('+').sum do |operand|
      part = operand.strip
      case part
      when /\A0x\h+\z/i then Integer(part, 16)
      when /\A\d+\z/ then Integer(part)
      when /\ARGAME_\w+\z/
        raise "cyclic define #{part}" if seen.include?(part)

        resolve(table.fetch(part), table, seen + [part])
      else raise "cannot resolve #{part.inspect} in #{expr.inspect}"
      end
    end
  end

  # Ruby constant => the C define it mirrors, where the names differ.
  def constant_map
    { 'KEYBOARD' => 'RGAME_INPUT_KEYBOARD',
      'GAMEPAD_FIRST' => 'RGAME_INPUT_GAMEPAD_FIRST',
      'MAX_GAMEPADS' => 'RGAME_INPUT_MAX_GAMEPADS' }
  end

  def c_name_for(ruby_name)
    constant_map.fetch(ruby_name, "RGAME_#{ruby_name}")
  end

  # Every KEY_*, PAD_* and AXIS_* constant, plus the three device numbers.
  def checked_constants
    described_class.constants.grep(/\A(KEY|PAD|AXIS)_/) + constant_map.keys.map(&:to_sym)
  end

  it 'has a C define behind every id it exposes' do
    table = c_defines
    missing = checked_constants.reject { |name| table.key?(c_name_for(name.to_s)) }

    expect(missing).to be_empty,
                       "no #define in core.h for: #{missing.join(', ')}"
  end

  it 'agrees with the C engine on every id' do
    table = c_defines
    mismatched = checked_constants.filter_map do |name|
      c_value = resolve(table.fetch(c_name_for(name.to_s)), table)
      ruby_value = described_class.const_get(name)
      "#{name}: Ruby #{ruby_value} vs C #{c_value}" unless ruby_value == c_value
    end

    expect(mismatched).to be_empty,
                          "these ids have drifted from ext/rgame_core/include/rgame/core.h:\n  " \
                          "#{mismatched.join("\n  ")}"
  end

  it 'checks a meaningful number of ids, so a broken parser cannot pass vacuously' do
    expect(checked_constants.size).to be >= 25
  end

  describe 'the id space' do
    it 'keeps every gamepad button inside the gamepad range' do
      pad_ids = described_class.constants.grep(/\APAD_/).map { |c| described_class.const_get(c) }

      expect(pad_ids).to all(be >= 0x1000)
      expect(pad_ids).to all(be <= 0x10FF)
    end

    it 'keeps every key inside the keyboard range' do
      key_ids = described_class.constants.grep(/\AKEY_/).map { |c| described_class.const_get(c) }

      expect(key_ids).to all(be < 0x1000)
    end

    it 'numbers the keyboard device before any gamepad' do
      expect(described_class::KEYBOARD).to eq(0)
      expect(described_class.gamepad(0)).to be > described_class::KEYBOARD
      expect(described_class.gamepad(3)).to eq(described_class::GAMEPAD_FIRST + 3)
    end
  end

  describe 'the default bindings' do
    it 'binds the same action to a different physical input per device class' do
      expect(described_class::DEFAULT_KEYBOARD[:fire]).to eq(described_class::KEY_SPACE)
      expect(described_class::DEFAULT_PAD[:fire]).to eq(described_class::PAD_A)
    end

    it 'covers the same actions on keyboard and pad, so rebinding one is not lopsided' do
      expect(described_class::DEFAULT_PAD.keys).to match_array(described_class::DEFAULT_KEYBOARD.keys)
    end

    it 'is frozen, so a game merges rather than mutating the defaults' do
      expect(described_class::DEFAULT_KEYBOARD).to be_frozen
      expect(described_class::DEFAULT_PAD).to be_frozen
      expect(described_class::DEFAULT_AXES).to be_frozen
    end

    it 'has no pointer binding — mouse input is deliberately absent' do
      expect(described_class::DEFAULT_KEYBOARD).not_to have_key(:pointer)
    end
  end
end
