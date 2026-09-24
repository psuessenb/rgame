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

      private_constant :CATEGORIES

      # Loads a short sound to play over itself. The same thing as
      # `Sample.new(audio, path)`, and the form to prefer: it reads in the
      # direction the objects depend, and it is the form a stand-in device can
      # implement, which `Sample.new` is not.
      def sample(path) = Sample.new(self, path)

      # Loads a long one to stream. See {Song}.
      def song(path) = Song.new(self, path)

      #   audio.play_sound(:hit)
      #
      # `category:` names the volume the sound plays under: `:effects` unless
      # given. A name used here for the first time is created, fourteen at most
      # beside `:music` and `:effects`, and a sound registered again plays under
      # the last name given.
      def register_sound(id, sample, category: :effects)
        samples[id] = sample
        put_in_category(sample, category_for(category))
        self
      end

      # As #register_sound, for a song, under `:music` unless given.
      def register_music(id, song, category: :music)
        songs[id] = song
        put_in_category(song, category_for(category))
        self
      end

      # Plays a sample by id. Each call is another voice, layered over the ones
      # already sounding.
      def play_sound(id)
        lookup(:sound, id).play
      end

      # Starts a song looping, and makes it the song #stop_music and
      # #pause_music act on. A song already playing is **not** restarted, so a
      # scene that re-emits the same request every time it is entered never
      # restarts the music mid-loop.
      def play_music(id)
        song = lookup(:song, id)
        @paused = false
        @playing_song = song
        return song if song.playing?

        song.play(looping: true)
      end

      # Stops the song the id names, or with no id the one #play_music last
      # started.
      #
      # Deliberately not "stop whatever is playing": one song at a time is a
      # game's policy rather than the engine's, so there is no process-wide
      # current song, and a `Song` a game started by hand is its own to stop.
      def stop_music(id = nil)
        song = id.nil? ? @playing_song : lookup(:song, id)
        song&.stop
        return if id && !song.equal?(@playing_song)

        @paused = false
        @playing_song = nil
      end

      # Stops the current song where it is. #resume_music carries on from
      # there, and #play_music starts it from the top.
      def pause_music
        return unless @playing_song&.playing?

        @playing_song.stop
        @paused = true
      end

      # Carries on the song #pause_music stopped. Does nothing unless a song is
      # paused.
      def resume_music
        return unless @paused

        @paused = false
        @playing_song.resume
      end

      # Sets the song's own volume, as `Song#volume=` does, by id.
      def set_music_volume(id, volume)
        lookup(:song, id).volume = volume
      end

      # The volume every sound in the category plays under, 1.0 until set. It
      # multiplies each sound's own volume and leaves it as it was. A name no
      # sound was registered under raises KeyError, so a mistyped category
      # fails rather than changing nothing.
      def category_volume(name) = category_volume_at(category_index(name))

      def set_category_volume(name, volume)
        set_category_volume_at(category_index(name), volume)
      end

      private

      def samples = @samples ||= {}
      def songs = @songs ||= {}
      def categories = @categories ||= { music: 0, effects: 1 }

      def category_index(name)
        categories.fetch(name) { raise KeyError, "no sound was registered under the category #{name.inspect}" }
      end

      def category_for(name)
        raise TypeError, "a category is named by a Symbol, not #{name.inspect}" unless name.is_a?(Symbol)

        categories.fetch(name) do
          raise ArgumentError, "no more than #{CATEGORIES} categories" if categories.size == CATEGORIES

          categories[name] = categories.size
        end
      end

      def registry(type) = type == :sound ? samples : songs

      def lookup(type, id)
        raise TypeError, "no implicit conversion of nil into #{type}" if id.nil?

        table = registry(type)
        table.fetch(id) { table[id] = resolve_asset(type, id) }
      end

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
    #   music.resume    # from where it stopped
    #
    # Unlike a sample, a song is one voice: playing it while it plays restarts
    # it from the beginning. Stopping and playing again also restarts, and
    # stopping and resuming carries on where it stopped.
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
