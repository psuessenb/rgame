# frozen_string_literal: true

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
    def draw(renderer); end

    # Container components (e.g. SceneStack) that hold nodes off the normal child
    # list override this to forward the deferred-free sweep into them.
    def sweep_freed; end
  end
end
