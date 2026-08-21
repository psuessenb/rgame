# frozen_string_literal: true

module RGame
  module Engine
    class Component
      extend Signal::DSL

      attr_accessor :node

      def context
        @context ||= node.context
      end

      # Tree-lifecycle hooks. on_attach fires once the node is in the live tree, so
      # node.root / node.scene and sibling systems are reachable — pull and register
      # shared systems here, not in initialize (where the node has no anchors yet).
      # on_detach mirrors it: release those registrations.
      def on_attach; end
      def on_detach; end

      def control(actions); end
      def update(dt); end
      def draw(renderer, view); end

      # Container components (e.g. SceneStack) that hold nodes off the normal child
      # list override this to forward the deferred-free sweep into them.
      def sweep_freed; end

      # `control` above receives **one player's** Actions — the actions of
      # whoever owns this component's node — which is what a component wants,
      # since it belongs to exactly one node.
      #
      # A container component holding a whole subtree needs the input *source*
      # instead, so the nodes inside it can each resolve their own owner. There
      # is no hook for that on purpose: it is a system lookup like any other, so
      # such a component pulls `node.system(Players)` in `on_attach` and passes
      # that down. SceneStack is the worked example.
    end
  end
end
