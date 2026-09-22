# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::DialogueBox do
  let(:root) { engine::Node2D.new }
  let(:renderer) { FakeRenderer.new }

  let(:hero) do
    Struct.new(:gold, :asked) do
      def can_bribe?
        self.asked += 1
        gold >= 50
      end

      def pay_bribe = self.gold -= 50
    end.new(10, 0)
  end
  let(:snapshot) do
    reads = %i[ui_up ui_down ui_left ui_right ui_confirm]
    held = reads.to_h { |name| [name, false] }
    previous = reads.to_h { |name| [name, false] }
    actions = engine::Actions.new(held: held, axes: {}, prev_held: previous)

    lambda do |*down|
      held.each { |name, state| previous[name] = state }
      reads.each { |name| held[name] = down.include?(name) }
      actions
    end
  end

  def engine = RGame::Engine

  def smith
    engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
      beat :greeting, speaker: :smith, line: 'greeting' do
        respond 'ask_work', to: :work
        respond 'bribe', to: :bribed, if: :can_bribe?, then: :pay_bribe
        respond 'again', to: :greeting
        respond 'bye'
      end
      beat :work, speaker: :smith, line: 'work', to: :greeting
      beat :bribed, speaker: :smith, line: 'bribed', to: :greeting
    end
  end

  before do
    engine::I18n.load_hash(
      en: {
        speakers: { smith: 'Smith' },
        smith: {
          greeting: 'Well met.',
          work: 'The forge wants coal, the bellows want mending, and the order book wants a clerk who can ' \
                'read. I can do the first two. The third waits for you.',
          bribed: 'Fifty it is.',
          ask_work: 'Any work?', bribe: 'Fifty gold?', again: 'Pardon?', bye: 'Farewell.'
        }
      },
      de: {
        speakers: { smith: 'Schmied' },
        smith: { greeting: 'Sei gegrüßt.' }
      }
    )
  end

  def talk(**) = engine::Dialogue.new(smith, context: hero, **)

  def box(dialogue: talk, unavailable: :disable, parent: root, **)
    parent.add_node(described_class.new(dialogue:, unavailable:, width: 400, reveal: nil, **)).tap do
      root.enter_tree
    end
  end

  def menu(of) = of.children.find { it.is_a?(engine::UI::Menu) }
  def line(of) = of.children.find { it.is_a?(engine::UI::Label) }
  def labels(of) = menu(of).buttons.map { it.label&.key }

  def tick(*down)
    root.control(snapshot.call(*down))
    root.update(1.0 / 60)
    root.sweep_freed
  end

  def confirm
    tick(:ui_confirm)
    tick
  end

  # The responses appear on an update, and the menu takes no confirm until it
  # has seen confirm up since, so a player's pick is one tick later at least.
  def choose(of, key)
    tick until menu(of).buttons.any?(&:label)
    tick
    menu(of).focus(labels(of).index(key))
    confirm
  end

  def texts
    renderer.clear
    root.draw(renderer, screen_view)
    renderer.calls_to(:text).map { it.args.first }
  end

  describe 'the invariant' do
    it 'records the same transcript as the dialogue driven directly, with the same picks' do
      direct = talk
      direct.respond(direct.responses[0])
      direct.continue
      direct.respond(direct.responses[2])
      direct.respond(direct.responses[3])

      boxed = talk
      shown = box(dialogue: boxed, lines_per_page: 1)
      tick
      choose(shown, 'ask_work')
      confirm until boxed.beat == :greeting
      choose(shown, 'again')
      choose(shown, 'bye')
      expect([boxed.ended?, boxed.transcript.to_h]).to eq([true, direct.transcript.to_h])
    end
  end

  describe 'building one' do
    it 'requires unavailable:' do
      expect { described_class.new(dialogue: talk, width: 400) }.to raise_error(ArgumentError, /unavailable/)
    end

    it 'refuses any unavailable: but :hide and :disable' do
      expect { described_class.new(dialogue: talk, unavailable: :show, width: 400) }
        .to raise_error(ArgumentError, /unavailable: must be one of \[:hide, :disable\], not :show/)
    end

    it 'refuses a dialogue that has ended' do
      ended = talk
      ended.respond(ended.responses.last)
      expect { described_class.new(dialogue: ended, unavailable: :hide, width: 400) }
        .to raise_error(ArgumentError, /has ended/)
    end

    it 'keeps one height for the whole conversation, from the most responses any beat has' do
      shown = box(dialogue: talk, lines_per_page: 1)
      heights = [shown.height]
      tick
      choose(shown, 'ask_work')
      heights << shown.height
      column = menu(shown).layout
      expect([heights.uniq.size, menu(shown).y + (4 * column.item_height) + (3 * column.spacing) + 12])
        .to eq([1, shown.height])
    end
  end

  describe 'confirm' do
    it 'shows the rest of a page still typing, then turns the page, then continues' do
      dialogue = talk
      shown = box(dialogue:, lines_per_page: 1, reveal: 10)
      tick
      choose(shown, 'ask_work')
      label = line(shown)
      tick
      typing = label.revealed?
      confirm
      steps = [[typing, label.revealed?, label.page]]
      confirm
      steps << [label.page]
      confirm until label.last_page? && label.revealed?
      confirm
      steps << [dialogue.beat]
      expect(steps).to eq([[false, true, 0], [1], [:greeting]])
    end

    it 'shows the responses once the last page is revealed, by the reveal' do
      shown = box(reveal: 40)
      tick until line(shown).revealed?
      tick
      expect(labels(shown)).to eq(%w[ask_work bribe again bye])
    end

    it 'shows the responses when confirm finishes the line, and picks none with that confirm' do
      dialogue = talk
      shown = box(dialogue:, reveal: 10)
      tick
      confirm
      expect([labels(shown), dialogue.beat, dialogue.transcript.size])
        .to eq([%w[ask_work bribe again bye], :greeting, 1])
    end

    it 'picks the focused response with the next confirm' do
      dialogue = talk
      shown = box(dialogue:)
      tick
      tick
      confirm
      expect([dialogue.beat, line(shown).page]).to eq([:work, 0])
    end

    it 'does nothing for a box added while confirm is held, until confirm is let go and pressed again' do
      dialogue = talk
      tick(:ui_confirm)
      shown = box(dialogue:, reveal: 10)
      3.times { tick(:ui_confirm) }
      held = [line(shown).revealed?, labels(shown)]
      tick
      confirm
      expect([held, line(shown).revealed?]).to eq([[false, [nil]], true])
    end
  end

  describe 'responses the player cannot pick' do
    it 'lists only the available ones under :hide' do
      shown = box(unavailable: :hide)
      tick
      expect(labels(shown)).to eq(%w[ask_work again bye])
    end

    it 'lists them all under :disable, the unavailable one disabled' do
      shown = box(unavailable: :disable)
      tick
      expect(menu(shown).buttons.map(&:enabled?)).to eq([true, false, true, true])
    end

    it 'steps past the disabled one' do
      shown = box(unavailable: :disable)
      tick
      tick(:ui_down)
      expect(menu(shown).focused.label.key).to eq('again')
    end

    it 'asks the condition once per beat, however many ticks pass' do
      box
      100.times { tick }
      expect(hero.asked).to eq(1)
    end

    it 'shows the bribe once the hero can pay' do
      hero.gold = 80
      shown = box(unavailable: :hide)
      tick
      expect(labels(shown)).to eq(%w[ask_work bribe again bye])
    end
  end

  describe 'after each move' do
    it 'draws the new line and the speaker\'s name' do
      shown = box
      tick
      choose(shown, 'ask_work')
      first_line = RGame::Util::Typeface.default.text_lines(engine::I18n.t('smith.work'), 400 - 12 - 12).first
      expect(texts.first(2)).to eq(['Smith', first_line])
    end

    it 'types a beat entered twice in a row out again' do
      dialogue = talk
      shown = box(dialogue:, reveal: 10)
      tick
      confirm
      choose(shown, 'again')
      tick
      expect([dialogue.visits(:greeting), line(shown).revealed?, labels(shown)]).to eq([2, false, [nil]])
    end

    it 'draws the speaker\'s name in the language chosen since' do
      box
      engine::I18n.locale = :de
      expect(texts.first(2)).to eq(['Schmied', 'Sei gegrüßt.'])
    end
  end

  describe 'the end of the conversation' do
    it 'frees the box, and the game hears on_ended with the transcript' do
      dialogue = talk
      heard = []
      dialogue.on_ended { heard << it }
      shown = box(dialogue:)
      tick
      choose(shown, 'bye')
      expect([shown.parent, heard.map(&:size), heard.first&.frozen?]).to eq([nil, [2], true])
    end
  end

  describe 'drawing' do
    it 'draws the panel as a button style draws, idle, over the whole box' do
      panel = Class.new do
        attr_reader :calls

        def initialize = @calls = []
        def draw(_renderer, state, width, height) = @calls << [state, width, height]
      end.new
      shown = box(panel:)
      texts
      expect(panel.calls).to eq([[:idle, 400, shown.height]])
    end

    it 'draws the marker as a triangle once the page is shown, and not while it types' do
      shown = box(reveal: 10)
      tick
      texts
      typing = renderer.drawn?(:triangle)
      line(shown).reveal_all
      texts
      expect([typing, renderer.drawn?(:triangle)]).to eq([false, true])
    end

    it 'calls _draw_portrait with the speaker, in the box\'s own space' do
      portrait = Class.new(described_class) do
        def _draw_portrait(renderer, speaker)
          renderer.rect(12, 12, 64, 64, color: speaker == :smith ? [255, 0, 0] : nil)
        end
      end
      root.add_node(portrait.new(dialogue: talk, unavailable: :hide, width: 400, x: 30, y: 200, portrait_width: 64))
      root.enter_tree
      texts
      call = renderer.calls_to(:rect).find { it.args == [12, 12, 64, 64] }
      expect([call.transforms.map(&:args), call.options[:color]]).to eq([[[30, 200]], [255, 0, 0]])
    end

    it 'keeps the portrait column free, starting the text after it' do
      shown = box(portrait_width: 64)
      expect(line(shown).x).to eq(12 + 64 + 12)
    end

    it 'draws no portrait by default' do
      shown = box(portrait_width: 64)
      shown._draw_portrait(renderer, :smith)
      expect(renderer.calls).to eq([])
    end

    it 'allocates nothing drawing, typing or not' do
      shown = box(reveal: 10)
      tick
      quiet = QuietRenderer.new
      view = screen_view
      typing = -> { root.draw(quiet, view) }
      typing.call
      expect(&typing).to allocate_nothing
      line(shown).reveal_all
      tick
      root.draw(quiet, view)
      expect { root.draw(quiet, view) }.to allocate_nothing
    end
  end

  describe 'who drives it' do
    let(:players) do
      engine::Players.new(
        [engine::Player.new(id: 0, device: RGame::Util::Controls.gamepad(0)),
         engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(1))]
      )
    end

    def tick_players(*pads)
      backend = FakeInputBackend.new
      pads.each { backend.hold(RGame::Util::Controls::PAD_A, device: RGame::Util::Controls.gamepad(it)) }
      players.poll(backend)
      root.control(players)
      root.update(1.0 / 60)
    end

    def press_players(pad)
      tick_players(pad)
      tick_players
    end

    it 'moves only player 2\'s conversation on player 2\'s confirm, one box per PlayerLayer' do
      root.add_component(players)
      one = talk
      two = talk
      box(dialogue: one, parent: root.add_node(engine::PlayerLayer.new(player: players[0])))
      box(dialogue: two, parent: root.add_node(engine::PlayerLayer.new(player: players[1])))
      tick_players
      tick_players
      press_players(1)
      expect([one.beat, two.beat]).to eq(%i[greeting work])
    end

    it 'answers to input_owner in the overlay band during solo!, as every node does' do
      root.add_component(players)
      viewports = engine::Viewports.new(players, width: 640, height: 480)
      root.add_component(viewports)
      viewports.solo!(engine::Camera.new)
      dialogue = talk
      box(dialogue:, band: :overlay, input_owner: players[1])
      tick_players
      tick_players
      press_players(0)
      untouched = dialogue.beat
      press_players(1)
      expect([untouched, dialogue.beat]).to eq(%i[greeting work])
    end
  end
end
