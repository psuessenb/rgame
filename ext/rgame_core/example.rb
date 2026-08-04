# frozen_string_literal: true

# Manual/visual smoke test for the core extension (layer 3 — the real
# SDL/GL path). Build it first, then run this from the project root:
#
#   make ext-core
#   ruby ext/rgame_core/example.rb
#
# It opens a window with one of each drawing primitive in it. Arrow keys (or a
# controller's dpad/stick) move the marker; Escape or closing the window quits.
# This is the Ruby-side mirror of src/main.c, and it exists to exercise every
# callback and every draw call the engine offers.
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
  Color = RGame::Util::Color

  RED = Color.new(224, 64, 64)
  GREEN = Color.new(64, 224, 96)
  BLUE = Color.new(64, 96, 224)
  YELLOW = Color.new(224, 192, 64)
  TRANSLUCENT_WHITE = Color.new(255, 255, 255, 128)

  attr_reader :frames, :ticks, :cursor_x, :cursor_y

  def initialize
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
    @spin += dt * 45.0
    speed = 200.0 * dt
    @cursor_x -= speed if @input.down?(:left, device: @device)
    @cursor_x += speed if @input.down?(:right, device: @device)
    @cursor_y -= speed if @input.down?(:up, device: @device)
    @cursor_y += speed if @input.down?(:down, device: @device)

    # Analog sticks are additive on top of the dpad; the keyboard reads 0.0.
    @cursor_x += @input.axis(:move_x, device: @device) * speed
    @cursor_y += @input.axis(:move_y, device: @device) * speed
  end

  # One of everything, so a look at the window checks the whole drawing path.
  # Colours are RGame::Util::Color values rather than arrays: a Color is frozen
  # and allocates nothing when it is drawn, which is what per-frame code wants.
  def draw
    r = @renderer

    # Baked on the first frame and replayed after that: forty rectangles cost
    # one call per frame instead of forty. A real game bakes its tile layers
    # this way. Recording has to happen inside #draw, which is why it is here
    # rather than in initialize.
    @baked ||= r.record do
      40.times { |i| r.rect(i * 18, 0, 12, 12, color: GREEN, z: 0) }
    end
    # Scrolls with the same value the spinning square turns by, so it is
    # visibly the *replay* moving and not a rebake.
    @baked.draw((@spin % 18) - 18, 560)
    r.rect(40, 40, 160, 100, color: RED, z: 0)
    # Higher z wins wherever they overlap, whatever order the calls came in.
    r.rect(120, 90, 160, 100, color: TRANSLUCENT_WHITE, z: 1)
    r.triangle(400, 40, 480, 180, 320, 180, color: GREEN, z: 0)
    r.circle(620, 110, 70, color: BLUE, z: 0)
    r.line(40, 240, 760, 240, thickness: 6, color: YELLOW, z: 0)

    # The transform stack: a square turning about its own centre.
    r.rotated(@spin, 400, 380) { r.rect(340, 320, 120, 120, color: GREEN, z: 0) }

    # The clip stack: the rectangle is twice the size of what shows.
    r.clipped(60, 480, 200, 80) { r.rect(60, 440, 400, 160, color: RED, z: 0) }

    # The cursor the arrow keys move.
    r.debug_box(@cursor_x - 8, @cursor_y - 8, 16, 16)

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
            app.frames, app.ticks, app.cursor_x, app.cursor_y, app.fps)
