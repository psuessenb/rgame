# frozen_string_literal: true

# The world the shell's stack holds while the game is played: the rooms, a hero
# and a bag for each player, and the listener that spawns them.
#
# ## Two players, two rooms
#
# Scene::Rooms runs every room a player stands in, and draws each into its own
# players' regions. So the pad's hero can walk through the town's gate into the
# garden while the keyboard's hero stays in the town, and each region shows its
# own map. A door moves the hero who touched it. The garden's horn moves every
# hero in `heroes`, from whichever room.
#
# ## What lives here rather than in a room
#
# A room is built anew each time somebody walks into it, so anything that must
# outlast a visit sits above the rooms. Each hero belongs to the world, and so
# does each bag, in a PlayerLayer of its player. A bag open while the other
# hero takes the gate stays open, and its hero stays paused until it closes.
#
# The first hero arrives under the opening fade. A player who joins later
# arrives with no transition, in whichever room the primary player stands in,
# so their region opens onto a room already running.
#
# ## The music
#
# The town claims `music.ogg` at priority 1, and the garden its own song at
# priority 2 when it has one, each while a player stands in it or is on the way
# to it. The claims change as a move is asked for, so the music crossfades to
# the garden's song over the cover and the reveal of the first hero asked into
# the garden, and back as the horn is sounded. With no song in the garden, the
# town's fades out when the town empties and in again when it fills.
#
# The world listens to `Players#on_joined` for as long as it is in the tree,
# and ends that as it leaves.
class World < RGame::Engine::Node2D
  ARRIVAL = RGame::Engine::Scene::Fade.new(cover: 0.5, reveal: 0.5)

  DOORS = RGame::Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)

  MUSIC = 'music.ogg'

  MAPS = [Town::MAP, Garden::MAP].freeze

  attr_reader :rooms, :heroes

  def initialize
    super
    @rooms = add_component(RGame::Engine::Scene::Rooms.new)
    @rooms.define(:town, music: MUSIC, priority: 1) { Town.new }
    @rooms.define(:garden, music: Garden::SONG, priority: 2) { Garden.new }
    @rooms.transition = DOORS
    @heroes = []
  end

  # Loads both maps before anyone walks, so a door parses nothing, and spawns a
  # hero for each player already playing and each who joins.
  def _enter_tree
    MAPS.each { root.context.assets.tilemap(it) }
    @players = system!(RGame::Engine::Players)
    @players.each_active { |player| spawn(player) }
    @joining = @players.on_joined { |player| spawn(player) }
  end

  def _exit_tree = @players.disconnect_joined(@joining)

  private

  def spawn(player)
    hero = Hero.new(camera: player.camera)
    hero.input_owner = player
    @heroes << hero
    add_node(RGame::Engine::PlayerLayer.new(player: player)).add_node(Bag.new(hero: hero, x: 8, y: 8))
    room = @rooms.room_of(@players.primary)
    @rooms.move(hero, to: room ? room.name : :town, entrance: 'start', transition: room ? nil : ARRIVAL)
  end
end
