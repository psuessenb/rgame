# frozen_string_literal: true

module RGame
  module Engine
    # Where each band of a frame sits in the draw order.
    #
    #   renderer.text(score, 12, 10, z: Z::HUD)
    #   renderer.nine_slice(:panel, x, y, w, h, z: Z::OVERLAY)
    #
    # The renderer sorts every command in a frame by `z` and draws low to high,
    # so the order calls are *issued* in does not matter — which is what lets a
    # tile map's canopies be drawn before the actors they cover. What does
    # matter is that the numbers agree, and until split-screen every one of them
    # was picked by hand in the file that used it.
    #
    # ## Why this needs stating now
    #
    # A frame has three kinds of content and they are drawn different numbers of
    # times. **World** content is drawn once per viewport, inside a WorldView.
    # A **player's own screen space** — their HUD, their inventory — is drawn
    # once, clipped to their viewport. **Global screen space** — a cutscene, a
    # results panel — is drawn once across the whole window.
    #
    # Two viewports interleaving in the sort is harmless: their commands carry
    # different clips and land on different pixels. Band order *within* one
    # viewport is not harmless, and nothing about drawing a HUD after the world
    # makes it appear above the world. Only its z does.
    #
    # ## The bands
    #
    # Bases, not slots: a HUD element three layers up is `Z::HUD + 3`. They are
    # far apart because the gaps are what a game gets to use.
    #
    # | Band | Base | Drawn |
    # |---|---|---|
    # | `WORLD` | 0 | once per viewport, under a camera |
    # | `HUD` | 100_000 | once per player, in their viewport |
    # | `OVERLAY` | 200_000 | once, across the whole window |
    # | `DEBUG` | 1_000_000 | last, over everything |
    #
    # ## Nothing enforces this
    #
    # There is no machinery here on purpose. A z is an Integer a caller passes,
    # and no guard can tell a HUD apart from a rock. What the constants buy is
    # that the numbers are decided once, in one place, with the reasoning next
    # to them — rather than in whichever file needed one first.
    #
    # **Mind the renderer's own defaults**, which predate this and are all inside
    # the world band: images at 0, text at 10, shapes at 50. So a shape drawn
    # with no `z:` sits *above* text drawn with no `z:`, and a HUD built out of
    # defaults ends up under world shapes. Naming a band fixes that; leaving it
    # to the defaults does not.
    #
    # The world band's headroom is the whole of 0...100_000, which is four
    # orders of magnitude more than the largest default. A game that needs more
    # than that is doing something this vocabulary cannot help with.
    module Z
      WORLD = 0
      HUD = 100_000
      OVERLAY = 200_000
      DEBUG = 1_000_000
    end
  end
end
