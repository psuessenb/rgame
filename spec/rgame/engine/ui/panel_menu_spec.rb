# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::PanelMenu do
  let(:root) { RGame::Engine::Node2D.new }
  let(:column) { RGame::Engine::UI::Column.new(item_width: 200, item_height: 40, spacing: 10) }
  let(:menu) { root.add_node(described_class.new(layout: column, padding: 12)) }

  # One log for every nine-slice id, in draw order, so the panel and the buttons
  # can be told apart and ordered against each other.
  let(:log) { [] }
  let(:renderer) do
    ids = [:panel, *RGame::Engine::UI::PanelButton::STYLE.elements.values]
    FakeRenderer.new.tap { |r| ids.each { |id| r.register_nine_slice(id, slice(id)) } }
  end

  def slice(id)
    entries = log
    Class.new do
      define_method(:draw) { |_renderer, x, y, width, height, **| entries << [id, x, y, width, height] }
    end.new
  end

  before { RGame::Engine::I18n.load_hash(en: { button0: 'Button 0', button1: 'Button 1', another: 'Another', one: 'One' }) }

  def button(label) = RGame::Engine::UI::PanelButton.new(label: label)

  def draw
    root.enter_tree
    log.clear
    root.draw(renderer, screen_view)
    log
  end

  def panels = draw.select { |id, *| id == :panel }

  it 'draws one panel enclosing its bounds, padding beyond them on every side' do
    2.times { |index| menu.add(button("button#{index}")) }
    expect(panels).to eq([[:panel, -12, -12, 224, 114]])
  end

  it 'grows the panel when a button is added' do
    2.times { |index| menu.add(button("button#{index}")) }
    expect { menu.add(button('another')) }.to change { panels.last.last }.from(114).to(164)
  end

  it 'draws the panel before its buttons, so they sit on top of it' do
    menu.add(button('one'))
    expect(draw.map(&:first)).to eq(%i[panel button_focus])
  end

  it 'draws whichever nine-slice it was built with' do
    other = root.add_node(described_class.new(layout: column, panel: :button_disabled))
    other.add(button('one'))
    expect(draw.map(&:first)).to eq(%i[button_disabled button_focus])
  end

  it 'pads by 16 unless told otherwise' do
    expect(described_class.new(layout: column).padding).to eq(16)
  end

  it 'allocates nothing drawing its panel' do
    menu.add(button('one'))
    quiet = Class.new { def nine_slice(_id, _x, _y, _width, _height) = nil }.new
    expect { menu.on_draw(quiet, nil) }.to allocate_nothing
  end
end
