# frozen_string_literal: true

require 'digest'
require 'net/http'
require 'rbconfig'

SDL2_RELEASE = {
  version: '2.32.10',
  sha256: '5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165'
}.freeze

SDL2_PREFIX = File.expand_path('../build/sdl2', __dir__)

MACOS_DEPLOYMENT_TARGET = '11.0'

# The pinned SDL2 release, and how `rake sdl2` fetches, checks and builds it
# into SDL2_PREFIX: a static, position-independent library for
# `ext/rgame_core/extconf.rb --with-sdl2-static`.
#
# The tarball is checked against SDL2_RELEASE before anything unpacks it, so
# the pin and its checksum live in this one place. SDL's audio subsystem and 2D
# renderer are left out: the engine opens only video and game controllers,
# plays sound through miniaudio and draws with its own GL.
#
# Plain Ruby rather than a .rake file, so every rake file that needs the prefix
# can require it, whatever order rake loads them in.
#
# MACOS_DEPLOYMENT_TARGET is the oldest macOS a platform gem's binaries load on:
# the oldest that runs Ruby 4.0 on Apple Silicon. SDL2 is built for it, so the
# static library never raises the floor the extension links against.
module SDL2Build
  BUILD_DIR = File.expand_path('../build', __dir__)
  NAME = "SDL2-#{SDL2_RELEASE[:version]}".freeze
  TARBALL = File.join(BUILD_DIR, "#{NAME}.tar.gz")
  URL = "https://github.com/libsdl-org/SDL/releases/download/release-#{SDL2_RELEASE[:version]}/#{NAME}.tar.gz".freeze
  SOURCE_DIR = File.join(BUILD_DIR, 'sdl2-src')
  CMAKE_DIR = File.join(BUILD_DIR, 'sdl2-build')

  CMAKE_OPTIONS = %w[
    -DCMAKE_BUILD_TYPE=Release
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_STATIC_PIC=ON -DSDL_TEST=OFF
    -DSDL_AUDIO=OFF -DSDL_RENDER=OFF
  ].freeze

  module_function

  def download(url, path, redirects: 5)
    response = Net::HTTP.get_response(URI(url))
    case response
    when Net::HTTPRedirection
      raise "too many redirects fetching #{URL}" if redirects.zero?

      download(response['location'], path, redirects: redirects - 1)
    when Net::HTTPSuccess
      File.binwrite(path, response.body)
    else
      raise "fetching #{URL} answered #{response.code}"
    end
  end

  def verify(path)
    actual = Digest::SHA256.file(path).hexdigest
    return if actual == SDL2_RELEASE[:sha256]

    raise "#{path} has SHA-256 #{actual}, but SDL2_RELEASE pins #{SDL2_RELEASE[:sha256]}. " \
          "Delete it to fetch #{NAME} again, or correct the pin in rakelib/sdl2_build.rb."
  end

  def cmake_options
    return CMAKE_OPTIONS unless RbConfig::CONFIG['host_os'].include?('darwin')

    [*CMAKE_OPTIONS, "-DCMAKE_OSX_DEPLOYMENT_TARGET=#{MACOS_DEPLOYMENT_TARGET}"]
  end

  # CMake picks Ninja on Windows only when ninja.exe happens to be on PATH, so
  # the generator is named rather than detected.
  def generator
    RbConfig::CONFIG['host_os'].match?(/mingw|mswin/) ? %w[-G Ninja] : []
  end

  # Unpacked from inside build/, so the archive's path has no drive letter,
  # which MSYS2's GNU tar would read as a remote host.
  def unpack_command
    ['tar', '-xzf', File.basename(TARBALL), '-C', File.basename(SOURCE_DIR)]
  end
end
