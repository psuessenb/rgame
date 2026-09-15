# frozen_string_literal: true

require 'open3'
require 'rbconfig'

# Checks what the two compiled extensions link, from the platform's own
# dependency and export listings, and exits 1 on a rule they break:
#
# 1. core_ext's dynamic dependencies name no SDL library.
# 2. core_ext exports no SDL_ symbol, which could collide with another SDL
#    loaded into the same process.
# 3. util_ext's dynamic dependencies name no SDL and no OpenGL library.
#
#   ruby tools/check_linkage.rb [core_ext path] [util_ext path]
#
# The paths default to the extensions in lib/rgame/. A build against the
# system's SDL2 fails rule 1, which is how to see the check fail.
module CheckLinkage
  SDL = /sdl/i
  GL = /\A(libGL\b|OpenGL|opengl32)|OpenGL\.framework/i

  Listing = Data.define(:dependencies, :exports)

  module_function

  # Prints both listings and the broken rules, and returns the broken rules.
  def broken_rules(core, util, out = $stdout)
    core_listing = listing(core)
    util_listing = listing(util)
    report(out, core, core_listing)
    report(out, util, util_listing)

    failures = rule_failures(core, core_listing, util, util_listing)
    out.puts
    failures.each { out.puts("FAIL #{it}") }
    out.puts(failures.empty? ? 'Linkage rules hold.' : "#{failures.size} linkage rule(s) broken.")
    failures
  end

  def rule_failures(core, core_listing, util, util_listing)
    sdl_needed = core_listing.dependencies.grep(SDL)
    exported = sdl_exports(core_listing)
    graphics = (util_listing.dependencies.grep(SDL) + util_listing.dependencies.grep(GL)).uniq
    failures = []
    failures << "#{core} depends on SDL: #{sdl_needed.join(', ')}" if sdl_needed.any?
    failures << "#{core} exports #{exported.size} SDL_ symbols, such as #{exported.first}" if exported.any?
    failures << "#{util} depends on a graphics library: #{graphics.join(', ')}" if graphics.any?
    failures
  end

  def report(out, path, listing)
    out.puts("== #{path}")
    listing.dependencies.each { out.puts("  needs #{it}") }
    out.puts("  exports #{listing.exports.size} symbols, #{sdl_exports(listing).size} of them SDL_")
  end

  def sdl_exports(listing) = listing.exports.grep(/\A_?SDL_/)

  def listing(path)
    raise ArgumentError, "no such file: #{path}" unless File.file?(path)

    case RbConfig::CONFIG['host_os']
    when /darwin/ then macos(path)
    when /mingw|mswin/ then windows(path)
    else linux(path)
    end
  end

  def linux(path)
    dependencies = capture('readelf', '-d', path).scan(/\(NEEDED\)\s+Shared library: \[([^\]]+)\]/).flatten
    exports = capture('nm', '-D', '--defined-only', path).lines.map { it.split.last }
    Listing.new(dependencies:, exports:)
  end

  # The first line of `otool -L` names the file itself.
  def macos(path)
    dependencies = capture('otool', '-L', path).lines.drop(1).map { it.strip.split(' (').first }
    exports = capture('nm', '-gU', path).lines.map { it.split.last }
    Listing.new(dependencies:, exports:)
  end

  # objdump's private headers hold both the import directory ("DLL Name:") and
  # the export table, whose names follow its "[Ordinal/Name Pointer] Table"
  # heading up to the next blank line.
  def windows(path)
    headers = capture('objdump', '-p', path)
    dependencies = headers.scan(/DLL Name: (\S+)/).flatten
    table = headers[%r{\[Ordinal/Name Pointer\] Table[^\n]*\n(.*?)(?:\n\s*\n|\z)}m, 1].to_s
    exports = table.lines.filter_map { it[/\[\s*\d+\].*?(\S+)\s*\z/, 1] }
    Listing.new(dependencies:, exports:)
  end

  def capture(*command)
    output, status = Open3.capture2(*command)
    raise "#{command.join(' ')} failed" unless status.success?

    output
  end
end

if $PROGRAM_NAME == __FILE__
  dlext = RbConfig::CONFIG['DLEXT']
  lib = File.expand_path('../lib/rgame', __dir__)
  core = ARGV[0] || File.join(lib, "core_ext.#{dlext}")
  util = ARGV[1] || File.join(lib, "util_ext.#{dlext}")
  exit(CheckLinkage.broken_rules(core, util).empty? ? 0 : 1)
end
