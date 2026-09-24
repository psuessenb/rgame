# frozen_string_literal: true

# A fade sets a volume every tick for as long as it runs, which makes it a
# per-frame path: nothing it does once it has started may build anything.
RSpec.describe RGame::Engine::AudioOut do
  # An audio server that takes each call and keeps nothing. FakeAudio records
  # every call, and a record is an allocation this spec would count as the
  # fade's.
  let(:quiet_audio) do
    Class.new do
      def play_music(_id) = nil
      def stop_music(_id = nil) = nil
      def set_music_volume(_id, _volume) = nil
      def pause_music = nil
      def resume_music = nil
    end
  end

  def mounted
    root = RGame::Engine::Node2D.new
    out = root.add_component(described_class.new(quiet_audio.new))
    root.enter_tree
    [root, out]
  end

  it 'allocates nothing to step a fade in' do
    root, out = mounted
    out.play_music(:theme, fade: 600.0)

    expect { root.update(1.0 / 60) }.to allocate_nothing
  end

  it 'allocates nothing to step a crossfade, a song down and another up' do
    root, out = mounted
    out.play_music(:theme)
    out.crossfade(:battle, over: 600.0)

    expect { root.update(1.0 / 60) }.to allocate_nothing
  end

  it 'allocates nothing to hold a fade while paused' do
    root, out = mounted
    out.play_music(:theme, fade: 600.0)
    out.pause_music

    expect { root.update(1.0 / 60) }.to allocate_nothing
  end

  it 'allocates nothing to step a crossfade a claim started' do
    root, out = mounted
    out.claim_music(:room, :town, priority: 1)
    out.claim_music(:battle, :battle, priority: 10, fade: 600.0)

    expect { root.update(1.0 / 60) }.to allocate_nothing
  end

  it 'allocates nothing for a tick while claims hold and nothing fades' do
    root, out = mounted
    out.claim_music(:room, :town, priority: 1)
    out.claim_music(:battle, :battle, priority: 10)

    expect { root.update(1.0 / 60) }.to allocate_nothing
  end
end
