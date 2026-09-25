# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # One player's menus that make up one screen, and the one of them that
      # reads input.
      #
      #   group = layer.add_node(UI::FocusGroup.new)
      #   bag   = group.add_node(UI::PanelMenu.new(x: 16, y: 48, layout: grid))
      #   verbs = group.add_node(UI::PanelMenu.new(x: 340, y: 48, layout: column))
      #
      # ## One menu reads
      #
      # Two open menus under one player would each move focus and each confirm on
      # every press. A group names one `current` menu, and only that menu reads
      # input: navigation, hotkeys and confirm. The others draw with nothing
      # focused. `current` starts on the first menu to join that is open and
      # has an enabled button, and is nil while none has.
      #
      # ## A menu joins as it enters the tree
      #
      # A menu joins the nearest group above it as it enters the tree, and leaves
      # as it exits, so nothing registers by hand. A menu wrapped in a panel node
      # belongs to the group round the panel. UI::Menu joins in `enter_tree`
      # itself, so a subclass that overrides `_enter_tree` stays in its group.
      #
      # Three menus refuse a group, and raise ArgumentError as they join. A menu
      # with a `trigger:` opens only while its trigger is held, so no group could
      # make it current. A UI::DialogueBox's menu advances its conversation,
      # which a group would stop whenever another menu is current. And a menu
      # answering to another player than the group would never read its own
      # player's input.
      #
      # ## Crossing to a neighbour
      #
      # UI::Stepping asks the group with `cross` before it wraps past the end of
      # a line, and on a direction the focused button cannot `adjust`. The group
      # makes the neighbour that way current and answers true, or answers false
      # when there is none, and the step wraps. So a bag and a column of verbs
      # become one screen, and neither menu knows the other exists.
      #
      # The neighbour is the nearest menu wholly beyond the current one's edge in
      # that direction, measured on the two menus' bounds. The gap between them
      # decides, and the distance between their centres across the gap breaks a
      # tie. A closed menu and a menu with no enabled button are never
      # neighbours.
      #
      # ## A change of current
      #
      # Every change of `current` follows one rule, whether a crossing,
      # `current=`, a hand-over or the first menu to join made it. The menu left
      # clears its focus and reads nothing more that tick. The menu entered reads
      # no input until the next tick, so one press crosses once whichever menu
      # the tree controls first. It takes no confirm until it has seen confirm
      # up, and its navigation decides where focus starts.
      #
      # Each tick, before any of its menus reads, the group checks `current`. A
      # menu that is closed, has no enabled button or has left the tree hands
      # over to the first menu that has joined and qualifies.
      class FocusGroup < Node2D
        DIRECTIONS = %i[left right up down].freeze

        # `menus` holds every menu in the group, in the order they joined.
        # `current` is the one that reads input, or nil.
        sealed_reader :menus, :current

        def initialize(**)
          super
          @rgame_menus = []
          @rgame_current = nil
          @rgame_passes = 0
          @rgame_entered_on = 0
        end

        # Makes `menu` current, from the next tick. Raises ArgumentError for a
        # menu that is not in the group.
        def current=(menu)
          raise ArgumentError, "#{menu.inspect} is not a menu in this FocusGroup" unless @rgame_menus.include?(menu)

          change_current(menu)
        end

        # Makes the neighbour in `direction` current and answers true, or answers
        # false and changes nothing when no menu lies that way. `direction` is
        # one of DIRECTIONS; anything else raises ArgumentError.
        #
        # rubocop:disable Naming/PredicateMethod -- a command that reports whether it could be
        # carried out, not a question; `cross?` would read as "may focus cross?".
        def cross(direction)
          unless DIRECTIONS.include?(direction)
            raise ArgumentError, "direction must be one of #{DIRECTIONS.inspect}, not #{direction.inspect}"
          end

          neighbour = @rgame_current && neighbour_of(@rgame_current, direction)
          return false if neighbour.nil?

          change_current(neighbour)
          true
        end
        # rubocop:enable Naming/PredicateMethod

        # Checks `current` before any menu under the group reads, then does what
        # every node does.
        def control(input)
          unless rgame_stopped?
            @rgame_passes += 1
            hand_over unless @rgame_current && qualifies?(@rgame_current)
          end
          super
        end

        # Called by a UI::Menu as it enters the tree under this group. Raises
        # ArgumentError for the three menus a group refuses.
        #
        # @api private
        def join(menu)
          refuse(menu)
          @rgame_menus << menu
          if @rgame_current.nil? && qualifies?(menu)
            change_current(menu)
          else
            menu.focus(nil)
          end
        end

        # Called by a UI::Menu as it exits the tree.
        #
        # @api private
        def leave(menu)
          @rgame_menus.delete(menu)
          change_current(nil) if menu.equal?(@rgame_current)
        end

        # Whether `menu` reads input on this tick: it is current, and was
        # already current when the tick began.
        #
        # @api private
        def reading?(menu) = menu.equal?(@rgame_current) && @rgame_entered_on < @rgame_passes

        private

        def change_current(menu)
          return if menu.equal?(@rgame_current)

          left = @rgame_current
          from = left&.focused
          @rgame_current = menu
          @rgame_entered_on = @rgame_passes
          left&.focus(nil)
          menu&.enter_from(from)
        end

        def hand_over
          index = 0
          while index < @rgame_menus.size
            menu = @rgame_menus[index]
            return change_current(menu) if qualifies?(menu)

            index += 1
          end
          change_current(nil)
        end

        def qualifies?(menu)
          return false unless menu.open?

          buttons = menu.buttons
          index = 0
          while index < buttons.size
            return true if buttons[index].enabled?

            index += 1
          end
          false
        end

        def neighbour_of(from, direction)
          best = nil
          best_gap = best_offset = Float::INFINITY
          index = 0
          while index < @rgame_menus.size
            menu = @rgame_menus[index]
            index += 1
            next if menu.equal?(from) || !qualifies?(menu)

            gap = gap_between(from, menu, direction)
            next if gap.negative?

            offset = offset_across(from, menu, direction)
            next unless gap < best_gap || (gap == best_gap && offset < best_offset)

            best = menu
            best_gap = gap
            best_offset = offset
          end
          best
        end

        def gap_between(from, to, direction)
          case direction
          when :right then left_edge(to) - right_edge(from)
          when :left then left_edge(from) - right_edge(to)
          when :down then top_edge(to) - bottom_edge(from)
          else top_edge(from) - bottom_edge(to)
          end
        end

        def offset_across(from, to, direction)
          case direction
          when :up, :down then (middle_x(to) - middle_x(from)).abs
          else (middle_y(to) - middle_y(from)).abs
          end
        end

        def left_edge(menu) = menu.world_x + menu.bounds_x
        def right_edge(menu) = left_edge(menu) + menu.bounds_width
        def top_edge(menu) = menu.world_y + menu.bounds_y
        def bottom_edge(menu) = top_edge(menu) + menu.bounds_height
        def middle_x(menu) = left_edge(menu) + (menu.bounds_width / 2.0)
        def middle_y(menu) = top_edge(menu) + (menu.bounds_height / 2.0)

        def refuse(menu)
          if menu.trigger
            raise ArgumentError, "a menu with trigger: #{menu.trigger.inspect} opens only while it is held, " \
                                 'so a FocusGroup could never make it current'
          end
          if menu.parent.is_a?(DialogueBox)
            raise ArgumentError, 'a DialogueBox\'s menu advances its conversation, and a FocusGroup would ' \
                                 'stop it whenever another menu is current'
          end
          return if owner_of(menu).equal?(owner_of(self))

          raise ArgumentError, 'this menu answers to another player than its FocusGroup, so it would never read ' \
                               'its own player\'s input; give each player a group of their own'
        end

        def owner_of(node)
          node = node.parent while node && node.input_owner.nil?
          node&.input_owner
        end
      end
    end
  end
end
