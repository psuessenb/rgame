# frozen_string_literal: true

require 'rgame/core_ext'

module RGame
  module Core
    # The sound device: one per game, and the thing samples and songs are made
    # from.
    #
    #   audio = RGame::Core::Audio.new
    #   audio.volume = 0.8
    #
    # It is not tied to a window. Sound outlives a resized or recreated window
    # and has nothing to do with a GL context, so nothing here takes an `app`.
    #
    # A machine with no sound hardware still gets a working `Audio` — it opens a
    # null device and plays silently. That is deliberate: a game should run on a
    # server, in a container, or on a laptop with the sound card disabled, and
    # the alternative is a crash at startup for something nobody asked for.
    # `#backend` says which one was chosen.
    class Audio
      # `assets` is what a path id is resolved through, and may be nil — a
      # device built by hand plays only what it is handed. `RGame::Core::App`
      # passes its own manager, so a game never sets this.
      #
      # A Ruby `self.new` because the C `initialize` takes no arguments and has
      # no business knowing what an asset manager is — the same shape
      # `Renderer.new` uses for the same reason.
      def self.new(assets: nil)
        audio = super()
        audio.assets = assets
        audio
      end

      attr_accessor :assets

      # Loads a short sound to play over itself. The same thing as
      # `Sample.new(audio, path)`, and the form to prefer: it reads in the
      # direction the objects depend, and it is the form a stand-in device can
      # implement, which `Sample.new` is not.
      def sample(path) = Sample.new(self, path)

      # Loads a long one to stream. See {Song}.
      def song(path) = Song.new(self, path)

      # --- play-by-id -----------------------------------------------------
      #
      # The same boundary the renderer's draw-by-id serves: game logic emits
      # facts — "the ship was hit" — and names the sound, because a scene may
      # not hold a `Sample`.
      #
      # An id is normally a **root-relative path**, resolved through the asset
      # manager on first use and then remembered:
      #
      #   audio.play_sound('hurt.ogg')
      #
      # `register_*` binds an id to a chosen object, which is what a name that
      # is not a file needs, and what a sound the game assembled rather than
      # loaded needs. A registered id also wins over a path that would resolve:
      #
      #   audio.register_sound(:hit, app.assets.sound('hurt.ogg'))
      #   audio.play_sound(:hit)
      #
      # **Resolution is cached, and has to be.** `play_music` asks the song
      # whether it is already playing, so resolving one path to two Song objects
      # would defeat that guard and restart the track on every request.

      def register_sound(id, sample)
        samples[id] = sample
        self
      end

      def register_music(id, song)
        songs[id] = song
        self
      end

      # Plays a sample by id. Each call is another voice, layered over the ones
      # already sounding.
      def play_sound(id)
        lookup(:sound, id).play
      end

      # Starts a song looping, and does **nothing** if it is already playing —
      # so a scene that re-emits the same request every time it is entered never
      # restarts the music mid-loop.
      def play_music(id)
        song = lookup(:song, id)
        return song if song.playing?

        @playing_song = song
        song.play(looping: true)
      end

      # Stops the song this registry started.
      #
      # Deliberately not "stop whatever is playing": the layer being replaced
      # reached for a process-wide `current_song`, and there is no such global
      # here by the decision that one-song-at-a-time is a game's policy rather
      # than the engine's. A `Song` a game started by hand is its own to stop.
      def stop_music
        @playing_song&.stop
        @playing_song = nil
      end

      private

      def samples = @samples ||= {}
      def songs = @songs ||= {}

      # Which registry answers for a kind of id. The names differ because the
      # asset manager's accessors are `sound` and `song` while the tables here
      # are of samples and songs; one map beats two spellings drifting apart.
      def registry(type) = type == :sound ? samples : songs

      # An id that has been registered, or a path resolved once and remembered.
      # The same shape as `Renderer#lookup`, deliberately: two id spaces that
      # behave differently is a thing a caller has to hold in their head.
      def lookup(type, id)
        # `nil` is never an id, and reporting it as one describes a typo when
        # the real bug is usually an asset that resolved to nothing.
        raise TypeError, "no implicit conversion of nil into #{type}" if id.nil?

        table = registry(type)
        table.fetch(id) { table[id] = resolve_asset(type, id) }
      end

      # Only a String is offered to the asset manager, because only a String can
      # be a path. A Symbol is a name a game chose, so a missing one is the
      # KeyError below — naming the id — rather than whatever the manager makes
      # of being handed a Symbol where it wanted a filename.
      def resolve_asset(type, id)
        resolved = @assets.public_send(type, id) if id.is_a?(String) && @assets.respond_to?(type)
        resolved || raise(KeyError, "no #{type} registered for #{id.inspect} " \
                                    'and no AssetManager to resolve it')
      end
    end

    # A short sound, decoded once and played many times over.
    #
    #   hit = RGame::Core::Sample.new(audio, 'assets/hit.ogg')
    #   hit.volume = 0.5
    #   hit.play
    #   hit.play   # layers a second voice over the first
    #
    # Playing a sample that is already sounding starts *another* copy rather
    # than restarting it, which is what makes footsteps and gunfire sound like
    # themselves. There is no handle for a single play and no way to stop one;
    # a sample is fire-and-forget. Volume belongs to the sample and applies to
    # every voice it has out, including the ones already sounding.
    #
    # Ogg Vorbis and WAV are the formats the engine reads. Anything else, or an
    # unreadable file, raises {Sample::LoadError}.
    class Sample
    end

    # A long piece of music, streamed from disk rather than decoded up front.
    #
    #   music = RGame::Core::Song.new(audio, 'assets/theme.ogg')
    #   music.play(looping: true)
    #   music.playing?  # => true
    #   music.stop
    #
    # Unlike a sample, a song is one voice: playing it while it plays restarts
    # it from the beginning. Stopping and playing again also restarts — there is
    # no pause.
    #
    # "Only one song at a time" is a rule a game keeps, not one this class
    # enforces. Two songs can play at once, which is what a crossfade is.
    class Song
      # `looping:` is a keyword here and positional in C, which has no keywords.
      def play(looping: false)
        play_looping(looping)
      end
    end
  end
end
