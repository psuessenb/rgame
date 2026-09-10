# frozen_string_literal: true

require 'tmpdir'

RSpec.describe RGame::Util::SaveFile do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  attr_reader :dir

  def save(name = 'slot1.json') = described_class.new(name, dir: dir)

  describe 'a round trip' do
    it 'reads back what it wrote' do
      save.write(dog: [120, 80], sheep: [[40, 40], [90, 30]])

      expect(save.read).to eq(dog: [120, 80], sheep: [[40, 40], [90, 30]])
    end

    it 'gives keys back as Symbols, so a game writes and reads one shape' do
      save.write(dog: [1, 2])

      expect(save.read.keys).to eq([:dog])
    end

    it 'reports whether there is a save at all' do
      expect(save).not_to be_exist

      save.write(dog: [1, 2])

      expect(save).to be_exist
    end

    it 'replaces an earlier save rather than merging into it' do
      save.write(dog: [1, 2], sheep: [])
      save.write(dog: [3, 4])

      expect(save.read).to eq(dog: [3, 4])
    end
  end

  # The point of the class. A save file is the one input a game did not produce
  # this run, and every one of these is a state a real one turns up in.
  describe 'reading something unusable' do
    it 'answers the default when there is no file' do
      expect(save.read).to eq({})
    end

    it 'takes the default a caller passes' do
      expect(save.read(dog: [0, 0])).to eq(dog: [0, 0])
    end

    it 'answers the default for a truncated file' do
      # What a kill mid-write used to leave behind, before writes were atomic.
      File.write(File.join(dir, 'slot1.json'), '{"dog":[120,')

      expect(save.read).to eq({})
    end

    it 'answers the default for an empty file' do
      File.write(File.join(dir, 'slot1.json'), '')

      expect(save.read).to eq({})
    end

    it 'answers the default for something that is not JSON at all' do
      File.write(File.join(dir, 'slot1.json'), 'this used to be a save file')

      expect(save.read).to eq({})
    end

    it 'answers the default for JSON that is not an object' do
      # Valid JSON, wrong shape — `[1, 2, 3]` parses fine and would then fail on
      # the first `state[:dog]` instead of here.
      File.write(File.join(dir, 'slot1.json'), '[1, 2, 3]')

      expect(save.read).to eq({})
    end

    it 'answers the default when a directory is in the way' do
      Dir.mkdir(File.join(dir, 'slot1.json'))

      expect(save.read).to eq({})
    end
  end

  describe 'writing' do
    it 'creates the save directory when it is not there yet' do
      # The first save on a fresh machine is the normal case, not an error.
      nested = described_class.new('slot1.json', dir: File.join(dir, 'deep', 'deeper'))
      nested.write(dog: [1, 2])

      expect(nested.read).to eq(dog: [1, 2])
    end

    it 'leaves no temporary file behind' do
      save.write(dog: [1, 2])

      expect(Dir.children(dir)).to eq(['slot1.json'])
    end

    it 'keeps the previous save intact when the new one cannot be written' do
      # The property the temp-file-and-rename buys: a failed write leaves the
      # old save whole rather than a truncated new one.
      #
      # A NaN coordinate stands in for the disk filling up, and is not a
      # contrived stand-in: a division by zero in a movement calculation puts one
      # in the game state, and JSON has no way to write it. Without the rename
      # this would blank the save on the way past.
      save.write(dog: [1, 2])

      expect { save.write(dog: [Float::NAN, 0]) }.to raise_error(JSON::GeneratorError)
      expect(save.read).to eq(dog: [1, 2])
    end

    it 'raises rather than losing progress quietly' do
      # Reading has a sensible answer for failure and writing does not: a
      # discarded save is noticed hours later, by which time it is gone.
      #
      # A plain file standing where a directory needs to be created is what
      # makes this fail on every platform alike: on Windows `/proc/nope/never`
      # is not a pseudo-filesystem, it is just a path under the current
      # drive's root, and `mkdir_p` happily creates it.
      blocker = File.join(dir, 'blocker')
      File.write(blocker, '')
      unwritable = described_class.new('slot1.json', dir: File.join(blocker, 'nested'))

      expect { unwritable.write(dog: [1, 2]) }.to raise_error(SystemCallError)
    end
  end

  describe 'deleting' do
    it 'removes the save' do
      save.write(dog: [1, 2])

      save.delete

      expect(save).not_to be_exist
    end

    it 'says nothing when there was no save' do
      # "Delete my save" and "there was no save" leave the player in the same
      # place, so this is not worth an exception.
      expect { save.delete }.not_to raise_error
    end
  end

  describe '.directory' do
    it 'follows the platform convention rather than dropping a dotfile at home' do
      # One of the three, depending on where the suite is running. Asserting the
      # shape rather than the platform keeps this meaningful on all of them —
      # all three are CI-gated.
      directory = described_class.directory('sheepdog')

      expect(directory).to end_with('sheepdog')
      expect(directory).to satisfy do |path|
        path.include?('.local/share') || path.include?('Application Support') ||
          path.include?(ENV.fetch('APPDATA', 'APPDATA-is-unset'))
      end
    end

    it 'puts two games in two directories' do
      expect(described_class.directory('one')).not_to eq(described_class.directory('two'))
    end

    it 'honours XDG_DATA_HOME where that is the convention' do
      skip 'not the XDG platform' unless RbConfig::CONFIG['host_os'].include?('linux')

      expect(with_env('XDG_DATA_HOME' => '/tmp/xdg') { described_class.directory('g') })
        .to eq('/tmp/xdg/g')
    end
  end

  def with_env(values)
    previous = values.transform_values { |_| nil }.merge(ENV.slice(*values.keys))
    ENV.update(values)
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
