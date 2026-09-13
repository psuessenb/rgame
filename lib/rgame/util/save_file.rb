# frozen_string_literal: true

require 'json'
require 'fileutils'

module RGame
  module Util
    # A game's saved state, as one JSON file.
    #
    #   save = SaveFile.new('slot1.json', game: 'sheepdog')
    #   save.write(dog: [120, 80], sheep: [[40, 40], [90, 30]])
    #   save.read                     # => { dog: [120, 80], sheep: [...] }
    #   save.read.fetch(:dog, nil)    # => nil when there is no save yet
    #
    # It holds no open handle — it opens, reads or writes, and closes — which is
    # why this is `Util` rather than `Core` (see CLAUDE.md, "Value objects go in
    # Util"). JSON comes from the standard library, so nothing here adds a
    # runtime dependency.
    #
    # ## Reading never raises
    #
    # `read` answers with the default for a file that is missing, empty,
    # truncated, not JSON, or JSON that is not an object. That is deliberate and
    # it is the whole reason this class exists rather than three lines of
    # `JSON.parse(File.read(...))` at a call site.
    #
    # A save file is the one input a game has that it did not produce this run.
    # It survives crashes, disk-full, a killed process mid-write, an editor, and
    # a copy from someone else's machine. A game that raises on any of those is
    # a game that cannot be started again, and the player's only fix is to find
    # and delete a file they were never told about. Losing a save is bad;
    # refusing to launch is worse.
    #
    # **Writing still raises.** A read failure has a sensible answer — "there is
    # no save" — and a write failure does not: silently discarding the player's
    # progress is the failure that gets noticed hours later. A caller that wants
    # to survive a full disk can rescue; it cannot un-swallow an exception this
    # class never raised.
    #
    # ## Writing is atomic
    #
    # `write` writes a temporary file beside the target and renames it over the
    # top. `File.rename` within one directory is atomic on every platform this
    # engine supports, so a save is either the old one or the new one and never
    # half of each.
    #
    # This matters more than it sounds: the moment a game most wants to save is
    # on the way out, which is also the moment it is most likely to be killed.
    # A plain `File.write` truncates first and fills in after, so a crash in
    # between leaves a zero-byte file where the player's afternoon used to be.
    class SaveFile
      # Where saves go, per platform, following each one's own convention rather
      # than dropping a dotfile in the home directory:
      #
      #   Linux    $XDG_DATA_HOME/<game>, or ~/.local/share/<game>
      #   macOS    ~/Library/Application Support/<game>
      #   Windows  %APPDATA%\<game>
      #
      # `game` names the directory, so two games do not share a save.
      def self.directory(game)
        case RbConfig::CONFIG['host_os']
        when /darwin/ then File.join(Dir.home, 'Library', 'Application Support', game)
        when /mswin|mingw|cygwin/ then File.join(ENV.fetch('APPDATA', Dir.home), game)
        else File.join(ENV.fetch('XDG_DATA_HOME', File.join(Dir.home, '.local', 'share')), game)
        end
      end

      attr_reader :path

      # `name` is a file name inside the game's save directory; pass `dir:` to
      # put it somewhere else, which is what a spec does.
      def initialize(name, game: 'rgame', dir: nil)
        @path = File.join(dir || SaveFile.directory(game), name)
      end

      def exist? = File.exist?(@path)

      # The saved state, or `default` if there is nothing usable to read. Keys
      # come back as Symbols, so a game writes and reads the same shape.
      def read(default = {})
        parsed = JSON.parse(File.read(@path), symbolize_names: true)
        parsed.is_a?(Hash) ? parsed : default
      rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, JSON::ParserError
        default
      end

      # Writes `state` as JSON, atomically. Creates the directory if it is not
      # there — a first save on a fresh machine is the normal case, not an error.
      def write(state)
        FileUtils.mkdir_p(File.dirname(@path))
        temporary = "#{@path}.#{Process.pid}.tmp"
        File.write(temporary, JSON.pretty_generate(state))
        File.rename(temporary, @path)
        self
      end

      # Removes the save, and says nothing if there was not one. "Delete my
      # save" and "there was no save" leave the player in the same place.
      def delete
        File.unlink(@path)
        self
      rescue Errno::ENOENT
        self
      end
    end
  end
end
