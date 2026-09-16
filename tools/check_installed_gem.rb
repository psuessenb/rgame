# frozen_string_literal: true

require_relative 'check_platform_gem'

# Checks the rgame that `gem install` left on disk, and exits 1 on a rule it
# breaks:
#
# 1. It is a platform gem, for one of the platforms rgame ships binaries for.
# 2. It declares no extensions, so the install had nothing to build.
# 3. The install compiled nothing: no extension build directory, and no
#    gem_make.out or mkmf.log anywhere under it.
# 4. It holds exactly one core_ext and one util_ext, in its own lib/rgame/.
# 5. Requiring rgame/game loads those two files and no others, so nothing on the
#    load path is standing in front of the gem.
#
#   ruby tools/check_installed_gem.rb
#
# tools/check_platform_gem.rb asks the same kind of question of a `.gem` file,
# and the two rules about naming binaries are its. What an archive cannot show
# is what installing it did — a compile that ran, or a checkout that answers
# `require` first — so this reads the installation instead, on a machine that
# did not build the gem. The source gem fails rules 1, 2 and 3, which is how to
# see the check fail.
module CheckInstalledGem
  BUILD_LOGS = %w[gem_make.out mkmf.log].freeze

  module_function

  # Prints what is installed and the broken rules, and returns the broken rules.
  def broken_rules(out = $stdout)
    spec = installed_spec
    out.puts("== #{spec.full_name} installed in #{spec.gem_dir}")

    failures = specification_failures(spec) + build_failures(spec) + load_failures(spec, out)
    out.puts
    failures.each { out.puts("FAIL #{it}") }
    out.puts(failures.empty? ? 'Installed gem rules hold.' : "#{failures.size} installed gem rule failure(s).")
    failures
  end

  def installed_spec
    Gem::Specification.find_by_name('rgame')
  rescue Gem::MissingSpecError
    abort 'No rgame is installed. Run: gem install --local pkg/rgame-<version>-<platform>.gem'
  end

  def specification_failures(spec)
    platform = spec.platform.to_s
    binaries = Dir.glob('lib/rgame/*_ext.*', base: spec.gem_dir).sort
    expected = CheckPlatformGem.expected_binaries(platform)
    failures = []
    unless CheckPlatformGem::PLATFORMS.include?(platform)
      failures << "rule 1: platform #{platform} is not one of #{CheckPlatformGem::PLATFORMS.join(', ')}"
    end
    failures << "rule 2: declares extensions #{spec.extensions.inspect}" if spec.extensions.any?
    failures << "rule 4: binaries #{binaries.inspect}, expected #{expected.inspect}" if binaries != expected
    failures
  end

  def build_failures(spec)
    built = Dir.exist?(spec.extension_dir) ? Dir.children(spec.extension_dir) : []
    logs = Dir.glob("**/{#{BUILD_LOGS.join(',')}}", base: spec.gem_dir)
    failures = []
    failures << "rule 3: #{spec.extension_dir} holds #{built.join(', ')}" if built.any?
    failures << "rule 3: the install left #{logs.join(', ')}" if logs.any?
    failures
  end

  # Loads the gem the way a game does, and reports where each binary came from.
  def load_failures(spec, out)
    require 'rgame/game'
    loaded = $LOADED_FEATURES.grep(%r{rgame/(?:core|util)_ext\.})
    loaded.each { out.puts("  loaded #{it}") }
    expected = CheckPlatformGem.expected_binaries(spec.platform.to_s).map { normalize(File.join(spec.gem_dir, it)) }
    return [] if loaded.map { normalize(it) }.sort == expected.sort

    ["rule 5: loaded #{loaded.inspect}, expected #{expected.inspect}"]
  rescue LoadError, StandardError => e
    ["rule 5: requiring rgame/game raised #{e.class}: #{e.message}"]
  end

  # Windows spells an installed gem's directory with backslashes in some places
  # and forward slashes in others, and $LOADED_FEATURES picks its own.
  def normalize(path) = File.expand_path(path).tr('\\', '/')
end

exit(CheckInstalledGem.broken_rules.empty? ? 0 : 1) if $PROGRAM_NAME == __FILE__
