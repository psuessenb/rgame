# frozen_string_literal: true

# What a cutscene's blocks are called with: a log of what ran on which tick,
# and the nodes a step puts things on.
class CutsceneStage
  attr_accessor :tick, :dialogue
  attr_reader :marks, :prop, :layer

  def initialize(prop, layer)
    @prop = prop
    @layer = layer
    @tick = 0
    @marks = []
  end

  def mark(name) = @marks << [name, @tick]

  def tween(seconds) = @prop.add_component(RGame::Engine::Components::Tween.new(seconds))

  def say(script)
    @dialogue = RGame::Engine::Dialogue.new(script)
    @layer.add_node(RGame::Engine::UI::DialogueBox.new(dialogue: @dialogue, unavailable: :hide, width: 200))
    @dialogue
  end
end

# A tick is an eighth of a second, and runs as RGame::Game runs one: a poll, a
# control of the whole tree, an update and a sweep.
# rubocop:disable RSpec/MultipleMemoizedHelpers -- two players, the screen, the tree and the stage every group shares
RSpec.describe RGame::Engine::Components::Cutscene do
  let(:controls) { RGame::Util::Controls }
  let(:map) { RGame::Engine::InputMap.default.merge(skip: { buttons: [controls::KEY_TAB], hold: 0.25 }) }
  let(:backend) { FakeInputBackend.new }
  let(:first) { RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD, input_map: map) }
  let(:second) { RGame::Engine::Player.new(id: 1, device: controls.gamepad(0), input_map: map) }
  let(:players) { RGame::Engine::Players.new([first, second]) }
  let(:viewports) { RGame::Engine::Viewports.new(players, width: 320, height: 240) }
  let(:root) do
    RGame::Engine::Node2D.new.tap do |root|
      root.add_component(players)
      root.add_component(viewports)
    end
  end
  let(:scene) { root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it } }
  let(:prop) { scene.add_node(RGame::Engine::Node2D.new) }
  let(:layer) { scene.add_node(RGame::Engine::Node2D.new) }
  let(:hero) { scene.add_node(RGame::Engine::Node2D.new) }
  let(:stage) { CutsceneStage.new(prop, layer) }
  let(:camera) { RGame::Engine::Camera.new }
  let(:mayor) do
    RGame::Engine::Dialogue::Script.build(start: :hello, scope: 'mayor') do
      beat :hello, speaker: :mayor, line: 'hello', to: :bye
      beat :bye, speaker: :mayor, line: 'bye'
    end
  end

  def dt = 0.125

  before do
    RGame::Engine::I18n.load_hash(en: { speakers: { mayor: 'Mayor' }, mayor: { hello: 'Hello.', bye: 'Bye.' } })
  end

  def tick
    stage.tick += 1
    players.poll(backend, dt)
    root.control(players)
    root.update(dt)
    root.sweep_freed
  end

  def script(&) = RGame::Engine::Cutscene::Script.build(&)

  def play(script, on: scene, **)
    root.enter_tree
    on.add_component(described_class.new(script, context: stage, **))
  end

  def ended
    heard = []
    yield.on_ended { heard << it }
    heard
  end

  # Rules 1 and 2.
  describe 'its steps' do
    it 'run in order, each from the tick the one before it ended' do
      play(script do
        run { |c| c.mark(:start) }
        wait 0.25
        run { |c| c.mark(:waited) }
        hold { |c| c.tween(0.25) }
        run { |c| c.mark(:held) }
      end)
      6.times { tick }
      expect(stage.marks).to eq([[:start, 0], [:waited, 2], [:held, 4]])
    end

    it 'start as the component attaches, and run on its node\'s update' do
      cutscene = play(script do
        run { |c| c.mark(:start) }
        wait 0.125
        run { |c| c.mark(:done) }
      end)
      scene.suspend
      3.times { tick }
      scene.resume
      tick
      expect([stage.marks, cutscene.ended?]).to eq([[[:start, 0], [:done, 4]], true])
    end

    it 'wait for the action a press names' do
      play(script do
        press :skip
        run { |c| c.mark(:pressed) }
      end)
      tick
      backend.hold(controls::KEY_RETURN)
      2.times { tick }
      backend.hold(controls::KEY_TAB)
      3.times { tick }
      expect(stage.marks).to eq([[:pressed, 5]])
    end

    it 'read every player on a node Players#everyone owns' do
      scene.input_owner = players.everyone
      cutscene = play(script { press })
      tick
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      tick
      expect(cutscene).to be_ended
    end

    it 'wait for the player\'s confirm on a press' do
      cutscene = play(script do
        press
        run { |c| c.mark(:confirmed) }
      end)
      tick
      backend.hold(controls::KEY_RETURN)
      tick
      expect([stage.marks, cutscene.ended?]).to eq([[[:confirmed, 2]], true])
    end
  end

  # Rules 3, 4 and 5, without rooms.
  describe 'what it takes' do
    it 'with a camera, solos the window onto it and stops joins, and gives both back' do
      players.accepting_joins = true
      play(script { wait 0.25 }, camera:)
      tick
      during = [viewports.solo_camera, players.accepting_joins]
      2.times { tick }
      tick
      expect([during, viewports.solo?, players.accepting_joins]).to eq([[camera, false], false, true])
    end

    it 'without a camera, solos nothing and leaves joins alone' do
      play(script { wait 0.25 })
      tick
      expect([viewports.solo?, players.accepting_joins]).to eq([false, true])
    end

    it 'puts back a solo that was there before it' do
      earlier = RGame::Engine::Camera.new
      viewports.solo!(earlier)
      root.enter_tree
      tick
      play(script { wait 0.125 }, camera:)
      3.times { tick }
      expect(viewports.solo_camera).to equal(earlier)
    end

    it 'suspends each node in pause: and resumes it, leaving its paused alone' do
      hero.paused = true
      play(script { wait 0.25 }, pause: [hero])
      during = hero.suspended?
      3.times { tick }
      expect([during, hero.suspended?, hero.paused]).to eq([true, false, true])
    end

    it 'gives everything back when it leaves the tree, and fires nothing' do
      cutscene = play(script { wait 1 }, on: prop, camera:, pause: [hero])
      heard = ended { cutscene }
      tick
      prop.queue_free
      2.times { tick }
      expect([hero.suspended?, viewports.solo?, players.accepting_joins, heard]).to eq([false, false, true, []])
    end

    it 'refuses to pause the node it rides, or one above it' do
      expect { play(script { wait 1 }, on: prop, pause: [scene]) }.to raise_error(ArgumentError, /never run/)
    end
  end

  # Rules 6 and 7.
  describe 'skipping' do
    def skippable(**)
      play(script do
        run { |c| c.mark(:start) }
        hold { |c| c.tween(10) }
        wait 5
        run { |c| c.mark(:after) }
        press
        run { |c| c.mark(:end) }
      end, skip: :skip, **)
    end

    def hold_skip(ticks)
      backend.hold(controls::KEY_TAB)
      ticks.times { tick }
      backend.release(controls::KEY_TAB)
    end

    it 'finishes the step under way, runs each remaining step\'s skip, and ends' do
      cutscene = skippable
      heard = ended { cutscene }
      tick
      hold_skip(4)
      tween = prop.get_component(RGame::Engine::Components::Tween)
      expect([stage.marks.map(&:first), tween.done?, heard]).to eq([%i[start after end], true, [true]])
    end

    it 'needs the skip held for its hold:' do
      cutscene = skippable
      tick
      hold_skip(1)
      tick
      expect(cutscene).to be_running
    end

    it 'refuses a skip begun before the cutscene started' do
      root.enter_tree
      backend.hold(controls::KEY_TAB)
      tick
      cutscene = skippable
      4.times { tick }
      expect(cutscene).to be_running
    end

    it 'refuses a confirm begun before the cutscene started' do
      backend.hold(controls::KEY_RETURN)
      root.enter_tree
      tick
      cutscene = play(script { press })
      3.times { tick }
      expect(cutscene).to be_running
    end

    it 'reads its node\'s player' do
      cutscene = skippable(on: prop)
      prop.input_owner = second
      tick
      hold_skip(4)
      expect(cutscene).to be_running
    end

    it 'is not possible without skip:' do
      cutscene = play(script { wait 1 })
      tick
      hold_skip(4)
      expect(cutscene).to be_running
    end

    it 'can be asked for by a call' do
      cutscene = play(script { wait 1 })
      heard = ended { cutscene }
      cutscene.skip.skip
      expect([cutscene.ended?, heard]).to eq([true, [true]])
    end
  end

  # Rule 8.
  describe 'skipping a talk' do
    it 'ends the conversation where it stands, and the box frees itself' do
      said = mayor
      cutscene = play(script do
        talk { |c| c.say(said) }
        run { |c| c.mark(:after) }
      end)
      tick
      box = layer.children.first
      cutscene.skip
      tick
      expect([stage.dialogue.ended?, stage.dialogue.transcript.size, box.parent,
              stage.marks.map(&:first)]).to eq([true, 1, nil, [:after]])
    end

    it 'puts up a remaining talk and ends it at once' do
      said = mayor
      cutscene = play(script do
        wait 1
        talk { |c| c.say(said) }
      end)
      cutscene.skip
      tick
      expect([stage.dialogue.ended?, layer.children]).to eq([true, []])
    end
  end

  # Rule 9.
  describe 'a hold' do
    it 'refuses a block returning what has no on_finished and finish, naming both' do
      expect { play(script { hold { :nothing } }) }.to raise_error(TypeError, /on_finished and finish/)
    end

    it 'refuses a talk returning what is not a dialogue' do
      expect { play(script { talk { :nothing } }) }.to raise_error(TypeError, /on_ended and finish/)
    end

    it 'hears what finishes in its first update, and moves on in its own next one' do
      play(script do
        hold { |c| c.tween(0.125) }
        run { |c| c.mark(:held) }
      end)
      2.times { tick }
      expect(stage.marks).to eq([[:held, 2]])
    end

    it 'moves on the same tick for what updates before the cutscene\'s node' do
      stage
      play(script do
        hold { |c| c.tween(0.125) }
        run { |c| c.mark(:held) }
      end, on: hero)
      2.times { tick }
      expect(stage.marks).to eq([[:held, 1]])
    end

    it 'stops listening once the step ends' do
      cutscene = play(script do
        hold { |c| c.tween(0.125) }
        press
      end)
      tick
      tween = prop.get_component(RGame::Engine::Components::Tween)
      tween.start
      2.times { tick }
      expect([cutscene.step_index, tween.done?]).to eq([1, true])
    end
  end

  # The caller that uses both: two players in two rooms of one world.
  describe 'in a room of a Scene::Rooms' do
    let(:rooms) { scene.add_component(RGame::Engine::Scene::Rooms.new) }
    let(:other_hero) { RGame::Engine::Node2D.new(input_owner: second) }
    let(:hero) { RGame::Engine::Node2D.new(input_owner: first) }

    before do
      rooms.define(:town) { SpecRoom.new }
      rooms.define(:garden) { SpecRoom.new }
      root.enter_tree
      rooms.move(hero, to: :town, entrance: 'gate')
      rooms.move(other_hero, to: :garden, entrance: 'well')
      tick
    end

    def clips
      renderer = FakeRenderer.new
      root.draw(renderer, viewports.screen)
      renderer.calls_to(:clipped).map(&:args)
    end

    it 'solos onto its room and stops the others, then gives all of it back as a door in its last step lands' do
      town = rooms[:town]
      moved = rooms
      rooms[:garden].add_component(described_class.new(script do
        wait 0.25
        run { moved.move(it.first, to: :town, entrance: 'gate') }
      end, context: [other_hero], camera:, pause: [other_hero]))
      tick
      during = [viewports.solo_room.name, town.suspended?, players.accepting_joins, clips]
      2.times { tick }
      expect([during, rooms[:garden], rooms.room_of(second).name, town.suspended?, other_hero.suspended?,
              viewports.solo?, players.accepting_joins, clips.size])
        .to eq([[:garden, true, false, [[0, 0, 320, 240]]], nil, :town, false, false, false, true, 2])
    end

    it 'gives all of it back when a door in a middle step frees its room' do
      moved = rooms
      cutscene = described_class.new(script do
        run { moved.move(it.first, to: :town, entrance: 'gate') }
        wait 1
      end, context: [other_hero], camera:, pause: [other_hero])
      rooms[:garden].add_component(cutscene)
      heard = ended { cutscene }
      2.times { tick }
      expect([rooms[:garden], rooms[:town].suspended?, other_hero.suspended?, viewports.solo?,
              players.accepting_joins, heard]).to eq([nil, false, false, false, true, []])
    end

    it 'leaves the hero running once both a move and a cutscene that stop it have ended' do
      rooms.transition = RGame::Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)
      rooms.move(hero, to: :garden, entrance: 'well')
      3.times { tick }
      rooms[:garden].add_component(described_class.new(script { wait 0.5 }, pause: [hero]))
      during = hero.suspended?
      6.times { tick }
      expect([during, hero.suspended?]).to eq([true, false])
    end
  end

  # Rule 10.
  it 'fires ended once, with false, after everything is given back' do
    seen = []
    cutscene = play(script { wait 0.125 }, camera:, pause: [hero])
    cutscene.on_ended { |skipped| seen << [skipped, hero.suspended?, players.accepting_joins] }
    3.times { tick }
    expect(seen).to eq([[false, false, true]])
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
