# frozen_string_literal: true

require_relative '../../tools/release_gems'

RSpec.describe ReleaseGems do
  # The commit main was on when this spec was written, and the one v0.3.1 names.
  let(:head) { 'cbd0b21e756760adef306456a9384dcb4ac1bd7d' }
  let(:elsewhere) { '78f462ee07288faf201cffe77e563f0dc05ebde4' }
  let(:version) { '0.4.0' }
  let(:gems) { described_class::PLATFORMS.map { built(it) } }

  def built(platform, at: version)
    suffix = platform == described_class::SOURCE_PLATFORM ? '' : "-#{platform}"
    described_class::Built.new(path: "pkg/rgame-#{at}#{suffix}.gem", version: at, platform: platform)
  end

  def plan(published:, tag_sha:, head_sha: head, at: version, holding: gems)
    described_class.plan(version: at, published: published, tag_sha: tag_sha, head_sha: head_sha, gems: holding)
  end

  describe '.plan' do
    it 'pushes every gem of a version RubyGems does not have' do
      result = plan(published: [], tag_sha: nil)

      expect(result.push.map(&:platform)).to eq(described_class::PLATFORMS)
      expect(result.reason).to include('is not on RubyGems')
    end

    it 'pushes the platform gems before the source gem' do
      result = plan(published: [], tag_sha: nil, holding: gems.reverse)

      expect(result.push.map(&:platform).last).to eq(described_class::SOURCE_PLATFORM)
    end

    it 'pushes what a release this commit left half-finished is missing' do
      result = plan(published: ['x86_64-linux-gnu'], tag_sha: head)

      expect(result.push.map(&:platform)).to eq(%w[arm64-darwin x64-mingw-ucrt ruby])
      expect(result.reason).to include('missing 3 of its 4 gems', 'names this commit')
    end

    it 'refuses to finish a release another commit made' do
      result = plan(published: ['x86_64-linux-gnu'], tag_sha: elsewhere)

      expect(result.push).to be_empty
      expect(result.reason).to include('78f462e', 'cbd0b21', 'belongs to another commit')
    end

    it 'refuses to finish a release no tag claims' do
      result = plan(published: ['x86_64-linux-gnu'], tag_sha: nil)

      expect(result.push).to be_empty
      expect(result.reason).to include('no v0.4.0 tag exists')
    end

    it 'refuses a commit the tag does not name, before anything is published' do
      result = plan(published: [], tag_sha: elsewhere)

      expect(result.push).to be_empty
      expect(result.reason).to include('Delete the tag')
    end

    it 'pushes nothing once every gem is published' do
      result = plan(published: described_class::PLATFORMS, tag_sha: head)

      expect(result.push).to be_empty
      expect(result.reason).to include('is complete on RubyGems')
    end
  end

  describe '.mismatches' do
    it 'accepts one gem per platform, all at the version' do
      expect(described_class.mismatches(version, gems)).to be_empty
    end

    it 'reports a platform no gem was built for' do
      failures = described_class.mismatches(version, gems.reject { it.platform == 'x64-mingw-ucrt' })

      expect(failures).to contain_exactly('rule 2: no gem for x64-mingw-ucrt')
    end

    it 'reports a gem for a platform rgame does not ship' do
      failures = described_class.mismatches(version, gems + [built('x86_64-linux-musl')])

      expect(failures).to contain_exactly('rule 2: unexpected 1 × x86_64-linux-musl')
    end

    it 'reports two gems for one platform' do
      failures = described_class.mismatches(version, gems + [built('arm64-darwin')])

      expect(failures).to contain_exactly('rule 2: unexpected 2 × arm64-darwin')
    end

    it 'reports a gem built from another version' do
      stale = gems.reject { it.platform == 'ruby' } + [built('ruby', at: '0.3.1')]
      failures = described_class.mismatches(version, stale)

      expect(failures).to contain_exactly('rule 1: rgame-0.3.1.gem is version 0.3.1, not 0.4.0')
    end
  end

  # The payload rubygems.org answered on 2026-09-16, cut to the keys this reads.
  # Recording it keeps the example offline and keeps it real: 0.3.1 is published
  # as a source gem, and its three platform gems will be missing for good.
  describe 'against the versions rgame has published' do
    let(:published) do
      %w[0.3.1 0.3.0 0.2.0 0.1.0].map { { 'number' => it, 'platform' => 'ruby', 'prerelease' => false } }
    end

    it 'reads the platforms of one version' do
      expect(described_class.rubygems_platforms('0.3.1', published)).to eq(['ruby'])
    end

    it 'refuses to publish platform gems for 0.3.1 from a later commit' do
      result = plan(published: described_class.rubygems_platforms('0.3.1', published),
                    tag_sha: elsewhere, at: '0.3.1', holding: described_class::PLATFORMS.map { built(it, at: '0.3.1') })

      expect(result.push).to be_empty
      expect(result.reason).to include('bump the version to release this one')
    end
  end
end
