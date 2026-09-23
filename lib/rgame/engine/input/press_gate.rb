# frozen_string_literal: true

module RGame
  module Engine
    # What a node reads its input through: an Actions snapshot whose edges
    # belong only to presses the node saw start.
    #
    # Node2D#control keeps one per node, made on the node's first control with
    # a polled snapshot, and hands it to the node's components and `_control`
    # in place of the snapshot. A snapshot built by hand has no `poll_count`,
    # and a node hands that one on as it is.
    #
    # A node *resumes* on the first poll it is controlled after one it was
    # not. That is its first control, and its first after a pause, after a
    # scene above it was popped, or after its page was hidden. It also resumes
    # when the snapshot it reads is another one, as when its `input_owner`
    # changes.
    #
    # `pressed?` and `released?` answer false for a press that began on or
    # before the poll the node resumed on. So the press that resumed a node is
    # not its press either, as UI::Menu refuses a confirm already down when it
    # opens. Every other query passes through: a direction held across a pause
    # still walks the hero once it ends.
    #
    # @api private
    class PressGate
      def initialize
        @actions = nil
        @last = nil
        @resumed = nil
      end

      # Points the gate at `actions`, the snapshot of poll `poll`, and answers
      # the gate. Unless the gate last read the poll before from the same
      # snapshot, the node resumes on this one.
      # hot-path
      def read(actions, poll)
        @resumed = poll unless actions.equal?(@actions) && poll == @last + 1
        @actions = actions
        @last = poll
        self
      end

      # hot-path
      def pressed?(name) = @actions.pressed?(name) && saw_start?(name)

      # hot-path
      def released?(name) = @actions.released?(name) && saw_start?(name)

      # hot-path
      def held?(name) = @actions.held?(name)

      # hot-path
      def axis(name) = @actions.axis(name)

      # hot-path
      def held_for(name) = @actions.held_for(name)

      # hot-path
      def down_since(name) = @actions.down_since(name)

      # hot-path
      def poll_count = @actions.poll_count

      def declared = @actions.declared

      # The snapshot itself, for a component that hands input on to a subtree,
      # as Scene::SceneStack does. Every node in that subtree keeps a gate of
      # its own.
      # hot-path
      def actions_for(_player) = @actions

      private

      # hot-path
      def saw_start?(name)
        since = @actions.down_since(name)
        since.nil? || since > @resumed
      end
    end
  end
end
