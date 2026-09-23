# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A thing that is taken by being touched.
      #
      #   coin.add_component(Collectable.new(by: :hero, sound: :blip))
      #       .on_collected { |_other| purse.add(:coin) }
      #
      #   chest.add_component(Collectable.new(by: :hero, free: false))
      #
      # It listens to its own node's collider and acts on the step a collider on
      # the `by` layer starts overlapping it: emit `collected`, play `sound`
      # through the tree's AudioOut if it was given one, and free the node unless
      # `free: false`. `on_hit` is an edge, so standing on a coin takes it once.
      #
      # **The collectable does the collecting**, rather than the hero holding a
      # list of what it may pick up. What a coin is worth belongs to the coin,
      # and a game adds one by adding a node — nothing elsewhere changes.
      #
      # `free: false` is the chest: it reports the touch and stays, and whatever
      # listens decides what opening means. That is also the shape a door takes.
      #
      # `sound:` is a declaration that this makes a noise, so it is looked up
      # with `system!` and a scene with no AudioOut raises rather than going
      # quietly missing — the same trade `blocked_by` takes. A collectable given
      # no sound never looks one up, and needs no AudioOut at all. The lookup
      # happens on the pickup rather than on attach because a pickup is rare,
      # and nothing here runs per frame.
      #
      # The shape may be either collider, because a coin is round and a chest is
      # not — see Collider. A node carrying both raises, since there is no
      # telling which was meant.
      #
      # ## What it connects, it disconnects
      #
      # `_attach` connects to the collider and `_detach` ends that connection,
      # so a pooled node taken twice fires twice rather than three times. Every
      # component that connects to a sibling has to do this by hand today; a
      # connection that ends with its node is a change to Signal rather than to
      # each owner, and is recorded as a possible-todo.
      class Collectable < Engine::Component
        # The collider that touched this, so a listener can read its node and
        # layer. Emitted before the node is freed.
        signal :collected, :other

        # `by` is the layer whose colliders take this; every other layer is
        # ignored. `sound` is a sound id, or nil for a silent pickup. `free:
        # false` keeps the node, for something that is opened rather than taken.
        def initialize(by:, sound: nil, free: true)
          super()
          @by = by
          @sound = sound
          @free = free
        end

        def _attach
          @collider = require_sibling(Collider)
          @handle = @collider.on_hit { |other| take(other) if other.layer == @by }
        end

        def _detach
          @collider&.disconnect_hit(@handle)
          @collider = nil
          @handle = nil
        end

        private

        def take(other)
          collected_signal.emit(other)
          node.system!(AudioOut).play_sound(@sound) if @sound
          node.queue_free if @free
        end
      end
    end
  end
end
