# frozen_string_literal: true

module Engine
  module UI
    # A line of text with an anchor and alignment (:left/:center/:right). Measures
    # its width through the renderer and caches it, re-measuring only when the text
    # changes — never building or measuring strings in the per-frame path. Pass `text:`
    # for a literal string or `key:` (+ optional `vars:`) to localize via Engine::I18n.
    class Label < Engine::Node
      include Engine::UI::Localized

      attr_reader :text

      def initialize(parent, x:, y:, text: nil, key: nil, vars: nil, align: :left, color: nil, z: 0)
        super(parent, x: x, y: y, z: z)
        @text = text
        @align = align
        @color = color
        @text_width = nil # measured text width (distinct from Node#width)
        init_localization(key, vars)
      end

      def text=(value)
        @text = value
        @text_width = nil # invalidate the cached measurement
      end

      def draw(renderer)
        refresh_localization { |resolved| self.text = resolved }
        @text_width ||= renderer.text_width(@text)
        x = case @align
            when :center then @abs_x - (@text_width / 2)
            when :right  then @abs_x - @text_width
            else @abs_x
            end
        renderer.text(@text, x, @abs_y, z: @abs_z, color: @color)
      end
    end
  end
end
