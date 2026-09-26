# frozen_string_literal: true

# Equipment — a character dressed from a column of slots and a grid of clothes,
# and a bag behind a second tab that says what is worn.
#
# Run it:
#
#   ruby examples/equipment/main.rb
#
# The arrow keys (or the d-pad) move through the slots and the clothes. Right
# from a slot crosses into the clothes that fit it, and left from the first
# column crosses back. Enter (or A) on a piece wears it, and on a slot takes its
# piece off. Q and E (or the shoulder buttons) switch between Gear and Bag. It
# exercises:
#   - UI::Tabs — two pages of one screen, and a bar of tabs over them;
#   - UI::FocusGroup — the slots and the clothes, and the one of them that reads
#     input;
#   - UI::Grid — the clothes, a row to a slot, and the bag;
#   - UI::Button — a piece's own button, which draws the piece;
#   - UI::PanelButton's `draw_foreground` — a slot that names what it holds;
#   - renderer.scaled — the character, drawn from `hero.png` five times its size.
#
# ## One outfit, read by everything
#
# An Outfit says which piece each slot wears, and it is the only place that
# says so. The slots, both grids and the character read it on every draw, and
# nothing copies it, so no screen can show a piece the character is not wearing.
#
# Each piece draws itself as shapes, in the character's own sixteen-by-22
# pixels. The character draws the pieces it wears at their places over the
# sprite. A piece's button draws the same piece, scaled and centred in its slot.
# One drawing serves both, so a piece and its button always agree.
#
# An empty slot stays enabled and says so. Taking the last piece off therefore
# leaves focus on the slot, where a disabled button would move it away.
#
# ## What this example does not solve
#
# Choosing a piece in the bag does nothing: the bag shows what is carried, and
# Gear is where it is worn. The bag holds the six pieces and nothing else, and
# a piece has no stats. The character stands still, drawn from one frame.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine` and `Util` inside it are short for
# `RGame::Engine` and `RGame::Util`, and every name the example defines stays off
# the top level. docs/api/README.md says why, under "A game's own module".
module EquipmentExample
  Engine = RGame::Engine
  Util = RGame::Util

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  Color = Util::Color

  # Something to wear: its name, the slot it fits, and the point a button centres
  # on. A subclass draws it, in the pixels of the character's standing frame.
  class Piece
    attr_reader :name, :slot, :centre_x, :centre_y

    def initialize(key, slot:, centre_x:, centre_y:)
      @name = Engine::Text.new(key, scope: 'pieces')
      @slot = slot
      @centre_x = centre_x
      @centre_y = centre_y
    end
  end

  # A wide straw brim with a low crown.
  class StrawHat < Piece
    STRAW = Color.new(232, 200, 112)
    CROWN = Color.new(196, 160, 80)

    def initialize = super('straw_hat', slot: :head, centre_x: 8, centre_y: 2.5)

    def draw(renderer)
      renderer.rect(4, 0, 8, 3, color: CROWN)
      renderer.rect(1, 3, 14, 2, color: STRAW)
    end
  end

  # A tall purple point on a narrow brim.
  class PointedHat < Piece
    CONE = Color.new(120, 72, 168)
    BRIM = Color.new(84, 48, 120)

    def initialize = super('pointed_hat', slot: :head, centre_x: 8, centre_y: 0)

    def draw(renderer)
      renderer.triangle(3, 4, 8, -5, 13, 4, color: CONE)
      renderer.rect(2, 3, 12, 2, color: BRIM)
    end
  end

  # A red cloak that flares towards the knees, with a gold clasp.
  class Cloak < Piece
    CLOTH = Color.new(176, 48, 56)
    CLASP = Color.new(240, 200, 96)

    def initialize = super('cloak', slot: :body, centre_x: 8, centre_y: 16.5)

    def draw(renderer)
      renderer.quad(3, 13, 13, 13, 15, 20, 1, 20, color: CLOTH)
      renderer.circle(8, 14, 1, color: CLASP)
    end
  end

  # A blue tunic with a belt.
  class Tunic < Piece
    CLOTH = Color.new(64, 104, 176)
    BELT = Color.new(96, 64, 40)

    def initialize = super('tunic', slot: :body, centre_x: 8, centre_y: 16)

    def draw(renderer)
      renderer.rect(3, 13, 10, 6, color: CLOTH)
      renderer.rect(3, 17, 10, 1, color: BELT)
    end
  end

  # Oxblood boots up the shin.
  class Boots < Piece
    LEATHER = Color.new(136, 48, 40)

    def initialize = super('boots', slot: :feet, centre_x: 8, centre_y: 20)

    def draw(renderer)
      renderer.rect(4, 18, 3, 4, color: LEATHER)
      renderer.rect(9, 18, 3, 4, color: LEATHER)
    end
  end

  # Thin soles and a strap over each foot.
  class Sandals < Piece
    SOLE = Color.new(208, 176, 128)

    def initialize = super('sandals', slot: :feet, centre_x: 8, centre_y: 21)

    def draw(renderer)
      renderer.rect(4, 21, 3, 1, color: SOLE)
      renderer.rect(9, 21, 3, 1, color: SOLE)
      renderer.rect(5, 20, 1, 1, color: SOLE)
      renderer.rect(10, 20, 1, 1, color: SOLE)
    end
  end

  # Which piece each slot wears. Wearing a piece replaces what its slot held.
  class Outfit
    SLOTS = %i[head body feet].freeze

    def initialize(*pieces)
      @worn = {}
      pieces.each { wear(it) }
    end

    def wear(piece) = @worn[piece.slot] = piece
    def take_off(slot) = @worn.delete(slot)

    # The piece `slot` wears, or nil.
    def on(slot) = @worn[slot]

    def wears?(piece) = @worn[piece.slot].equal?(piece)
  end

  # The character on a panel: the standing frame of `hero.png`, five times its
  # size, with every worn piece drawn over it.
  class Figure < Engine::Node2D
    SHEET = 'hero.json'
    SCALE = 5
    WIDTH = 112
    HEIGHT = 160
    INSET_X = 16
    INSET_Y = 32

    def initialize(outfit:, **)
      super(**)
      @outfit = outfit
    end

    def _draw(renderer, _view)
      renderer.nine_slice(:panel, 0, 0, WIDTH, HEIGHT)
      renderer.translated(INSET_X, INSET_Y) do
        renderer.scaled(SCALE) do
          renderer.sprite(SHEET, 0, 0, 0, 0)
          Outfit::SLOTS.each { |slot| @outfit.on(slot)&.draw(renderer) }
        end
      end
    end
  end

  # A piece in a grid: the piece itself, centred and three times its size, and a
  # dot in the corner while it is worn.
  class PieceButton < Engine::UI::Button
    STYLE = Engine::UI::ShapeStyle.new
    SCALE = 3
    WORN = Color.new(240, 200, 96)

    attr_reader :piece

    def initialize(piece:, outfit:, **)
      super(**)
      @piece = piece
      @outfit = outfit
    end

    def _draw(renderer, _view)
      STYLE.draw(renderer, state, width, height)
      renderer.translated((width / 2.0) - (@piece.centre_x * SCALE), (height / 2.0) - (@piece.centre_y * SCALE)) do
        renderer.scaled(SCALE) { @piece.draw(renderer) }
      end
      renderer.circle(width - 8, 8, 4, color: WORN) if @outfit.wears?(@piece)
    end
  end

  # A slot in the column: its own name, then the name of the piece it wears, or
  # the empty slot's word.
  class SlotButton < Engine::UI::PanelButton
    NAME_X = 16
    WORN_X = 80

    def initialize(slot:, outfit:, **)
      super(label: slot.to_s, **)
      @slot = slot
      @outfit = outfit
      @empty = Engine::Text.new('outfit.empty')
    end

    private

    def draw_foreground(renderer)
      y = label_y(renderer)
      color = current_label_color
      renderer.text(label, NAME_X, y, z: 1, color: color)
      renderer.text(@outfit.on(@slot)&.name || @empty, WORN_X, y, z: 1, color: color)
    end
  end

  # The panel beside the bag. It names the focused piece, and says whether it is
  # worn.
  class PiecePanel < Engine::Node2D
    WIDTH = 236
    HEIGHT = 72

    def initialize(menu:, outfit:, **)
      super(**)
      @menu = menu
      @outfit = outfit
      @worn = Engine::Text.new('outfit.worn')
      @carried = Engine::Text.new('outfit.carried')
    end

    def _draw(renderer, _view)
      renderer.nine_slice(:panel, 0, 0, WIDTH, HEIGHT)
      piece = @menu.focused&.piece
      return unless piece

      renderer.text(piece.name, 16, 14)
      renderer.text(@outfit.wears?(piece) ? @worn : @carried, 16, 40)
    end
  end

  # The tabs, and the two pages under them.
  class Wardrobe < Engine::Node2D
    UI = Engine::UI

    SLOT = 64
    SPACING = 6

    def initialize
      super
      pieces = [StrawHat.new, PointedHat.new, Cloak.new, Tunic.new, Boots.new, Sandals.new]
      @outfit = Outfit.new(pieces[0], pieces[4])
      @help = Engine::Text.new('help.keys')
      tabs = add_node(UI::Tabs.new(x: 16, y: 40, layout: UI::Row.new(item_width: 120, item_height: 28), scope: 'tabs'))
      tabs.add(UI::PanelButton.new(label: 'gear'), gear_page(pieces))
      tabs.add(UI::PanelButton.new(label: 'bag'), bag_page(pieces))
    end

    def _draw(renderer, _view) = renderer.text(@help, 16, 12)

    private

    # The character, the slots, and the clothes two to a row, a row to a slot, so
    # a crossing from a slot lands on a piece that fits it.
    def gear_page(pieces)
      page = Engine::Node2D.new
      page.add_node(Figure.new(outfit: @outfit, x: 16, y: 32))
      group = page.add_node(UI::FocusGroup.new)
      column = UI::Column.new(item_width: 200, item_height: SLOT, spacing: SPACING)
      slots = group.add_node(UI::PanelMenu.new(x: 176, y: 48, layout: column, scope: 'slots'))
      Outfit::SLOTS.each do |slot|
        slots.add(SlotButton.new(slot: slot, outfit: @outfit)).on_activated { @outfit.take_off(slot) }
      end
      grid = UI::Grid.new(columns: 2, item_width: SLOT, item_height: SLOT, spacing: SPACING)
      clothes = group.add_node(UI::PanelMenu.new(x: 424, y: 48, layout: grid))
      pieces.each do |piece|
        clothes.add(PieceButton.new(piece: piece, outfit: @outfit)).on_activated { @outfit.wear(piece) }
      end
      page
    end

    def bag_page(pieces)
      page = Engine::Node2D.new
      grid = UI::Grid.new(columns: 2, item_width: SLOT, item_height: SLOT, spacing: SPACING)
      bag = page.add_node(UI::PanelMenu.new(x: 32, y: 48, layout: grid))
      pieces.each { |piece| bag.add(PieceButton.new(piece: piece, outfit: @outfit)) }
      page.add_node(PiecePanel.new(menu: bag, outfit: @outfit, x: 208, y: 32))
      page
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Wardrobe.new,
      caption: 'Equipment',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES
    )

    # The panels and the slots are nine-slices, each a Symbol naming an element of
    # the UI atlas, so the atlas is registered once.
    game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))

    game.start
  end
end

EquipmentExample.start
