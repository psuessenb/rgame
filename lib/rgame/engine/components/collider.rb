# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What BoxCollider and CircleCollider both are: a shape on a node that
      # registers with the scene's CollisionWorld and reports its contacts.
      #
      # It declares nothing. The two colliders already answer the same
      # broadphase (`aabb_x`, `cx`), narrowphase (`overlap?`) and contact
      # (`on_hit`, `on_separated`, `layer`) protocol, and CollisionWorld has
      # always called them by name without asking which it held. This is the
      # name for that, so a component wanting *the collider on this node*
      # whatever its shape can say so:
      #
      #   def _attach = @collider = require_sibling(Collider)
      #
      # Without it `require_sibling` takes a class, and naming either one would
      # rule the other out — a coin is round and a chest is not, and Collectable
      # has no opinion about which.
      #
      # A node carrying both matches twice and `require_sibling` raises, which
      # is the right answer: there is no telling which shape was meant.
      module Collider; end
    end
  end
end
