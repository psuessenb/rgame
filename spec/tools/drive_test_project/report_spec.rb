# frozen_string_literal: true

require_relative '../../../tools/drive_test_project'

RSpec.describe DriveTestProject::Report do
  let(:report) { described_class.new(texts: true) }
  let(:left) { [0, 0, 320, 480] }
  let(:right) { [320, 0, 320, 480] }

  def section(title)
    report.to_s[/^#{title}\n((?:  .*\n)+)/, 1]
  end

  describe 'texts drawn' do
    it 'counts each string with the tick it first appeared on' do
      report.record_text('coin')
      report.ticks = 5
      report.record_text('coin')
      report.record_text('hat')

      expect(section('texts drawn')).to eq(<<~TEXTS)
        \s\s     2  "coin" from tick 0
        \s\s     1  "hat" from tick 5
      TEXTS
    end
  end

  describe 'scenes' do
    let(:root) do
      RGame::Engine::Node2D.new.tap { it.add_component(RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0)])) }
    end
    let(:rooms) do
      probed = Class.new(RGame::Engine::Scene::Rooms).prepend(DriveTestProject.send(:rooms_probe, report))
      world = root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it }
      world.add_component(probed.new)
    end

    it 'lists each room built, each node a move landed, and each room freed, by name, in order' do
      rooms.define(:town) { SpecRoom.new }
      rooms.define(:garden) { SpecRoom.new }
      root.enter_tree
      hero = RGame::Engine::Node2D.new
      rooms.move(hero, to: :town, entrance: 'gate')
      root.sweep_freed
      rooms.move(hero, to: :garden, entrance: 'gate')
      root.sweep_freed

      expect(section('scenes')).to eq(<<~SCENES)
        \s\sbuild :town
        \s\smove RGame::Engine::Node2D to :town
        \s\sbuild :garden
        \s\smove RGame::Engine::Node2D to :garden
        \s\sfree :town
      SCENES
    end
  end

  describe 'texts drawn per clip' do
    it 'lists each string under the innermost clip it was drawn in' do
      report.within_clip(left) { report.record_text('coin') }
      report.ticks = 3
      report.within_clip(right) do
        report.record_text('coin')
        report.within_clip(left) { report.record_text('hat') }
      end

      expect(section('texts drawn per clip')).to eq(<<~TEXTS)
        \s\s[0, 0, 320, 480]
        \s\s       1  "coin" from tick 0
        \s\s       1  "hat" from tick 3
        \s\s[320, 0, 320, 480]
        \s\s       1  "coin" from tick 3
      TEXTS
    end

    it 'is left out of a run with one clip, whose strings it would repeat' do
      report.within_clip(left) { report.record_text('coin') }

      expect(report.to_s).not_to include('texts drawn per clip')
    end

    it 'is left out without texts:' do
      quiet = described_class.new
      quiet.within_clip(left) { quiet.record_text('coin') }
      quiet.within_clip(right) { quiet.record_text('coin') }

      expect(quiet.to_s).not_to include('texts drawn')
    end
  end
end
