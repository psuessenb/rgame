# frozen_string_literal: true

module RGame
  module Util
    # The vocabulary of draw order: which band a thing is drawn in, and how the
    # single number the renderer sorts on is built out of one.
    #
    #   RGame::Util::Z::BANDS          # => [:world, :hud, :overlay, :debug]
    #   RGame::Util::Z.base(:hud, 3)   # the fourth slot handed out in the HUD band
    #
    # These are values — plain Symbols and Integers with no window, GPU or OS
    # handle behind them — so they live here rather than in Core, and both sides
    # of the line may name them. `RGame::Engine` decides which band a node is
    # in; `RGame::Core::Renderer` turns that into a z. Neither could reach the
    # other's spelling of it, and the vocabulary is exactly what they have to
    # agree on. Same reasoning as RGame::Util::Controls.
    #
    # ## Draw order is tree order, not a number a caller picks
    #
    # A frame's order is decided in three steps, coarsest first:
    #
    # 1. **The band.** Structural and inherited: everything in `:world` is under
    #    everything in `:hud`, whatever either drew. Bands are 2**40 apart, so
    #    no arithmetic below can carry one into the next.
    # 2. **The slot.** The scene graph is walked depth-first with siblings in
    #    `z` order, and each node takes the next slot in its band as it is
    #    reached. Because the walk descends fully before moving on, a node's
    #    subtree occupies one contiguous run of slots — which is what makes a
    #    subtree atomic, and what stops some of a node's children landing in
    #    front of a sibling the node itself is behind.
    # 3. **The offset.** `Z_MIN..Z_MAX` inside the node's own slot, and the only
    #    part a `z:` argument on a drawing call touches. It orders a node's
    #    components against each other and its own draw calls against each
    #    other, and it cannot reach the next node, let alone the next band.
    #
    # So a node's `z` is **only ever compared to its siblings'**. Its magnitude
    # means nothing: `z: 1` and `z: 1_000_000` behave identically if they are
    # the only two children, and negatives are ordinary.
    #
    # ## The arithmetic is exact
    #
    # Every value here is an integer below 2**42, and the `double` the draw
    # queue sorts on is exact below 2**53. Two different slots can therefore
    # never compare equal by rounding — which would show up as two sprites
    # swapping places between frames, and would be very hard to see as a
    # precision problem.
    module Z
      # How much room a node has for ordering its own drawing. Nothing in this
      # repo uses more than three offsets; a thousand is room to stop thinking
      # about it.
      SLOT = 1024
      HALF = SLOT / 2

      # What a `z:` argument on a drawing call may be. Signed, because a node
      # drawing something *behind* its sprite is as ordinary as drawing
      # something in front of it, and the sprite's own default is 0.
      Z_MIN = -HALF
      Z_MAX = HALF - 1

      # The gap between bands: 2**30 slots each, which no frame will approach.
      STRIDE = 1 << 40
      SLOTS_PER_BAND = STRIDE / SLOT

      # In order, back to front.
      #
      # `:world` is what a node with no band ancestor is in, so a game that
      # never mentions a band is entirely in it. `:hud` is one player's own
      # screen space (RGame::Engine::PlayerLayer), `:overlay` is screen space
      # across the whole window — a cutscene, a results panel — and `:debug` is
      # the development overlay, over everything by construction.
      BANDS = %i[world hud overlay debug].freeze
      DEFAULT = :world

      INDICES = BANDS.each_with_index.to_h.freeze

      def self.band?(band) = INDICES.key?(band)

      # Raises unless `band` names one. Called where a band is *set* rather than
      # where it is used, so a typo surfaces at assignment with the list in the
      # message instead of as a KeyError from inside a draw.
      def self.band!(band)
        return band if band?(band)

        raise ArgumentError, "unknown z band #{band.inspect}; expected one of #{BANDS.inspect}"
      end

      # Which band this is, 0-based and back to front. This is what a renderer's
      # slot counters are keyed on, so it is also where a bad band is caught.
      def self.index(band)
        INDICES[band] || band!(band)
      end

      # The z base of the `slot_index`-th slot in the band with that index.
      # Offsets are measured from the middle of the slot, so Z_MIN..Z_MAX is
      # symmetric — a node can draw behind its own sprite as easily as in front.
      #
      # Takes the band's *index* rather than its name because a renderer already
      # has the index in hand (it counts slots per index), and looking the same
      # Symbol up twice per node per frame is work with nothing to show for it.
      # hot-path
      def self.slot_base(band_index, slot_index)
        if slot_index >= SLOTS_PER_BAND
          raise RangeError,
                "z band #{BANDS[band_index].inspect} is full at " \
                "#{SLOTS_PER_BAND} slots per frame"
        end

        (band_index * STRIDE) + (slot_index * SLOT) + HALF
      end

      # The same thing by name, for a caller that has one rather than an index.
      def self.base(band, slot_index) = slot_base(index(band), slot_index)

      # Checks a `z:` argument and returns it. Drawing methods run this instead
      # of trusting the caller, because the whole guarantee — that a node cannot
      # draw outside its band — rests on the offset staying inside one slot.
      # A stale global z (the bands used to be Integers a caller passed) lands
      # here and says so rather than sorting somewhere surprising.
      # hot-path
      def self.offset(z)
        raise TypeError, "no implicit conversion of #{z.class} into Float" unless z.is_a?(Numeric)

        unless z.between?(Z_MIN, Z_MAX)
          raise ArgumentError,
                "z: #{z} is outside a node's slot (#{Z_MIN}..#{Z_MAX}); a `z:` orders one " \
                'node\'s own drawing, and the band comes from the tree'
        end

        z
      end
    end
  end
end
