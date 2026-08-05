# frozen_string_literal: true

require 'tmpdir'

# Sound files for the audio specs to load.
#
#   AudioFixture.write_wav(seconds: 0.1)  # => "/tmp/.../tone_1.wav"
#   AudioFixture::OGG                     # => the committed Vorbis fixture
#
# WAV is generated here for the same reason PngFixture generates its PNGs: a
# hand-written RIFF header is short enough to read, so what the file *is* stays
# visible next to the assertion instead of hiding inside a binary.
#
# Vorbis is the exception and is committed, because encoding one needs an
# encoder — see tools/make_ogg_fixture.c, which produced spec_core/fixtures.
# Both formats matter: WAV goes through miniaudio's own decoder and Vorbis
# through the one this project wired in (ext/rgame_core/audio/vorbis_decoder.c), so a
# spec that used only WAV would not touch the part we wrote.
module AudioFixture
  # 0.25 s of stereo tone, 440 Hz left and 880 Hz right.
  OGG = File.expand_path('../fixtures/tone.ogg', __dir__)

  SAMPLE_RATE = 44_100
  TWO_PI = 2 * Math::PI

  module_function

  # A mono 16-bit PCM WAV holding a sine tone, in a temporary directory that
  # lives as long as the process.
  def write_wav(seconds: 0.05, frequency: 440.0, name: nil)
    path = File.join(directory, name || "tone_#{next_id}.wav")
    File.binwrite(path, encode_wav(seconds, frequency))
    path
  end

  # A file that is not a sound at all, for the "corrupt asset" path. The `.ogg`
  # extension is deliberate: the engine must decide by content, not by name.
  def write_garbage(name: nil)
    path = File.join(directory, name || "garbage_#{next_id}.ogg")
    File.binwrite(path, 'this is not an Ogg stream')
    path
  end

  def directory
    @directory ||= Dir.mktmpdir('rgame-audio-fixtures')
  end

  def next_id
    @next_id = (@next_id || 0) + 1
  end

  # RIFF: a "WAVE" container with a 16-byte PCM format chunk and the samples.
  # Everything is little-endian, which is what the 'V'/'v' pack codes mean.
  def encode_wav(seconds, frequency)
    frames = (SAMPLE_RATE * seconds).to_i
    samples = Array.new(frames) do |i|
      (Math.sin(TWO_PI * frequency * i / SAMPLE_RATE) * 20_000).to_i
    end
    data = samples.pack('s<*')

    format = [
      1,                 # PCM, uncompressed
      1,                 # channels
      SAMPLE_RATE,
      SAMPLE_RATE * 2,   # bytes per second: rate * channels * 2 bytes
      2,                 # bytes per frame
      16                 # bits per sample
    ].pack('vvVVvv')

    "RIFF#{[36 + data.bytesize].pack('V')}WAVE" \
      "fmt #{[format.bytesize].pack('V')}#{format}" \
      "data#{[data.bytesize].pack('V')}#{data}"
  end
end
