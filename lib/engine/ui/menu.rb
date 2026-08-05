# frozen_string_literal: true

module Engine
  module UI
    # A focus/navigation container for controls, navigable by mouse AND
    # keyboard/controller. It owns an ordered list of items (a control is added by
    # constructing it with the menu as its parent — Node#initialize routes through
    # #add) and drives them each frame: ui_up/ui_down move focus between enabled
    # items (wrapping, skipping disabled); the pointer focuses whatever it hovers.
    #
    # Activation stays the item's own job — a focused Button emits on_clicked. The
    # Menu observes that and re-emits a higher-level on_selected(index, id) to its own
    # observer (the scene), so a scene listens in one place instead of wiring every
    # button. All edges are direct node-to-node signals; there is no global bus.
    class Menu < Engine::Scene
      # The multi-field UI event: which item (ordinal + its action id) was chosen.
      signal :on_selected, Signal.define(:index, :id)

      def initialize(parent)
        super
        @focused = 0
        # Last pointer position, so hover only steals focus when the mouse actually
        # moves — a cursor resting over an item must not fight keyboard navigation.
        @ptr_x = 0.0
        @ptr_y = 0.0
        @seen_pointer = false
      end

      def on_add(node)
        node.on_clicked { select(node) } if node.respond_to?(:on_clicked)
      end

      def update(_dt, actions)
        ensure_focusable
        navigate(actions)
        apply_focus
      end

      # A focused item fired :clicked — report which one to our observers.
      def select(control)
        index = nodes.index { |item| item.equal?(control) }
        return unless index

        id = control.respond_to?(:action) ? control.action : nil
        on_selected_signal.emit(index: index, id: id)
      end

      private

      def navigate(actions)
        move(+1) if actions.pressed?(:ui_down)
        move(-1) if actions.pressed?(:ui_up)
        focus_hovered(actions)
      end

      # Point-to-focus, but only on actual mouse movement (see @seen_pointer): a
      # resting cursor over an item leaves keyboard focus alone.
      def focus_hovered(actions)
        px = actions.pointer_x
        py = actions.pointer_y
        moved = @seen_pointer && (px != @ptr_x || py != @ptr_y)
        @ptr_x = px
        @ptr_y = py
        @seen_pointer = true
        return unless moved

        hovered = nodes.index { |item| item.focusable? && item.contains?(px, py) }
        @focused = hovered if hovered
      end

      # Step to the next/previous focusable item, wrapping; no-op if none qualify.
      def move(step)
        count = nodes.size
        index = @focused
        count.times do
          index = (index + step) % count
          if nodes[index].focusable?
            @focused = index
            break
          end
        end
      end

      def apply_focus
        nodes.each_with_index { |item, i| item.focused = (i == @focused) }
      end

      # Keep focus on a real target even if the current one is disabled/absent.
      def ensure_focusable
        return if nodes.empty? || nodes[@focused]&.focusable?

        first = nodes.index(&:focusable?)
        @focused = first if first
      end
    end
  end
end
