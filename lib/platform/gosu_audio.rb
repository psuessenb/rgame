# frozen_string_literal: true

module Platform
  # Audio backend backed by Gosu, the mirror of GosuRenderer: the app registers
  # samples (one-shot SFX) and songs (looping music) by id, then plays them by id.
  # The engine never sees Gosu — Engine::AudioDirector drives this through
  # :play_sound/:play_music events; tests substitute a recording fake with the same
  # methods.
  class GosuAudio
    def initialize
      @samples = {}
      @songs   = {}
    end

    # Store already-loaded samples/songs under an id; the AssetManager does the
    # loading + caching, this is just the play-by-id registry.
    def register_sound(id, sample)
      @samples[id] = sample
    end

    def register_music(id, song)
      @songs[id] = song
    end

    def play_sound(id)
      @samples.fetch(id).play
    end

    # Loop a registered song. Idempotent: re-requesting the song already playing is a
    # no-op, so a scene re-emitting :play_music never restarts it mid-loop.
    def play_music(id)
      song = @songs.fetch(id)
      song.play(true) unless song.playing?
    end

    def stop_music
      Gosu::Song.current_song&.stop
    end
  end
end
