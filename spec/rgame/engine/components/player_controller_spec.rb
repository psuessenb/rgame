# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::PlayerController do
  let(:node) { RGame::Engine::Node2D.new }
  let(:body) { RGame::Engine::Components::CharacterBody.new(feet_width: 8, feet_height: 8, speed: 100.0) }

  before do
    node.add_component(body)
    node.add_component(described_class.new)
    node.enter_tree # on_attach pulls the CharacterBody sibling
  end

  # Both axes are declared every time, because that is the set this component
  # reads and Actions answers only for what it was given.
  def actions(**axes)
    RGame::Engine::Actions.new(axes: { move_x: 0.0, move_y: 0.0 }.merge(axes))
  end

  describe '#control' do
    it 'copies the two axes into the body as its movement intent' do
      node.control(actions(move_x: 1.0, move_y: -1.0))
      expect([body.move_x, body.move_y]).to eq([1.0, -1.0])
    end

    it 'is neutral when the axes are at rest' do
      node.control(actions(move_x: 1.0))
      node.control(actions) # released
      expect([body.move_x, body.move_y]).to eq([0.0, 0.0])
    end
  end
end
