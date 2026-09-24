# frozen_string_literal: true

module RGame
  module Engine
    # The system a node plays sound through, and the clock its music fades on.
    #
    #   out = system!(Engine::AudioOut)
    #   out.play_sound(:boom)
    #   out.play_music(:theme, fade: 0.8)   # up from silence over 0.8 s
    #   out.crossfade(:battle, over: 1.2)   # :theme down while :battle comes up
    #   out.stop_music(fade: 0.5)           # down to silence, then stopped
    #
    # RGame::Game mounts one on the root, holding the game's sound device, so
    # every node in the tree reaches it with `Node2D#system!`. A spec mounts one
    # the same way, built on the audio stand-in it asserts against:
    #
    #   root.add_component(Engine::AudioOut.new(FakeAudio.new))
    #
    # What an id resolves to, whether music loops and what a category holds are
    # the device's. What this adds is time: a fade is a volume set once a tick
    # from `_update`, off two tweens built once, so pausing the game's clock
    # pauses a fade and a spec reads a fade halfway by passing half its length.
    # Being on the root, a fade outlives the scene that asked for it.
    #
    # It tracks two songs at most: the current one, and one on its way out. A
    # song it stops or fades out plays at full volume the next time. It calls
    # the device by method name, so it names no Core class, and the 'an audio
    # server' contract in rgame's own suite checks the stand-ins against the
    # real device.
    class AudioOut < Component
      # `audio` is the sound device: anything answering the calls below by name,
      # as RGame::Core::Audio does.
      def initialize(audio)
        super()
        @audio = audio
        @rise = Engine::Tween.new(1.0, to: 1.0)
        @fall = Engine::Tween.new(1.0, to: 0.0)
        @rising = nil
        @falling = nil
        @current = nil
        @paused = false
      end

      def play_sound(id) = @audio.play_sound(id)

      # Plays a song looping and makes it the current one. With `fade:` it
      # comes up from silence over that many seconds; with none, the device is
      # sent exactly the one call it would be sent without a fade. A song on its
      # way out comes back up from where it is, rather than starting again.
      def play_music(id, fade: 0)
        seconds = seconds!(:fade, fade)
        level = level_of(id)
        @falling = nil if @falling == id
        bring_in(id, level, seconds)
      end

      # Stops the current song, or with `fade:` lowers it to silence over that
      # many seconds and stops it on the tick it arrives. A song still on its
      # way out of a crossfade stops at once.
      def stop_music(fade: 0)
        seconds = seconds!(:fade, fade)
        if seconds.zero?
          stop_at_once
        elsif @current
          fade_out(@current, seconds)
        end
        nil
      end

      # Lowers the current song and raises `id` over the same `over` seconds,
      # and stops the old song once it is silent. With no current song it is a
      # fade in. A crossfade begun before the last one ended stops the song
      # still on its way out, and brings the one that was coming in down from
      # where it is.
      def crossfade(id, over:)
        seconds = seconds!(:over, over)
        return play_music(id, fade: seconds) if @current.nil? || @current == id

        level = level_of(id)
        @falling = nil if @falling == id
        fade_out(@current, seconds)
        bring_in(id, level, seconds)
      end

      # Holds the music and its fade where they are: the current song, or the
      # song a `stop_music(fade:)` is lowering. A song on its way out of a
      # crossfade stops at once.
      def pause_music
        stop_now(@falling) if @falling && @current
        @audio.pause_music
        @paused = true
      end

      # Carries the song and its fade on from where #pause_music held them.
      def resume_music
        @audio.resume_music
        @paused = false
      end

      def category_volume(name) = @audio.category_volume(name)
      def set_category_volume(name, volume) = @audio.set_category_volume(name, volume)

      # Whether a song is on its way up or down.
      def fading? = !(@rising.nil? && @falling.nil?)

      def _update(dt)
        return if @paused

        step_rise(dt) if @rising
        step_fall(dt) if @falling
      end

      private

      def level_of(id)
        return nil if id.nil?
        return @rise.value if id == @rising
        return @fall.value if id == @falling

        1.0 if id == @current
      end

      def bring_in(id, level, seconds)
        settle_rise unless @rising == id
        @audio.set_music_volume(id, 0.0) if level.nil? && seconds.positive?
        @audio.play_music(id)
        @current = id
        @paused = false
        level ||= seconds.positive? ? 0.0 : 1.0
        return if level >= 1.0

        seconds.positive? ? start_rise(id, level, seconds) : settle(id)
      end

      def fade_out(id, seconds)
        level = level_of(id)
        stop_now(@falling) if @falling
        @rising = nil if @rising == id
        @current = nil
        return stop_now(id) if seconds.zero?

        @falling = id
        @fall.from = level
        @fall.duration = seconds
        @fall.restart
      end

      def start_rise(id, level, seconds)
        @rising = id
        @rise.from = level
        @rise.duration = seconds
        @rise.restart
      end

      def settle(id)
        @rising = nil if @rising == id
        @audio.set_music_volume(id, 1.0)
      end

      def settle_rise
        settle(@rising) if @rising
      end

      def stop_now(id)
        @falling = nil if @falling == id
        @audio.stop_music(id)
        @audio.set_music_volume(id, 1.0)
      end

      def stop_at_once
        stop_now(@falling) if @falling
        level = level_of(@current)
        @audio.stop_music
        @audio.set_music_volume(@current, 1.0) if level && level < 1.0
        @rising = nil
        @current = nil
        @paused = false
      end

      def step_rise(dt)
        @audio.set_music_volume(@rising, @rise.update(dt).value)
        @rising = nil if @rise.done?
      end

      def step_fall(dt)
        @audio.set_music_volume(@falling, @fall.update(dt).value)
        stop_now(@falling) if @fall.done?
      end

      def seconds!(name, value)
        return value if value.is_a?(Numeric) && value >= 0

        raise ArgumentError, "#{name}: must be 0 or more seconds, not #{value.inspect}"
      end
    end
  end
end
