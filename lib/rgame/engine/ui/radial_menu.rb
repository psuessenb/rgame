# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A wheel: a Menu with its buttons on a UI::Ring and focus chosen by
      # UI::Pointing, drawing its own backdrop disc, the dead zone to scale, and
      # a pointer from the centre towards where the stick aims.
      #
      #   wheel = layer.add_node(UI::RadialMenu.new(x: 320, y: 240, radius: 150, button_width: 64))
      #   wheel.add(UI::IconButton.new(image: :home, style: UI::ShapeStyle.new(shape: :disc)))
      #
      # The menu's origin is the centre of the wheel. The backdrop is sized from
      # the ring's bounds — the square enclosing every slot, whatever the number
      # of buttons — plus `padding`, so it does not change size as buttons are
      # added. The pointer's tip is clamped to the ring: two arrow keys read as
      # (1, 1), which is longer than a stick can reach.
      #
      # `backdrop:`, `dead_zone_color:` and `pointer:` are colours, and `nil`
      # omits that part. The buttons are children, so they draw over all three.
      #
      # `trigger:` makes it the wheel held open by a button — see UI::Menu, "A
      # menu held open by an action" — and `grace:` is its UI::Pointing's, which
      # already defaults to `Pointing::GRACE` on a menu with a trigger.
      #
      # It builds its own layout and navigation, so passing `layout:` or
      # `navigation:` raises ArgumentError: forwarded on, either would silently
      # replace the ring or the pointing this class is made of. A wheel stepped
      # through with the default navigation is a UI::Menu with a UI::Ring.
      class RadialMenu < Menu
        BACKDROP = Util::Color.new(44, 40, 52)
        DEAD_ZONE = Util::Color.new(76, 72, 88)
        POINTER = Util::Color.new(240, 236, 224)

        POINTER_THICKNESS = 3.0
        POINTER_TIP_RADIUS = 6

        attr_reader :padding, :backdrop, :dead_zone_color, :pointer

        def initialize(radius:, button_width:, button_height: button_width, dead_zone: Pointing::DEAD_ZONE,
                       grace: nil, padding: 16, backdrop: BACKDROP, dead_zone_color: DEAD_ZONE, pointer: POINTER,
                       **options)
          refuse_preset_keywords(options)
          super(layout: Ring.new(radius: radius, item_width: button_width, item_height: button_height),
                navigation: Pointing.new(dead_zone: dead_zone, grace: grace), **options)
          @padding = padding
          @backdrop = backdrop&.then { Util::Color.coerce(it) }
          @dead_zone_color = dead_zone_color&.then { Util::Color.coerce(it) }
          @pointer = pointer&.then { Util::Color.coerce(it) }
        end

        def _draw(renderer, _view)
          radius = layout.radius
          renderer.circle(0, 0, backdrop_radius, color: @backdrop) if @backdrop
          renderer.circle(0, 0, navigation.dead_zone * radius, color: @dead_zone_color) if @dead_zone_color
          draw_pointer(renderer, radius) if @pointer
        end

        # The radius of the disc drawn behind the ring: half the larger side of
        # the bounds, plus `padding`.
        def backdrop_radius
          ([bounds_width, bounds_height].max / 2.0) + @padding
        end

        private

        def refuse_preset_keywords(options)
          return unless options.key?(:layout) || options.key?(:navigation)

          raise ArgumentError, 'a RadialMenu builds its own layout: and navigation:; use UI::Menu to choose them'
        end

        def draw_pointer(renderer, radius)
          aim_x = navigation.aim_x
          aim_y = navigation.aim_y
          reach = radius / [Math.hypot(aim_x, aim_y), 1.0].max
          tip_x = aim_x * reach
          tip_y = aim_y * reach
          renderer.line(0, 0, tip_x, tip_y, thickness: POINTER_THICKNESS, color: @pointer)
          renderer.circle(tip_x, tip_y, POINTER_TIP_RADIUS, color: @pointer)
        end
      end
    end
  end
end
