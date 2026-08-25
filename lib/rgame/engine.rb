# frozen_string_literal: true

# RGame::Engine — the scene graph a game is written against: nodes, components,
# signals, scenes, collision, tile maps, pathing, pooling.
#
# Pure Ruby, and it links nothing. It may hold `RGame::Util` values but may not
# name `RGame::Core` at all, reaching the platform only through objects handed
# to it — a `renderer` passed into `draw`, an audio server behind
# `AudioDirector`. See CLAUDE.md, "The three layers, and who may talk to whom".
#
# That is what lets the whole layer be specified with no window, no GPU and no
# clock: `spec/` drives `update(dt)` directly and can run a simulated hour in
# milliseconds.
#
# Loaded by `require "rgame"` along with Util, since between them they are
# everything that runs without a window. Requirable on its own too — hence the
# `util` require below rather than relying on `rgame.rb` to have got there
# first: `TileMap` holds a `Util::Tensor`, which is exactly the dependency the
# three-layer rule allows and this file therefore has to declare.
require_relative 'util'

require_relative 'engine/culling'
require_relative 'engine/matrix'
require_relative 'engine/signal'
require_relative 'engine/node2d'
require_relative 'engine/component'
require_relative 'engine/animation_set'
require_relative 'engine/animator'
require_relative 'engine/camera'
require_relative 'engine/layout'
require_relative 'engine/view'
require_relative 'engine/world_view'
require_relative 'engine/player_layer'
require_relative 'engine/ui/menu_item'
require_relative 'engine/ui/menu'
require_relative 'engine/path'
require_relative 'engine/timer'
require_relative 'engine/tileset'
require_relative 'engine/tile_map'
require_relative 'engine/tile_collision'
require_relative 'engine/collision_box'
require_relative 'engine/collision_system'
require_relative 'engine/circle_collider'
require_relative 'engine/spatial_hash'
require_relative 'engine/pool'
require_relative 'engine/resettable'
require_relative 'engine/audio_bus'
require_relative 'engine/audio_director'
require_relative 'engine/i18n'
require_relative 'engine/cached_label'
require_relative 'engine/debug_overlay'
require_relative 'engine/body'
require_relative 'engine/actor'
require_relative 'engine/input/actions'
require_relative 'engine/input/input_map'
require_relative 'engine/input/action_mapper'
require_relative 'engine/input/player_controller'
require_relative 'engine/player'
require_relative 'engine/players'
require_relative 'engine/viewports'
require_relative 'engine/scene/scene_stack'
require_relative 'engine/components/velocity'
require_relative 'engine/components/pool'
require_relative 'engine/components/path_follow'
require_relative 'engine/components/timer'
require_relative 'engine/components/screen_wrap'
require_relative 'engine/components/despawn_offscreen'
require_relative 'engine/components/circle_collider'
require_relative 'engine/components/collision_world'
require_relative 'engine/components/targeting'
require_relative 'engine/components/sprite'
require_relative 'engine/components/thrust_controller'
require_relative 'engine/components/action_trigger'
require_relative 'engine/components/tile_world'
require_relative 'engine/components/character_body'
require_relative 'engine/components/player_controller'
require_relative 'engine/components/wander_controller'
require_relative 'engine/components/animated_sprite'
require_relative 'engine/components/camera_follow'
require_relative 'engine/tile_map_layer'
