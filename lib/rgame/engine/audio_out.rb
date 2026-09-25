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
    #
    # **Music can be claimed instead of played.** Each claim has a key, a song
    # and a priority, and the claim with the highest priority plays:
    #
    #   out.claim_music(:battle, 'battle.ogg', priority: 10, fade: 0.3)
    #   out.release_music(:battle, fade: 1.0)   # back to whatever the other claims choose
    #
    # A Scene::Rooms claims each room's song this way, so a battle claimed over
    # every room outranks them all. A tie goes to the latest claim. The song
    # crossfades only when the winner changes, over the `fade:` of the call
    # that changed it. While any claim holds, `play_music`, `crossfade` and
    # `stop_music` raise: a song with two owners would be fought over without
    # a word. A game uses claims or those calls, not both.
    class AudioOut < Component
      Claim = Struct.new(:song, :priority)
      private_constant :Claim

      # `audio` is the sound device: anything answering the calls below by name,
      # as RGame::Core::Audio does.
      def initialize(audio)
        super()
        @rgame_audio = audio
        @rgame_rise = Engine::Tween.new(1.0, to: 1.0)
        @rgame_fall = Engine::Tween.new(1.0, to: 0.0)
        @rgame_rising = nil
        @rgame_falling = nil
        @rgame_current = nil
        @rgame_paused = false
        @rgame_claims = {}
        @rgame_claimed = nil
      end

      def play_sound(id) = @rgame_audio.play_sound(id)

      # Plays a song looping and makes it the current one. With `fade:` it
      # comes up from silence over that many seconds; with none, the device is
      # sent exactly the one call it would be sent without a fade. A song on its
      # way out comes back up from where it is, rather than starting again.
      def play_music(id, fade: 0)
        unclaimed!(:play_music)
        start_music(id, seconds!(:fade, fade))
      end

      # Stops the current song, or with `fade:` lowers it to silence over that
      # many seconds and stops it on the tick it arrives. A song still on its
      # way out of a crossfade stops at once.
      def stop_music(fade: 0)
        unclaimed!(:stop_music)
        end_music(seconds!(:fade, fade))
        nil
      end

      # Lowers the current song and raises `id` over the same `over` seconds,
      # and stops the old song once it is silent. With no current song it is a
      # fade in. A crossfade begun before the last one ended stops the song
      # still on its way out, and brings the one that was coming in down from
      # where it is.
      def crossfade(id, over:)
        unclaimed!(:crossfade)
        cross_to(id, seconds!(:over, over))
      end

      # Claims the music for `key`, any object, with the song `id` at
      # `priority`. Claiming a key again replaces its song and priority, and
      # makes it the latest claim. When the song the claims choose changes, it
      # crossfades over `fade` seconds.
      def claim_music(key, id, priority: 0, fade: 0)
        raise ArgumentError, "claim_music(#{key.inspect}) needs a song, not nil" if id.nil?
        raise TypeError, "a claim's priority is a number, not #{priority.inspect}" unless priority.is_a?(Numeric)

        seconds = seconds!(:fade, fade)
        @rgame_claims.delete(key)
        @rgame_claims[key] = Claim.new(id, priority)
        follow_claims(seconds)
        self
      end

      # Ends the claim each key holds, if it holds one. When the song the
      # claims choose changes, it crossfades over `fade` seconds. Several keys
      # released in one call change the song once, to what the claims left
      # choose. Releasing the last claim fades the music to silence and stops
      # it.
      def release_music(*keys, fade: 0)
        seconds = seconds!(:fade, fade)
        released = false
        keys.each { released = true if @rgame_claims.delete(it) }
        follow_claims(seconds) if released
        self
      end

      # The song the claims chose, or nil while nothing claims the music.
      def claimed_music = @rgame_claimed

      # Holds the music and its fade where they are: the current song, or the
      # song a `stop_music(fade:)` is lowering. A song on its way out of a
      # crossfade stops at once.
      def pause_music
        stop_now(@rgame_falling) if @rgame_falling && @rgame_current
        @rgame_audio.pause_music
        @rgame_paused = true
      end

      # Carries the song and its fade on from where #pause_music held them.
      def resume_music
        @rgame_audio.resume_music
        @rgame_paused = false
      end

      def category_volume(name) = @rgame_audio.category_volume(name)
      def set_category_volume(name, volume) = @rgame_audio.set_category_volume(name, volume)

      # Whether a song is on its way up or down.
      def fading? = !(@rgame_rising.nil? && @rgame_falling.nil?)

      def _update(dt)
        return if @rgame_paused

        step_rise(dt) if @rgame_rising
        step_fall(dt) if @rgame_falling
      end

      private

      def start_music(id, seconds)
        level = level_of(id)
        @rgame_falling = nil if @rgame_falling == id
        bring_in(id, level, seconds)
      end

      def end_music(seconds)
        if seconds.zero?
          stop_at_once
        elsif @rgame_current
          fade_out(@rgame_current, seconds)
        end
      end

      def cross_to(id, seconds)
        return start_music(id, seconds) if @rgame_current.nil? || @rgame_current == id

        level = level_of(id)
        @rgame_falling = nil if @rgame_falling == id
        fade_out(@rgame_current, seconds)
        bring_in(id, level, seconds)
      end

      def follow_claims(seconds)
        winner = winning_song
        return if winner == @rgame_claimed

        @rgame_claimed = winner
        winner.nil? ? end_music(seconds) : cross_to(winner, seconds)
      end

      def winning_song
        best = nil
        @rgame_claims.each_value { |claim| best = claim if best.nil? || claim.priority >= best.priority }
        best&.song
      end

      def unclaimed!(call)
        return if @rgame_claims.empty?

        raise "#{call} while the music is claimed by #{@rgame_claims.keys.map(&:inspect).join(', ')}. " \
              'A game uses claims or the direct calls, not both: claim_music the song instead'
      end

      def level_of(id)
        return nil if id.nil?
        return @rgame_rise.value if id == @rgame_rising
        return @rgame_fall.value if id == @rgame_falling

        1.0 if id == @rgame_current
      end

      def bring_in(id, level, seconds)
        settle_rise unless @rgame_rising == id
        @rgame_audio.set_music_volume(id, 0.0) if level.nil? && seconds.positive?
        @rgame_audio.play_music(id)
        @rgame_current = id
        @rgame_paused = false
        level ||= seconds.positive? ? 0.0 : 1.0
        return if level >= 1.0

        seconds.positive? ? start_rise(id, level, seconds) : settle(id)
      end

      def fade_out(id, seconds)
        level = level_of(id)
        stop_now(@rgame_falling) if @rgame_falling
        @rgame_rising = nil if @rgame_rising == id
        @rgame_current = nil
        return stop_now(id) if seconds.zero?

        @rgame_falling = id
        @rgame_fall.from = level
        @rgame_fall.duration = seconds
        @rgame_fall.restart
      end

      def start_rise(id, level, seconds)
        @rgame_rising = id
        @rgame_rise.from = level
        @rgame_rise.duration = seconds
        @rgame_rise.restart
      end

      def settle(id)
        @rgame_rising = nil if @rgame_rising == id
        @rgame_audio.set_music_volume(id, 1.0)
      end

      def settle_rise
        settle(@rgame_rising) if @rgame_rising
      end

      def stop_now(id)
        @rgame_falling = nil if @rgame_falling == id
        @rgame_audio.stop_music(id)
        @rgame_audio.set_music_volume(id, 1.0)
      end

      def stop_at_once
        stop_now(@rgame_falling) if @rgame_falling
        level = level_of(@rgame_current)
        @rgame_audio.stop_music
        @rgame_audio.set_music_volume(@rgame_current, 1.0) if level && level < 1.0
        @rgame_rising = nil
        @rgame_current = nil
        @rgame_paused = false
      end

      def step_rise(dt)
        @rgame_audio.set_music_volume(@rgame_rising, @rgame_rise.update(dt).value)
        @rgame_rising = nil if @rgame_rise.done?
      end

      def step_fall(dt)
        @rgame_audio.set_music_volume(@rgame_falling, @rgame_fall.update(dt).value)
        stop_now(@rgame_falling) if @rgame_fall.done?
      end

      def seconds!(name, value)
        return value if value.is_a?(Numeric) && value >= 0

        raise ArgumentError, "#{name}: must be 0 or more seconds, not #{value.inspect}"
      end
    end
  end
end
