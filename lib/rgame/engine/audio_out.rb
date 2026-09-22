# frozen_string_literal: true

module RGame
  module Engine
    # The system a node plays sound through.
    #
    #   system!(Engine::AudioOut).play_sound(:boom)
    #   system!(Engine::AudioOut).play_music(:theme)
    #   system!(Engine::AudioOut).stop_music
    #
    # RGame::Game mounts one on the root, holding the game's sound device, so
    # every node in the tree reaches it with `Node2D#system!`. A spec mounts one
    # the same way, built on the audio stand-in it asserts against:
    #
    #   root.add_component(Engine::AudioOut.new(FakeAudio.new))
    #
    # It forwards each call to the audio server it holds and decides nothing
    # itself: what an id resolves to, whether music loops, and what `stop_music`
    # stops are the server's. It calls the server by method name, so it names no
    # Core class, and the 'an audio server' contract in rgame's own suite checks
    # the stand-ins against the real device.
    class AudioOut < Component
      # `audio` is the sound device: anything answering `play_sound(id)`,
      # `play_music(id)` and `stop_music`, as RGame::Core::Audio does.
      def initialize(audio)
        super()
        @audio = audio
      end

      def play_sound(id) = @audio.play_sound(id)
      def play_music(id) = @audio.play_music(id)
      def stop_music = @audio.stop_music
    end
  end
end
