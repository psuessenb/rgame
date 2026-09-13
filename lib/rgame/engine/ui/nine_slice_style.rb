# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A button background drawn from a UI atlas: one nine-slice element per
      # state, stretched over the button's whole slot.
      #
      #   style = UI::NineSliceStyle.new(idle: :button_idle, focused: :button_focus,
      #                                  pressed: :button_pressed, disabled: :button_disabled)
      #   menu.add(UI::TextButton.new(label: 'Play', style: style))
      #
      # Every state is required, so an atlas missing its disabled element is a
      # missing keyword where the style is built rather than a lookup failure the
      # first frame a button is disabled.
      #
      # A style is anything answering `draw(renderer, state, width, height)` in
      # the button's local space, drawing at `z: 0` or below so the button's own
      # content, at `z: 1`, stays on top. This one draws at the nine-slice
      # default of 0.
      #
      # A style may also answer `content_color(state)`: the colour a button's
      # label or icon should take over that state's background, or nil to keep
      # the button's own. Art is the game's, so this one cannot know what reads
      # on it and always answers nil — PanelButton's dark label is chosen for
      # the shipped atlas instead.
      class NineSliceStyle
        # The element name drawn for each state, keyed by `idle`, `focused`,
        # `pressed` and `disabled`.
        attr_reader :elements

        def initialize(idle:, focused:, pressed:, disabled:)
          @elements = { idle: idle, focused: focused, pressed: pressed, disabled: disabled }.freeze
        end

        # A copy with some elements replaced — a game whose atlas differs from
        # the shipped one in a single state names only that state.
        #
        #   UI::PanelButton::STYLE.with(focused: :my_glow)
        def with(**changes) = self.class.new(**@elements, **changes)

        def content_color(_state) = nil

        def draw(renderer, state, width, height)
          renderer.nine_slice(@elements.fetch(state), 0, 0, width, height)
        end
      end
    end
  end
end
