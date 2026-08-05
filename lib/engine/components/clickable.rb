# frozen_string_literal: true

module Engine
  module Components
    # Makes the owning node a click target. On the click-down edge it hit-tests the
    # pointer against a circle of `radius` about the node's absolute origin and emits
    # `on_clicked`. Like a button, it carries no payload — the owning node identifies the
    # click (`spot.on_clicked { build_tower }`).
    #
    # It reads the pointer straight from the Actions snapshot, so it assumes screen ==
    # world: fine for a fixed, unscrolled board. Under a scrolling camera the pointer
    # would need unprojecting first; that's a later addition.
    #
    # Add it named (`as:`) like any component when a node needs more than one click
    # region. Binding required: an action (default `:ui_click`) mapped to the pointer
    # button — `action_map: { ui_click: { button: %i[pointer] } }`.
    class Clickable < Engine::Component
      signal :on_clicked # emits no payload; the owning node identifies the click

      attr_accessor :radius

      def initialize(radius:, action: :ui_click)
        super()
        @radius = radius
        @action = action
      end

      # Resolve happens before components, so node.abs_x/abs_y are current here.
      def control(actions)
        return unless actions.pressed?(@action)
        return unless hit?(actions.pointer_x, actions.pointer_y)

        on_clicked_signal.emit
      end

      private

      def hit?(px, py)
        dx = px - node.abs_x
        dy = py - node.abs_y
        ((dx * dx) + (dy * dy)) <= (@radius * @radius)
      end
    end
  end
end
