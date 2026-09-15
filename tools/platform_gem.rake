# frozen_string_literal: true

require 'rake/extensiontask'
require_relative '../rakelib/sdl2_build'

# The platform gem's build, for the platform of the machine it runs on. Both
# extensions compile with rake-compiler, core_ext links the static SDL2
# `rake sdl2` builds, and the gem lands in pkg/:
#
#   rake -f tools/platform_gem.rake platform_gem
#
# Linux cross-compiles inside the rake-compiler-dock x86_64-linux-gnu image. Its
# cross Ruby links no libruby, and its glibc is old enough for the binaries to
# load on older distributions. macOS and Windows build natively. A Mac's
# platform is named without its Darwin version, so the gem matches every macOS
# on that CPU, and macOS builds for MACOS_DEPLOYMENT_TARGET. Neither extension
# links libruby, except on Windows, where an extension must import the Ruby DLL.
#
# The gem holds rgame.gemspec's files minus ext/, the two binaries, and SDL2's
# licence, and declares no extensions. rake-compiler packages each file from the same path in the checkout,
# so the licence is copied from build/sdl2 to licenses/SDL2/, which git ignores
# and the source gem does not ship. rake-compiler bounds required_ruby_version
# to the Ruby it builds for. On Linux, its `cross` task runs first: without it
# the gem would depend on a second, native build of both extensions. `cross`
# edits the `native` task, which rake-compiler leaves undefined under the
# image's RAKE_EXTENSION_TASK_NO_NATIVE, so the rakefile defines an empty one.
#
# It refuses to run while ext/ holds the objects `make ext` builds in place,
# because make would find them through VPATH and link them rather than compile.
# That refusal also settles lib/rgame/, where a native build installs its
# binaries: after `make ext-clean`, the next `make ext` builds and copies its
# own over them.
#
# A rakefile of its own rather than part of the Rakefile, because rake-compiler
# warns about those objects on every rake invocation, and because the image has
# no bundle to load the Rakefile's RSpec tasks from.
module PlatformGem
  ROOT = File.expand_path('..', __dir__)
  SDL2_LICENCE = 'licenses/SDL2/LICENSE.txt'
  EXTENSIONS = { 'rgame_util' => 'util_ext', 'rgame_core' => 'core_ext' }.freeze

  PLATFORM = case RbConfig::CONFIG['host_os']
             when /linux/ then 'x86_64-linux-gnu'
             when /darwin/ then "#{Gem::Platform.local.cpu}-darwin"
             else Gem::Platform.local.to_s
             end

  module_function

  def cross_compiled? = PLATFORM.end_with?('-linux-gnu')

  def macos? = PLATFORM.end_with?('-darwin')

  def gem_path(spec) = "pkg/#{spec.name}-#{spec.version}-#{PLATFORM}.gem"

  def make_ext_objects = Dir.glob('ext/*/*.{o,obj,so,bundle}', base: ROOT)
end

Dir.chdir(PlatformGem::ROOT)

ENV['MACOSX_DEPLOYMENT_TARGET'] = MACOS_DEPLOYMENT_TARGET if PlatformGem.macos?

gemspec = Gem::Specification.load('rgame.gemspec')
gemspec.extensions = []
gemspec.files = gemspec.files.grep_v(%r{\Aext/}) + [PlatformGem::SDL2_LICENCE]

file PlatformGem::SDL2_LICENCE => "#{SDL2_PREFIX}/lib/pkgconfig/sdl2.pc" do |t|
  mkdir_p File.dirname(t.name)
  cp File.join(SDL2_PREFIX, 'share/licenses/SDL2/LICENSE.txt'), t.name
end

task :native if PlatformGem.cross_compiled?

PlatformGem::EXTENSIONS.each do |dir, name|
  Rake::ExtensionTask.new(name, gemspec) do |ext|
    ext.ext_dir = "ext/#{dir}"
    ext.lib_dir = 'lib/rgame'
    ext.config_options << '--disable-libruby-link'
    ext.config_options << "--with-sdl2-static=#{SDL2_PREFIX}" if name == 'core_ext'
    if PlatformGem.cross_compiled?
      ext.cross_compile = true
      ext.cross_platform = [PlatformGem::PLATFORM]
    else
      ext.platform = PlatformGem::PLATFORM
    end
  end
end

desc "Build the #{PlatformGem::PLATFORM} platform gem into pkg/"
task :platform_gem do
  objects = PlatformGem.make_ext_objects
  unless objects.empty?
    abort "ext/ holds #{objects.size} objects from `make ext`, such as #{objects.first}. " \
          'rake-compiler would link them instead of compiling. Run: make ext-clean'
  end

  native = "native:#{PlatformGem::PLATFORM}"
  unless Rake::Task.task_defined?(native)
    abort "No cross Ruby for #{PlatformGem::PLATFORM} in ~/.rake-compiler/config.yml. " \
          'The Linux platform gem builds in the rake-compiler-dock image, as ci.yml does.'
  end

  Rake::Task[:sdl2].invoke
  Rake::Task[:cross].invoke if PlatformGem.cross_compiled?
  Rake::Task[native].invoke
  Rake::Task['gem'].invoke
  puts "Built #{PlatformGem.gem_path(gemspec)}"
end
