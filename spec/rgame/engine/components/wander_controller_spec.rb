# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::WanderController do
  let(:body) { RGame::Engine::Components::CharacterBody.new(feet_width: 8, feet_height: 8, speed: 60.0) }

  # Build an actor node carrying a CharacterBody + a wander controller with the given
  # options, already in the tree (so on_attach has run).
  def build(**)
    node = RGame::Engine::Node2D.new
    node.add_component(body)
    controller = node.add_component(described_class.new(**))
    node.enter_tree
    [node, controller]
  end

  describe '#update' do
    it 'rolls a direction on the first update' do
      _node, controller = build(rng: Random.new(1), idle_chance: 0.0)
      controller.update(0.016)
      expect([body.move_x, body.move_y]).not_to eq([0.0, 0.0])
    end

    it 'idles when the idle roll wins (idle_chance 1.0)' do
      _node, controller = build(rng: Random.new(1), idle_chance: 1.0)
      controller.update(0.016)
      expect([body.move_x, body.move_y]).to eq([0.0, 0.0])
    end

    it 'is deterministic for a given seed' do
      _na, ca = build(rng: Random.new(42))
      body_b = RGame::Engine::Components::CharacterBody.new(feet_width: 8, feet_height: 8, speed: 60.0)
      nb = RGame::Engine::Node2D.new
      nb.add_component(body_b)
      cb = nb.add_component(described_class.new(rng: Random.new(42)))
      nb.enter_tree

      5.times do
        ca.update(0.5)
        cb.update(0.5)
      end
      expect([body_b.move_x, body_b.move_y]).to eq([body.move_x, body.move_y])
    end

    it 're-rolls early when a wall blocks it, ignoring the timer' do
      # Long interval so the timer alone would never re-roll within these two ticks.
      node, controller = build(rng: Random.new(7), idle_chance: 0.0, change_interval: 100.0..100.0)
      allow(body).to receive(:set_intent).and_call_original

      controller.update(0.016)        # first roll (timer was 0)
      controller.update(0.016)        # node never moved while intending → blocked → re-roll
      expect(body).to have_received(:set_intent).twice

      node # silence unused
    end

    it 'does not re-roll while it is making progress' do
      node, controller = build(rng: Random.new(7), idle_chance: 0.0, change_interval: 100.0..100.0)
      allow(body).to receive(:set_intent).and_call_original

      controller.update(0.016) # first roll, timer set to 100
      node.x += 5.0            # progress: it moved since last tick
      controller.update(0.016) # not blocked, timer still ~100 → no re-roll
      expect(body).to have_received(:set_intent).once
    end
  end
end
