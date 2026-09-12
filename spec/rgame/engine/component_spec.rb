# frozen_string_literal: true

RSpec.describe RGame::Engine::Component do
  describe '#require_sibling' do
    # A component whose on_attach pulls a sibling, which is the shape the helper exists
    # for. Anonymous rather than a real one so the examples pin the helper, not whichever
    # component was borrowed to demonstrate it.
    let(:driver_class) do
      Class.new(described_class) do
        attr_reader :body

        def on_attach = @body = require_sibling(RGame::Engine::Components::CharacterBody)
      end
    end

    let(:node) { RGame::Engine::Node2D.new }
    let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 10.0) }

    it 'returns the sibling when it is there' do
      node.add_component(body)
      driver = node.add_component(driver_class.new)
      node.enter_tree
      expect(driver.body).to be(body)
    end

    # Anonymous again, and for a second reason: the helper must find a subclass of what
    # was asked for, and borrowing a real subclass to show it would tie this example to
    # whichever subclasses happen to exist.
    it 'finds a subclass of the requested component, as get_component does' do
      subclassed = Class.new(RGame::Engine::Components::CharacterBody).new(speed: 10.0)
      node.add_component(subclassed)
      driver = node.add_component(driver_class.new)
      node.enter_tree
      expect(driver.body).to be(subclassed)
    end

    it 'raises naming both components when the sibling is absent' do
      node.add_component(driver_class.new)
      expect { node.enter_tree }.to raise_error(/needs a RGame::Engine::Components::CharacterBody/)
    end

    # The case the message's second half is about, and the reason the helper is not just
    # a nicer nil: a node already in the tree attaches each component as it arrives, so
    # the same two lines in the other order fail — silently, before this raise existed.
    # The raise lands on the add_component that attaches the driver, so it points at the
    # line to move rather than at the frame that later called a method on nil.
    it 'raises when the sibling would be added after it, on a node already in the tree' do
      node.enter_tree
      expect { node.add_component(driver_class.new) }.to raise_error(/add it before this component/)
    end

    # The mirror: assembled outside the tree, the whole set is present before any
    # on_attach runs, so order genuinely does not matter and this must not raise.
    it 'does not care about add order on a node assembled outside the tree' do
      driver = node.add_component(driver_class.new)
      node.add_component(body)
      expect { node.enter_tree }.not_to raise_error
      expect(driver.body).to be(body)
    end
  end
end
