# frozen_string_literal: true

RSpec.describe RGame::Engine::Presentation do
  # Named `build` rather than `presentation`: a `subject(:presentation)` in a
  # nested group would shadow a helper of the same name, and the failure is an
  # arity error rather than anything that points at the clash.
  def build(mode, width: 640, height: 480)
    described_class.new(width: width, height: height, mode: mode)
  end

  describe ':disabled' do
    subject(:presentation) { build(:disabled) }

    it 'is not scaling anything' do
      expect(presentation).not_to be_scaled
    end

    it 'reports the window as the logical size, so a caller has one number to read' do
      presentation.fit(1600, 900)

      expect([presentation.width, presentation.height]).to eq([1600, 900])
    end

    it 'leaves the transform alone' do
      presentation.fit(1600, 900)

      expect([presentation.scale_x, presentation.scale_y]).to eq([1.0, 1.0])
      expect([presentation.offset_x, presentation.offset_y]).to eq([0.0, 0.0])
    end
  end

  describe ':stretch' do
    subject(:presentation) { build(:stretch) }

    it 'keeps the logical size whatever the window does' do
      presentation.fit(1600, 900)

      expect([presentation.width, presentation.height]).to eq([640, 480])
    end

    it 'scales each axis to fill the window, distorting if it must' do
      presentation.fit(1600, 900)

      expect(presentation.scale_x).to eq(2.5)
      expect(presentation.scale_y).to eq(1.875)
    end

    it 'never offsets, because there is nothing left over' do
      presentation.fit(1600, 900)

      expect([presentation.offset_x, presentation.offset_y]).to eq([0.0, 0.0])
    end
  end

  describe ':letterbox' do
    subject(:presentation) { build(:letterbox) }

    it 'takes the largest scale that fits, on both axes equally' do
      presentation.fit(1600, 900)

      # 900/480 = 1.875 is tighter than 1600/640 = 2.5, so it wins.
      expect(presentation.scale_x).to eq(1.875)
      expect(presentation.scale_y).to eq(1.875)
    end

    it 'centres what is left over' do
      presentation.fit(1600, 900)

      expect(presentation.offset_x).to eq(200) # (1600 - 640*1.875) / 2
      expect(presentation.offset_y).to eq(0)   # the tight axis has nothing spare
    end

    it 'fills exactly when the aspect ratios match' do
      presentation.fit(1280, 960)

      expect(presentation.scale_x).to eq(2.0)
      expect([presentation.offset_x, presentation.offset_y]).to eq([0, 0])
    end
  end

  describe ':integer' do
    subject(:presentation) { build(:integer) }

    it 'rounds the fitting scale down to a whole number' do
      # The point of the mode: 2.25 would give some source pixels two screen
      # pixels and others three, and the unevenness crawls as things move.
      presentation.fit(1920, 1080)

      expect(presentation.scale_x).to eq(2.0)
      expect(presentation.scale_y).to eq(2.0)
    end

    it 'centres the border the rounding leaves behind' do
      presentation.fit(1920, 1080)

      expect(presentation.offset_x).to eq(320) # (1920 - 1280) / 2
      expect(presentation.offset_y).to eq(60)  # (1080 - 960) / 2
    end

    it 'drops to 1x when the tighter axis is short of 2x' do
      # 16:9 at 900 or 720 tall is the case worth knowing about: 2x needs 960
      # rows and neither has them, so the whole window falls back to 1x.
      expect(presentation.fit(1600, 900).scale_x).to eq(1.0)
      expect(presentation.fit(1280, 720).scale_x).to eq(1.0)
    end

    it 'agrees with letterbox when the fit is already a whole number' do
      integer = presentation.fit(1280, 960)
      letterbox = build(:letterbox).fit(1280, 960)

      expect(integer.scale_x).to eq(letterbox.scale_x)
      expect(integer.offset_x).to eq(letterbox.offset_x)
    end

    it 'never goes below 1x, so a small window crops instead of blurring' do
      presentation.fit(320, 240)

      expect(presentation.scale_x).to eq(1.0)
    end

    it 'offsets negatively when it crops, keeping the crop centred' do
      # Half the overflow off each edge rather than all of it off the right —
      # so what is lost is the border of the design, not one whole side of it.
      presentation.fit(320, 240)

      expect(presentation.offset_x).to eq(-160)
      expect(presentation.offset_y).to eq(-120)
    end
  end

  describe 'the offsets' do
    it 'are whole pixels' do
      # A half-pixel translate puts every sprite edge between two screen pixels,
      # which with nearest filtering is the shimmer this whole class exists to
      # avoid. 1000 - 640*1 = 360, halved is 180 exactly; 1001 must not give
      # 180.5.
      presentation = build(:integer).fit(1001, 481)

      expect(presentation.offset_x).to be_an(Integer)
      expect(presentation.offset_y).to be_an(Integer)
    end
  end

  describe 'refusals' do
    it 'refuses a mode it does not have' do
      expect { build(:overscan) }
        .to raise_error(ArgumentError, /unknown scale mode :overscan/)
    end

    it 'names the modes it does have, so the fix is in the message' do
      expect { build(:nope) }.to raise_error(ArgumentError, /:disabled.*:integer/)
    end

    it 'refuses a zero or negative size' do
      # Every mode divides by these, so the failure would otherwise be a
      # ZeroDivisionError or an infinite scale much later.
      expect { build(:integer, width: 0) }.to raise_error(ArgumentError, /positive/)
      expect { build(:integer, height: -1) }.to raise_error(ArgumentError, /positive/)
    end
  end

  describe 'changing mode while running' do
    it 'refits against the window it last saw' do
      # The caller changing modes knows which mode it wants and has no reason to
      # also know the window size, so this must not need one passed back in.
      presentation = build(:disabled)
      presentation.fit(1920, 1080)

      presentation.mode = :integer

      expect(presentation.scale_x).to eq(2.0)
      expect([presentation.width, presentation.height]).to eq([640, 480])
    end

    it 'gives the logical size back to the window on the way to :disabled' do
      # The half that is easy to miss: leaving a scaling mode turns a fixed
      # logical size back into the window's own, and anything holding the old
      # one would lay out into a corner.
      presentation = build(:integer)
      presentation.fit(1920, 1080)

      presentation.mode = :disabled

      expect([presentation.width, presentation.height]).to eq([1920, 1080])
      expect(presentation).not_to be_scaled
    end

    it 'reports the mode it was given' do
      presentation = build(:disabled)

      presentation.mode = :letterbox

      expect(presentation.mode).to eq(:letterbox)
    end

    it 'refuses a mode it does not have, without changing the one in force' do
      presentation = build(:integer)
      presentation.fit(1920, 1080)

      expect { presentation.mode = :nope }.to raise_error(ArgumentError, /unknown scale mode/)
      expect(presentation.mode).to eq(:integer)
      expect(presentation.scale_x).to eq(2.0)
    end

    it 'round-trips through every mode and back' do
      # What a settings screen cycling with left/right actually does.
      presentation = build(:disabled)
      presentation.fit(1920, 1080)

      described_class::MODES.each { |mode| presentation.mode = mode }
      presentation.mode = :disabled

      expect([presentation.width, presentation.height]).to eq([1920, 1080])
      expect([presentation.scale_x, presentation.offset_x]).to eq([1.0, 0.0])
    end
  end

  describe 'fitting more than once' do
    it 'recomputes rather than accumulating' do
      # It is mutated on every resize, so a stale field would show up as a
      # scale that only ever grew.
      presentation = build(:integer)
      presentation.fit(1920, 1080)
      presentation.fit(640, 480)

      expect(presentation.scale_x).to eq(1.0)
      expect([presentation.offset_x, presentation.offset_y]).to eq([0, 0])
    end

    it 'returns itself, so a fit can be chained onto construction' do
      presentation = build(:letterbox)

      expect(presentation.fit(800, 600)).to be(presentation)
    end
  end
end
