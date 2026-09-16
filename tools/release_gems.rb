# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'
require 'rubygems/package'

require_relative 'check_platform_gem'
require_relative '../lib/rgame/version'

# Decides which of a run's gems to push to RubyGems, and says why.
#
# One version ships four gems: a platform gem per platform, and the source gem
# for every other machine. Which of them RubyGems already has decides what is
# left to push, so a release that failed halfway finishes on a later run instead
# of needing a new version.
#
#   ruby tools/release_gems.rb pkg
#
# It prints the gems to push on stdout, in push order, one path per line, and
# the reasoning on stderr. It exits 1 on a directory that cannot be released:
#
# 1. Every gem in it is the version lib/rgame/version.rb names.
# 2. The gems are exactly one per platform tools/check_platform_gem.rb names,
#    plus the source gem. A build job dropped from the matrix then fails the
#    release rather than shrinking it.
#
# Platform gems push before the source gem. RubyGems indexes each push on its
# own, so a window where the version looks source-only exists either way; this
# keeps it to seconds.
#
# A version that is already partly published may only be finished by the commit
# the vX.Y.Z tag names. Otherwise main has moved on, and the gems still missing
# would hold code the published ones do not — one version number over two
# different engines. Refusing is a no-op rather than a failure, because every
# version released before platform gems existed is missing three of them for
# good.
module ReleaseGems
  SOURCE_PLATFORM = 'ruby'
  PLATFORMS = (CheckPlatformGem::PLATFORMS + [SOURCE_PLATFORM]).freeze
  VERSIONS_URI = URI('https://rubygems.org/api/v1/versions/rgame.json')

  Built = Data.define(:path, :version, :platform)
  Plan = Data.define(:push, :reason)

  module_function

  # Prints the plan, writes the gems to push to `out`, and returns the plan.
  def report(dir, out = $stdout, log = $stderr)
    version = RGame::VERSION
    gems = built_gems(dir)
    log.puts("== rgame #{version}, #{gems.size} gem(s) in #{dir}")
    gems.each { log.puts("  #{it.platform} #{File.basename(it.path)}") }

    failures = mismatches(version, gems)
    failures.each { log.puts("FAIL #{it}") }
    abort("#{failures.size} release rule failure(s).") unless failures.empty?

    decide(version, gems, log).tap do |plan|
      log.puts(plan.reason)
      plan.push.each { out.puts(it.path) }
    end
  end

  # What to push, and the sentence explaining it. Pure: every fact it weighs is
  # an argument, so the branches no single run reaches are still testable.
  #
  # An untagged version is this commit's to release only while nothing of it is
  # published. Once something is, the tag is the only evidence of which commit
  # put it there, and no tag is no evidence.
  def plan(version:, published:, tag_sha:, head_sha:, gems:)
    wanted = order(gems)
    missing = wanted.reject { published.include?(it.platform) }
    return Plan.new(push: [], reason: "rgame #{version} is complete on RubyGems — nothing to push.") if missing.empty?

    ours = published.empty? ? tag_sha.nil? || tag_sha == head_sha : tag_sha == head_sha
    return Plan.new(push: [], reason: refusal(version, missing, wanted, published, tag_sha, head_sha)) unless ours

    reason =
      if published.empty?
        "rgame #{version} is not on RubyGems — pushing #{describe(missing)}."
      else
        "rgame #{version} is missing #{missing.size} of its #{wanted.size} gems, and v#{version} " \
          "names this commit — pushing #{describe(missing)}."
      end
    Plan.new(push: missing, reason: reason)
  end

  # Why a version this run holds gems for is not this run's to publish.
  def refusal(version, missing, wanted, published, tag_sha, head_sha)
    named = tag_sha ? "v#{version} names #{short(tag_sha)}" : "no v#{version} tag exists"
    if published.empty?
      "#{named}, and no gem of rgame #{version} is on RubyGems. HEAD is #{short(head_sha)}. " \
        'Delete the tag to release this commit, or bump the version.'
    else
      "rgame #{version} is missing #{missing.size} of its #{wanted.size} gems, but #{named} " \
        "and HEAD is #{short(head_sha)}. That release belongs to another commit — " \
        'bump the version to release this one.'
    end
  end

  # A directory that cannot be released, whatever RubyGems holds.
  def mismatches(version, gems)
    platforms = gems.map(&:platform)
    failures = gems.reject { it.version == version }
                   .map { "rule 1: #{File.basename(it.path)} is version #{it.version}, not #{version}" }
    missing = PLATFORMS - platforms
    failures << "rule 2: no gem for #{missing.join(', ')}" if missing.any?
    unexpected = platforms.tally.reject { |platform, count| PLATFORMS.include?(platform) && count == 1 }
    failures << "rule 2: unexpected #{unexpected.map { |p, c| "#{c} × #{p}" }.join(', ')}" if unexpected.any?
    failures
  end

  # The platforms RubyGems holds for one version.
  def rubygems_platforms(version, versions = fetch_versions)
    versions.select { it['number'] == version }.map { it['platform'] }
  end

  # Every version rgame has published. An answer that is neither success nor
  # "no such gem" is unknown rather than empty: guessing would let a RubyGems
  # hiccup decide whether a release happens, and how much of one.
  def fetch_versions(uri = VERSIONS_URI)
    response = Net::HTTP.get_response(uri)
    case response
    when Net::HTTPSuccess then JSON.parse(response.body)
    when Net::HTTPNotFound then []
    else abort "RubyGems answered #{response.code} — refusing to guess"
    end
  end

  def built_gems(dir)
    Dir.glob('*.gem', base: dir).sort.map do |name|
      path = File.join(dir, name)
      spec = Gem::Package.new(path).spec
      Built.new(path: path, version: spec.version.to_s, platform: spec.platform.to_s)
    end
  end

  # The commit a tag names, peeled, so an annotated tag reads like a plain one.
  def tag_sha(version)
    out, status = Open3.capture2('git', 'rev-parse', '-q', '--verify', "refs/tags/v#{version}^{commit}")
    status.success? ? out.strip : nil
  end

  def head_sha
    ENV['GITHUB_SHA'] || Open3.capture2('git', 'rev-parse', 'HEAD').first.strip
  end

  def decide(version, gems, log)
    tag = tag_sha(version)
    log.puts("v#{version} names #{tag ? short(tag) : 'nothing yet'}; HEAD is #{short(head_sha)}")
    plan(version: version, published: rubygems_platforms(version), tag_sha: tag, head_sha: head_sha, gems: gems)
  end

  def order(gems) = PLATFORMS.filter_map { |platform| gems.find { |gem| gem.platform == platform } }

  def describe(gems) = gems.map(&:platform).join(', ')

  def short(sha) = sha.to_s[0, 7]
end

ReleaseGems.report(ARGV[0] || 'pkg') if $PROGRAM_NAME == __FILE__
