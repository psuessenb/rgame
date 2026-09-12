# frozen_string_literal: true

# What `RGame::Engine` does not contain, stated as an example rather than left
# to the absence of a file.
#
# Three classes were removed from the engine layer because each was superseded
# by the Node/Component architecture and had no caller: `Body` (a transform plus
# kinematics, now a node's own position and the `Velocity`, `ScreenWrap` and
# `DespawnOffscreen` components), `Matrix` (a flat grid, now `Util::Tensor`) and
# `Resettable` (pooled value objects, where the engine pools nodes that `reset`
# themselves). Deleting a file proves nothing about whether a copy of the
# constant survives somewhere else under `lib/`, and `spec_helper` has already
# required the whole layer by the time this runs.
RSpec.describe RGame::Engine do
  %i[Body Matrix Resettable].each do |name|
    it "does not define #{name}" do
      expect(described_class.const_defined?(name, false)).to be(false)
    end
  end
end
