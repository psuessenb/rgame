# frozen_string_literal: true

require 'rubygems/package'
require 'tmpdir'

require_relative 'check_linkage'
require_relative '../rakelib/sdl2_build'

# Checks a built platform gem by opening the .gem archive itself, and exits 1 on
# a rule it breaks:
#
# 1. The platform is arm64-darwin, x86_64-linux-gnu or x64-mingw-ucrt.
# 2. It holds exactly one core_ext and one util_ext, in lib/rgame/, with the
#    platform's extension: bundle on macOS, so elsewhere.
# 3. It holds no .c, .h, extconf.rb or Makefile, and declares no extensions.
# 4. required_ruby_version admits .ruby-version's Ruby and no release,
#    preview or development build of the next minor.
# 5. It holds SDL2's licence.
# 6. Its files are the source gem's files outside ext/, plus the two binaries
#    and the licence, and nothing else.
# 7. tools/check_linkage.rb's rules hold for the two binaries.
# 8. Neither binary depends on libruby or carries a runpath (Linux, macOS).
# 9. Neither binary needs a newer OS than the gem claims: MACOS_DEPLOYMENT_TARGET
#    on macOS, GLIBC_FLOOR on Linux.
#
#   ruby tools/check_platform_gem.rb pkg/rgame-<version>-<platform>.gem
#
# Rules 7 to 9 read the binaries with the platform's own tools, so they run on
# the platform the gem is for. tools/platform_gem.rake runs the checker on every
# gem it builds. The source gem fails rules 1 to 6, which is how to see the
# check fail.
#
# It reads the archive rather than the specification the rakefile built, so it
# does not share the derivation it checks. The source gem's file list is the one
# thing it takes from rgame.gemspec, as the reference for rule 6.
module CheckPlatformGem
  ROOT = File.expand_path('..', __dir__)
  PLATFORMS = %w[arm64-darwin x86_64-linux-gnu x64-mingw-ucrt].freeze
  SDL2_LICENCE = 'licenses/SDL2/LICENSE.txt'
  GLIBC_FLOOR = '2.29'
  NEXT_MINOR_BUILDS = %w[.0.dev .0.preview1 .0].freeze
  SOURCES = %r{\.[ch]\z|(?:\A|/)(?:extconf\.rb|Makefile)\z}

  module_function

  # Prints the gem's platform, its binaries' listings and the broken rules, and
  # returns the broken rules.
  def broken_rules(gem_path, out = $stdout)
    package = Gem::Package.new(gem_path)
    platform = package.spec.platform.to_s
    out.puts("== #{gem_path}, platform #{platform}")

    failures = package_failures(package, platform)
    Dir.mktmpdir('rgame-platform-gem') do |dir|
      package.extract_files(dir)
      failures.concat(binary_failures(dir, package.contents, platform, out))
    end

    out.puts
    failures.each { out.puts("FAIL #{it}") }
    out.puts(failures.empty? ? 'Platform gem rules hold.' : "#{failures.size} platform gem rule failure(s).")
    failures
  end

  def package_failures(package, platform)
    spec = package.spec
    files = package.contents
    binaries = files.grep(%r{(?:\A|/)(?:core|util)_ext\.(?:so|bundle|dll|dylib)\z})
    failures = []
    failures << "rule 1: platform #{platform} is not one of #{PLATFORMS.join(', ')}" unless PLATFORMS.include?(platform)
    if binaries.sort != expected_binaries(platform)
      failures << "rule 2: binaries #{binaries.inspect}, expected #{expected_binaries(platform).inspect}"
    end
    compiled = files.grep(SOURCES)
    failures << "rule 3: holds #{compiled.size} build inputs, such as #{compiled.first}" if compiled.any?
    failures << "rule 3: declares extensions #{spec.extensions.inspect}" if spec.extensions.any?
    failures.concat(ruby_version_failures(spec.required_ruby_version))
    failures << "rule 5: no #{SDL2_LICENCE}" unless files.include?(SDL2_LICENCE)
    failures.concat(file_list_failures(files, platform))
  end

  def ruby_version_failures(requirement)
    current = Gem::Version.new(File.read(File.join(ROOT, '.ruby-version'))[/\d+\.\d+\.\d+/])
    major, minor = current.segments
    next_minor = NEXT_MINOR_BUILDS.map { Gem::Version.new("#{major}.#{minor + 1}#{it}") }
    failures = []
    failures << "rule 4: #{requirement} refuses Ruby #{current}" unless requirement.satisfied_by?(current)
    admitted = next_minor.select { requirement.satisfied_by?(it) }
    failures << "rule 4: #{requirement} admits Ruby #{admitted.join(', ')}" if admitted.any?
    failures
  end

  def file_list_failures(files, platform)
    source = Gem::Specification.load(File.join(ROOT, 'rgame.gemspec')).files.grep_v(%r{\Aext/})
    expected = source + expected_binaries(platform) + [SDL2_LICENCE]
    failures = []
    missing = expected - files
    extra = files - expected
    failures << "rule 6: missing #{missing.size} files, such as #{missing.first}" if missing.any?
    failures << "rule 6: #{extra.size} unexpected files, such as #{extra.first}" if extra.any?
    failures
  end

  def binary_failures(dir, files, platform, out)
    core, util = expected_binaries(platform)
    return [] unless files.include?(core) && files.include?(util)

    core_path = File.join(dir, core)
    util_path = File.join(dir, util)
    core_listing = CheckLinkage.listing(core_path)
    util_listing = CheckLinkage.listing(util_path)
    CheckLinkage.report(out, core, core_listing)
    CheckLinkage.report(out, util, util_listing)

    CheckLinkage.rule_failures(core, core_listing, util, util_listing).map { "rule 7: #{it}" } +
      portability_failures(core, core_listing, platform) +
      portability_failures(util, util_listing, platform)
  end

  def portability_failures(name, listing, platform)
    failures = []
    unless platform.include?('mingw')
      libruby = listing.dependencies.grep(/libruby/)
      failures << "rule 8: #{name} depends on #{libruby.join(', ')}" if libruby.any?
      failures << "rule 8: #{name} has runpath #{listing.runpaths.join(', ')}" if listing.runpaths.any?
    end
    floor = os_floor(platform)
    needed = listing.minimum_os&.[](/[\d.]+\z/)
    if floor && (needed.nil? || Gem::Version.new(needed) > Gem::Version.new(floor))
      failures << "rule 9: #{name} needs #{listing.minimum_os || 'an unknown OS version'}, newer than #{floor}"
    end
    failures
  end

  def os_floor(platform)
    case platform
    when /darwin/ then MACOS_DEPLOYMENT_TARGET
    when /linux/ then GLIBC_FLOOR
    end
  end

  def expected_binaries(platform)
    dlext = platform.include?('darwin') ? 'bundle' : 'so'
    %W[lib/rgame/core_ext.#{dlext} lib/rgame/util_ext.#{dlext}]
  end
end

exit(CheckPlatformGem.broken_rules(ARGV.fetch(0)).empty? ? 0 : 1) if $PROGRAM_NAME == __FILE__
