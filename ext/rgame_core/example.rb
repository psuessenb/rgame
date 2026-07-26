# frozen_string_literal: true

# Manual/visual smoke test for the core extension (layer 3 — the real
# SDL/GL path). Build it first, then run this from the project root:
#
#   make ext-core
#   ruby ext/rgame_core/example.rb
#
# It opens a window that shows the engine's clear color. Press Escape or close
# the window to quit; F1 toggles a counter printed on the way out. This is the
# Ruby-side mirror of src/main.c, and it exists to exercise every callback the
# engine offers.
#
# The load path points at lib/, not at this directory: `make ext-core`
# copies the built core_ext.so to lib/rgame/, so this runs against exactly
# the layout a user of the library would see.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/core'

# Button ids are SDL scancodes. The input layer will replace these with named
# RGame::Core::Input::KEY_* constants; until it exists, a driver that wants to
# name a key spells it out. The C side keeps these two honest with a
# _Static_assert against SDL (see ext/rgame_core/app.c).
KEY_ESCAPE = 41
KEY_F1 = 58

# An App subclass overrides only the hooks it needs; the rest are inherited
# no-ops, so this class is the smallest useful driver of the engine.
class Example < RGame::Core::App
  attr_reader :frames, :ticks

  def initialize
    super(width: 800, height: 600, caption: 'rgame via Ruby')
    @frames = 0
    @ticks = 0
    @verbose = false
  end

  # One fixed simulation tick. dt is always the engine's fixed step, never
  # wall-clock frame time.
  def update(_dt)
    @ticks += 1
  end

  def draw
    @frames += 1
  end

  def button_down(id)
    case id
    when KEY_ESCAPE then close
    when KEY_F1 then toggle_verbose
    end
  end

  def resize(width, height)
    puts "resized to #{width}x#{height}"
  end

  private

  def toggle_verbose
    @verbose = !@verbose
    puts "verbose: #{@verbose}"
  end
end

app = Example.new
app.run

puts "drew #{app.frames} frames, ran #{app.ticks} ticks, last fps: #{app.fps.round(1)}"
