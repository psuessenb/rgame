# frozen_string_literal: true

RSpec.describe RGame::Engine::Scene::Fade do
  def color = RGame::Util::Color

  it 'holds a colour and two durations, and is frozen' do
    fade = described_class.new(color: color::WHITE, cover: 0.25, reveal: 0.5)

    expect([fade.color, fade.cover, fade.reveal, fade.frozen?]).to eq([color::WHITE, 0.25, 0.5, true])
  end

  it 'covers in black unless given a colour' do
    expect(described_class.new(cover: 1, reveal: 1).color).to eq(color::BLACK)
  end

  it 'equals another with the same colour and durations' do
    one = described_class.new(cover: 1, reveal: 2)
    other = described_class.new(cover: 1, reveal: 2)

    expect(one).to eq(other)
  end

  it 'refuses a colour that is not a Color' do
    expect { described_class.new(color: :black, cover: 1, reveal: 1) }.to raise_error(TypeError, /colour/)
  end

  it 'refuses a duration that is not a number' do
    expect { described_class.new(cover: '1', reveal: 1) }.to raise_error(TypeError, /cover/)
  end

  it 'refuses a duration that is not positive' do
    expect { described_class.new(cover: 1, reveal: 0) }.to raise_error(ArgumentError, /reveal/)
  end
end
