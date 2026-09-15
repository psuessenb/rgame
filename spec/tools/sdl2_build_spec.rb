# frozen_string_literal: true

require 'tempfile'

require_relative '../../rakelib/sdl2_build'

RSpec.describe SDL2Build do
  describe '.verify' do
    it 'refuses a tarball whose checksum is not the pinned one' do
      Tempfile.create('SDL2.tar.gz') do |tarball|
        tarball.write('not the release')
        tarball.close

        expect { described_class.verify(tarball.path) }
          .to raise_error(RuntimeError, /SDL2_RELEASE pins #{SDL2_RELEASE[:sha256]}/)
      end
    end
  end
end
