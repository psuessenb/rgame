# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame'
require 'rgame/core'

# An App subclass overrides only the hooks it needs; the rest are inherited
# no-ops, so this class is the smallest useful driver of the engine.
class Example < RGame::Core::App
  Controls = RGame::Util::Controls
  Color = RGame::Util::Color

  RED = Color.new(224, 64, 64)
  GREEN = Color.new(64, 224, 96)
  BLUE = Color.new(64, 96, 224)
  YELLOW = Color.new(224, 192, 64)
  TRANSLUCENT_WHITE = Color.new(255, 255, 255, 128)

  AUDIO_HINT_NONE = 'audio: pass a sound file on the command line to try it'
  AUDIO_HINT_STOPPED = 'audio: Space plays a sample, Return starts the music'
  AUDIO_HINT_PLAYING = 'audio: Space plays a sample, Return stops the music'

  attr_reader :frames, :ticks, :cursor_x, :cursor_y

  def initialize(sound_path = nil)
    super(width: 800, height: 600, caption: 'rgame via Ruby')
    @input = RGame::Core::Input.new(self)
    @pads = RGame::Core::Gamepad.new(self)
    @renderer = RGame::Core::Renderer.new(self)
    @frames = 0
    @ticks = 0
    @cursor_x = 400.0
    @cursor_y = 300.0
    @spin = 0.0
    @baked = nil
    @device = Controls::KEYBOARD

    @audio = RGame::Core::Audio.new
    puts "audio backend: #{@audio.backend}"
    return unless sound_path

    @sample = RGame::Core::Sample.new(@audio, sound_path)
    @song = RGame::Core::Song.new(@audio, sound_path)
  end

  # Once per frame, before the tick batch: pick which device to read. Doing it
  # here rather than per tick is the pattern the engine is shaped around — one
  # sample per frame, reused by however many catch-up ticks follow.
  def frame_begin
    @device = @pads.connected?(0) ? @pads.device(0) : Controls::KEYBOARD
  end

  # One fixed simulation tick. dt is always the engine's fixed step.
  def update(dt)
    @ticks += 1
    @spin += dt * 45.0
    speed = 200.0 * dt
    @cursor_x -= speed if held?(Controls::KEY_LEFT, Controls::PAD_DPAD_LEFT)
    @cursor_x += speed if held?(Controls::KEY_RIGHT, Controls::PAD_DPAD_RIGHT)
    @cursor_y -= speed if held?(Controls::KEY_UP, Controls::PAD_DPAD_UP)
    @cursor_y += speed if held?(Controls::KEY_DOWN, Controls::PAD_DPAD_DOWN)

    @cursor_x += @input.axis(Controls::AXIS_LEFT_X, device: @device) * speed
    @cursor_y += @input.axis(Controls::AXIS_LEFT_Y, device: @device) * speed
  end

  # Core is the raw layer: Input answers "is this scancode down on this device",
  # and naming the key *and* the pad button for one intent is the caller's job.
  # Asking both costs nothing, because a device only answers for its own kind of
  # input — a gamepad reads false for a scancode.
  #
  # A game does not write this. RGame::Engine::InputMap is a table of exactly
  # these pairs, one entry per action, and the scene graph reads named actions
  # instead. This example is here to exercise Core on its own, so it does
  # without that and shows what the layer above is for.
  def held?(key, pad) = @input.down?(key, device: @device) || @input.down?(pad, device: @device)

  # One of everything, so a look at the window checks the whole drawing path.
  # Colours are RGame::Util::Color values rather than arrays: a Color is frozen
  # and allocates nothing when it is drawn, which is what per-frame code wants.
  def draw
    r = @renderer

    @baked ||= r.record do
      40.times { |i| r.rect(i * 18, 0, 12, 12, color: GREEN, z: 0) }
    end
    @baked.draw((@spin % 18) - 18, 560)
    r.rect(40, 40, 160, 100, color: RED, z: 0)
    r.rect(120, 90, 160, 100, color: TRANSLUCENT_WHITE, z: 1)
    r.triangle(400, 40, 480, 180, 320, 180, color: GREEN, z: 0)
    r.circle(620, 110, 70, color: BLUE, z: 0)
    r.line(40, 240, 760, 240, thickness: 6, color: YELLOW, z: 0)

    r.rotated(@spin, 400, 380) { r.rect(340, 320, 120, 120, color: GREEN, z: 0) }

    r.clipped(60, 480, 200, 80) { r.rect(60, 440, 400, 160, color: RED, z: 0) }

    r.debug_box(@cursor_x - 8, @cursor_y - 8, 16, 16)

    r.text('rgame — Grüße, œuvre, 5 €', 40, 270, color: YELLOW)
    label = format('%d fps', fps)
    r.text(label, 400 - (r.text_width(label) / 2), 270 + r.text_height)
    r.text(audio_status, 40, 270 + (r.text_height * 2), color: YELLOW)

    @frames += 1
  end

  def button_down(id)
    case id
    when Controls::KEY_ESCAPE then close
    when Controls::KEY_SPACE then @sample&.play
    when Controls::KEY_RETURN then toggle_music
    end
  end

  # Return is a toggle, so one key covers both transitions and the "play after
  # stop starts from the beginning" behaviour is audible by pressing it twice.
  def toggle_music
    return unless @song

    @song.playing? ? @song.stop : @song.play(looping: true)
  end

  def audio_status
    return AUDIO_HINT_NONE unless @song

    @song.playing? ? AUDIO_HINT_PLAYING : AUDIO_HINT_STOPPED
  end

  # The callbacks are for reacting to the change; the polling above is for
  # reading the current state. Slots are stable across a replug, so a pad that
  # falls out and returns comes back as the same player.
  def gamepad_connected(slot)
    puts "controller connected in slot #{slot}: #{@pads.name(slot)}"
  end

  def gamepad_disconnected(slot)
    puts "controller disconnected from slot #{slot}"
  end

  def resize(width, height)
    puts "resized to #{width}x#{height}"
  end
end

app = Example.new(ARGV[0])
app.run

puts format('drew %d frames, ran %d ticks, cursor at (%.1f, %.1f), last fps: %.1f',
            app.frames, app.ticks, app.cursor_x, app.cursor_y, app.fps)
