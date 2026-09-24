# frozen_string_literal: true

module RGame
  module Engine
    class Players < Component
      # An input owner that stands for every active player at once.
      #
      #   box.input_owner = node.system(Players).everyone
      #
      # A game sets it on a node that no one player owns: a dialogue box, a
      # title screen or a pause menu shown during `solo!`. The node then reads
      # one controller whose buttons are the OR of every active player's.
      #
      # - `held?` is true while any active player holds the action.
      # - `pressed?` and `released?` are the edges of that union. A press while
      #   another player already holds the action is no press, so one press
      #   still does one thing.
      # - `axis` is the value of largest magnitude.
      # - `held_for` is the longest any active player has held it.
      # - `down_since` is the poll on which the first of the presses under way
      #   began, counted in this owner's own `poll_count`.
      #
      # An action no active player declares raises `KeyError`, as `Actions`
      # does. With no active player at all, it reads the primary player.
      #
      # `Players#poll` builds it once a tick, into hashes it reuses, so reading
      # it allocates nothing. It has no region of the screen, so a
      # `PlayerLayer` refuses it; a node it owns goes in the `:overlay` band.
      class Everyone
        def initialize(players)
          @players = players
          @members = []
          @held = {}
          @prev_held = {}
          @axes = {}
          @hold_times = {}
          @since = {}
          @down = {}
          @actions = Actions.new(held: @held, axes: @axes, prev_held: @prev_held, hold_times: @hold_times,
                                 down_since: @since, poll_count: 0)
        end

        # The union of every active player's input this tick, or the primary
        # player's while nobody is active. The same object every tick, so a
        # node may hold it, as it may `Player#actions`.
        attr_reader :actions

        # @api private
        # hot-path
        def poll
          enlist unless members_current?
          @actions.count_poll
          @held.each { |name, down| @prev_held[name] = down }
          @held.each_key { |name| @held[name] = false }
          @axes.each_key { |name| @axes[name] = 0.0 }
          @hold_times.each_key { |name| @hold_times[name] = 0.0 }
          @down.each_key { |name| @down[name] = false }
          @members.each { |player| fold(player) }
          note_starts
          self
        end

        private

        # hot-path
        def members_current?
          nobody = @players.list.none?(&:active?)
          @players.list.all? { |player| member?(player, nobody) == @members.include?(player) } &&
            @members.all? { |player| @players.list.include?(player) }
        end

        # hot-path
        def member?(player, nobody) = player.active? || (nobody && player.equal?(@players.primary))

        def enlist
          nobody = @players.list.none?(&:active?)
          @members.replace(@players.list.select { member?(it, nobody) })
          declared = @members.flat_map { |player| player.input_map.bindings.keys }.uniq
          (@held.keys - declared).each { |name| forget(name) }
          declared.each do |name|
            @held[name] = false unless @held.key?(name)
            @prev_held[name] = false unless @prev_held.key?(name)
            @axes[name] = 0.0 unless @axes.key?(name)
            @hold_times[name] = 0.0 unless @hold_times.key?(name)
            @since[name] = nil unless @since.key?(name)
            @down[name] = false unless @down.key?(name)
          end
        end

        def forget(name)
          @held.delete(name)
          @prev_held.delete(name)
          @axes.delete(name)
          @hold_times.delete(name)
          @since.delete(name)
          @down.delete(name)
        end

        # hot-path
        def fold(player)
          actions = player.actions
          player.input_map.bindings.each_key do |name|
            @held[name] = true if actions.held?(name)
            value = actions.axis(name)
            @axes[name] = value if value.abs > @axes[name].abs
            time = actions.held_for(name)
            @hold_times[name] = time if time > @hold_times[name]
            @down[name] = true if actions.down_since(name)
          end
        end

        # hot-path
        def note_starts
          @down.each do |name, down|
            @since[name] = down ? @since[name] || @actions.poll_count : nil
          end
        end
      end
    end
  end
end
