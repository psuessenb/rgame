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
      # not hold a `Sample`. Registration only, unlike the renderer: a sound id
      # is whatever a game wants to call it, and there is no per-frame path to
      # make resolving one worth caching.
      #
      #   audio.register_sound(:hit, app.assets.sound('example 09/hurt.ogg'))
      #   audio.play_sound(:hit)

      def register_sound(id, sample)
        samples[id] = sample
        self
      end

      def register_music(id, song)
        songs[id] = song
        self
      end

      # Plays a registered sample. Each call is another voice, layered over the
      # ones already sounding.
      def play_sound(id)
        samples.fetch(id).play
      end

      # Starts a registered song looping, and does **nothing** if it is already
      # playing — so a scene that re-emits the same request every time it is
      # entered never restarts the music mid-loop.
      def play_music(id)
        song = songs.fetch(id)
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
