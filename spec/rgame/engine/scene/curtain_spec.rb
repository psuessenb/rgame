# frozen_string_literal: true

# A tick is an eighth of a second, so a Fade of half a second covers in four
# ticks and reveals in four more, with no rounding.
RSpec.describe RGame::Engine::Scene::Curtain do
  subject(:curtain) { described_class.new(host) }

  let(:host) { RGame::Engine::Node2D.new.tap(&:enter_tree) }
  let(:fade) { RGame::Engine::Scene::Fade.new(cover: 0.5, reveal: 0.5) }
  let(:view) { RGame::Engine::View.new(width: 320, height: 240) }

  def dt = 0.125

  # How opaque the cover draws: 0 when it draws nothing, and 1.0 when it draws
  # with no `faded` around it.
  def drawn
    renderer = FakeRenderer.new
    curtain.draw(renderer, view)
    rect = renderer.calls_to(:rect).first
    return 0 unless rect

    rect.transforms.find { it.name == :faded }&.args&.first || 1.0
  end

  def run(ticks)
    Array.new(ticks) do
      curtain.update(dt)
      block_given? ? [drawn, yield] : drawn
    end
  end

  it 'draws nothing and is ready before anything closes it' do
    expect([drawn, curtain.ready?, curtain.running?]).to eq([0, true, false])
  end

  it 'stays open for a close with no transition' do
    curtain.close(nil)
    expect([curtain.running?, curtain.ready?]).to eq([false, true])
  end

  it 'covers, is ready once opaque, and reveals when opened' do
    curtain.close(fade)
    covering = run(4) { curtain.ready? }
    curtain.open
    expect(covering + run(4) { curtain.ready? })
      .to eq([[0.25, false], [0.5, false], [0.75, false], [1.0, true],
              [0.75, true], [0.5, true], [0.25, true], [0, true]])
  end

  it 'is covering until it opens, and running until the reveal ends' do
    curtain.close(fade)
    run(4)
    states = [[curtain.covering?, curtain.running?]]
    curtain.open
    states << [curtain.covering?, curtain.running?]
    run(4)
    expect(states << [curtain.covering?, curtain.running?]).to eq([[true, true], [false, true], [false, false]])
  end

  it 'covers at once with at_once:' do
    curtain.close(fade, at_once: true)
    expect([drawn, curtain.ready?]).to eq([1.0, true])
  end

  it 'keeps the cover under way for a close during it' do
    curtain.close(fade)
    run(2)
    curtain.close(RGame::Engine::Scene::Fade.new(cover: 2, reveal: 2))
    expect(run(2)).to eq([0.75, 1.0])
  end

  it 'covers again from where a reveal got to, in the running durations when given none' do
    curtain.close(fade)
    run(4)
    curtain.open
    run(2)
    curtain.close(nil)
    expect(run(4)).to eq([0.625, 0.75, 0.875, 1.0])
  end

  it 'covers in the colour of the transition it runs' do
    red = RGame::Util::Color.new(255, 0, 0)
    curtain.close(RGame::Engine::Scene::Fade.new(cover: 0.5, reveal: 0.5, color: red), at_once: true)
    renderer = FakeRenderer.new
    curtain.draw(renderer, view)
    expect(renderer.calls_to(:rect).first.options[:color]).to eq(red)
  end

  it 'opens nothing when nothing covers' do
    curtain.open
    expect(curtain.running?).to be(false)
  end

  it 'hangs its fade off the host, outside its child list' do
    curtain.close(fade)
    expect(host.children).to be_empty
  end
end
