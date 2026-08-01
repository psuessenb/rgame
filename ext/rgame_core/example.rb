# frozen_string_literal: true

# Manual/visual smoke test for the core extension (layer 3 — the real
# SDL/GL path). Build it first, then run this from the project root:
#
#   make ext-core
#   ruby ext/rgame_core/example.rb
#
# It opens a window showing the engine's clear color. Arrow keys (or a
# controller's dpad/stick) move an invisible cursor whose position prints on
# exit; Escape or closing the window quits. This is the Ruby-side mirror of
# src/main.c, and it exists to exercise every callback the engine offers.
#
# The load path points at lib/, not at this directory: `make ext-core`
# copies the built core_ext.so to lib/rgame/, so this runs against exactly
# the layout a user of the library would see.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame'
require 'rgame/core'

# An App subclass overrides only the hooks it needs; the rest are inherited
# no-ops, so this class is the smallest useful driver of the engine.
class Example < RGame::Core::App
  Controls = RGame::Util::Controls

  attr_reader :frames, :ticks, :x, :y

  def initialize
    super(width: 800, height: 600, caption: 'rgame via Ruby')
    @input = RGame::Core::Input.new(self)
    @pads = RGame::Core::Gamepad.new(self)
    @frames = 0
    @ticks = 0
    @x = 0.0
    @y = 0.0
    @device = Controls::KEYBOARD
  end

  # Once per frame, before the tick batch: pick which device to read. Doing it
  # here rather than per tick is the pattern the engine is shaped around — one
  # sample per frame, reused by however many catch-up ticks follow.
  def frame_begin
    # Poll rather than track: Gamepad answers straight from the engine, so
    # there is no local copy of the connection state to keep in step.
    @device = @pads.connected?(0) ? @pads.device(0) : Controls::KEYBOARD
  end

  # One fixed simulation tick. dt is always the engine's fixed step.
  def update(dt)
    @ticks += 1
    speed = 200.0 * dt
    @x -= speed if @input.down?(:left, device: @device)
    @x += speed if @input.down?(:right, device: @device)
    @y -= speed if @input.down?(:up, device: @device)
    @y += speed if @input.down?(:down, device: @device)

    # Analog sticks are additive on top of the dpad; the keyboard reads 0.0.
    @x += @input.axis(:move_x, device: @device) * speed
    @y += @input.axis(:move_y, device: @device) * speed
  end

  def draw
    @frames += 1
  end

  def button_down(id)
    close if id == Controls::KEY_ESCAPE
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

app = Example.new
app.run

puts format('drew %d frames, ran %d ticks, cursor at (%.1f, %.1f), last fps: %.1f',
            app.frames, app.ticks, app.x, app.y, app.fps)
