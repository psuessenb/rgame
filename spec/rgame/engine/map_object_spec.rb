# frozen_string_literal: true

RSpec.describe RGame::Engine::MapObject do
  def object(shape, x:, y:, width: 0.0, height: 0.0, rotation: 0.0)
    described_class.new(id: 1, name: '', class_name: '', layer: 0, x:, y:, width:, height:, rotation:, tile: nil,
                        orientation: RGame::Engine::TileMap::Orientation::IDENTITY, visible: true, shape:,
                        points: [], properties: RGame::Engine::Properties::EMPTY)
  end

  def origin(...)
    built = object(...)
    [built.origin_x, built.origin_y].map { it.round(9) }
  end

  describe 'the origin' do
    it 'is a point object’s own point' do
      expect(origin(:point, x: 10.0, y: 20.0)).to eq([10.0, 20.0])
    end

    it 'is the bottom centre of a box' do
      expect(origin(:rectangle, x: 10.0, y: 20.0, width: 30.0, height: 40.0)).to eq([25.0, 60.0])
    end

    it 'is the bottom centre of an ellipse’s box, as of any shape with one' do
      expect(origin(:ellipse, x: 10.0, y: 20.0, width: 30.0, height: 40.0)).to eq([25.0, 60.0])
    end

    it 'turns with the box, about its corner' do
      # Turned 90° clockwise about (100, 200), the box hangs to the left of
      # that corner, and its bottom edge is its left edge now.
      expect(origin(:rectangle, x: 100.0, y: 200.0, width: 30.0, height: 40.0, rotation: 90.0)).to eq([60.0, 215.0])
    end

    it 'is a polygon’s own corner, which its points are relative to' do
      expect(origin(:polygon, x: 10.0, y: 20.0, width: 16.0, height: 8.0)).to eq([10.0, 20.0])
    end

    it 'is a polyline’s own corner' do
      expect(origin(:polyline, x: 10.0, y: 20.0, width: 16.0, height: 8.0, rotation: 45.0)).to eq([10.0, 20.0])
    end
  end
end
