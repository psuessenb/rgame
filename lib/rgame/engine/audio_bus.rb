# frozen_string_literal: true

module RGame
  module Engine
    # A global, always-present audio bus: gameplay emits audio *facts* here (decoupled
    # from any Gosu playback), and an AudioDirector turns them into sound. A module
    # rather than an instance so any node can reach it without wiring.
    module AudioBus
      @on_play_sound = Signal.define(:id).new
      @on_play_music = Signal.define(:id).new
      @on_stop_music = Signal.define.new

      def self.on_play_sound = @on_play_sound
      def self.on_play_music = @on_play_music
      def self.on_stop_music = @on_stop_music

      # Emit shims so callers say `AudioBus.play_sound(:boom)` rather than reaching
      # through the signal. The signal is still the subscription seam (AudioDirector).
      def self.play_sound(id) = @on_play_sound.emit(id)
      def self.play_music(id) = @on_play_music.emit(id)
      def self.stop_music = @on_stop_music.emit
    end
  end
end
