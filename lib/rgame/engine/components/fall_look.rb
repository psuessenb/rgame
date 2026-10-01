# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What a fall looks like: a shrink, a splash, a burn. The node's Fall calls
      # #start as a fall starts, #show every tick of it with how far through the
      # fall it is, from 0 to 1, and #finish once as it ends, however it ends.
      #
      #   hero.add_component(Fall.new)
      #   hero.add_component(Shrink.new)
      #
      # Each does nothing here, and a look overrides what it needs. Components::Shrink
      # is the one rgame ships.
      #
      # **The node is suspended all the while**, so a look never counts time itself:
      # its `_update` does not run, and `progress` is its clock. Its `_draw` still
      # runs, as a suspended node still draws, so a look may draw what it likes.
      #
      # A node holds one look, and a Fall raises as it starts on a node with two. A
      # look that leaves its node mid-fall is shown no more, and gets no #finish: its
      # own `_detach` gives back what it changed.
      class FallLook < Engine::Component
        # A fall starts. The look finds what it will change, such as the scale.
        def start; end

        # `progress` runs from 0 at the fall's start to 1 at its end.
        def show(progress); end

        # The fall ended: the node comes back, is freed, or left the tree. The look
        # gives back what it changed.
        def finish; end
      end
    end
  end
end
