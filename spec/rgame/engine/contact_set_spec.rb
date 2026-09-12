# frozen_string_literal: true

RSpec.describe RGame::Engine::ContactSet do
  subject(:contacts) { described_class.new }

  # The set holds colliders, but it never calls anything on them — identity is all it
  # compares — so plain objects stand in for them here.
  let(:rock)   { Object.new }
  let(:bullet) { Object.new }

  describe '#started?' do
    it 'is true for a contact absent last step' do
      contacts.begin_frame
      expect(contacts.started?(rock)).to be(true)
    end

    it 'is false for a contact held last step' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.begin_frame
      expect(contacts.started?(rock)).to be(false)
    end

    # A pair that stopped touching for a step and met again has started a new contact,
    # not continued the old one: the comparison is against the step just gone, not
    # against everything ever seen.
    it 'is true for a contact held two steps ago' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.begin_frame # rock not added: the pair came apart
      contacts.begin_frame
      expect(contacts.started?(rock)).to be(true)
    end

    # Recording this step does not change the answer, which is what lets the collision
    # world ask before it records and read the guard in the order it happens.
    it 'is unchanged by recording the contact this step' do
      contacts.begin_frame
      contacts.add(rock)
      expect(contacts.started?(rock)).to be(true)
    end
  end

  describe '#touching?' do
    it 'is true for a contact already recorded this step' do
      contacts.begin_frame
      contacts.add(rock)
      expect(contacts.touching?(rock)).to be(true)
    end

    it 'is false for a contact that was only held last step' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.begin_frame
      expect(contacts.touching?(rock)).to be(false)
    end

    it 'is false for a contact never recorded' do
      contacts.begin_frame
      expect(contacts.touching?(rock)).to be(false)
    end
  end

  describe '#each_ended' do
    def ended
      found = []
      contacts.each_ended { |other| found << other }
      found
    end

    it 'yields a contact held last step and not this one' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.begin_frame
      expect(ended).to eq([rock])
    end

    it 'yields nothing for a contact that is still held' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.begin_frame
      contacts.add(rock)
      expect(ended).to be_empty
    end

    it 'yields only the contacts that ended' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.add(bullet)
      contacts.begin_frame
      contacts.add(rock)
      expect(ended).to eq([bullet])
    end

    it 'yields nothing on the first step' do
      contacts.begin_frame
      expect(ended).to be_empty
    end
  end

  describe '#reset' do
    it 'forgets a contact held last step, so nothing ends' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.reset
      contacts.begin_frame
      found = []
      contacts.each_ended { |other| found << other }
      expect(found).to be_empty
    end

    it 'makes a contact held last step start again' do
      contacts.begin_frame
      contacts.add(rock)
      contacts.reset
      contacts.begin_frame
      expect(contacts.started?(rock)).to be(true)
    end
  end

  # This runs once per collider per frame, plus once per contact, so it sits squarely
  # on the per-frame path (CLAUDE.md: never allocate there). The arrays are swapped and
  # cleared rather than rebuilt, and Array#clear keeps the capacity it grew to, so a
  # steady contact costs nothing at all once the first few steps have sized them.
  it 'allocates nothing per step while a contact lasts' do
    expect do
      contacts.begin_frame
      contacts.touching?(rock)
      contacts.started?(rock)
      contacts.add(rock)
      contacts.each_ended { |_other| nil }
    end.to allocate_nothing
  end
end
