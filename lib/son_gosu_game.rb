# frozen_string_literal: true

require_relative 'boot'
require 'gosu'
require_relative 'engine'
require_relative 'platform'

class SonGosuGame
  WIDTH = 640
  HEIGHT = 480

  attr_reader :action_mapper, :height, :width, :renderer, :assets

  def initialize(root:, width: WIDTH, height: HEIGHT, caption: 'SonGosu Game',
                 media_root: 'media', action_map: {})
    @width = width
    @height = height
    @action_mapper = Engine::ActionMapper.new(action_map)
    # The game owns the asset manager; the renderer resolves draw assets through it, and
    # nodes reach it via node.root.context.assets — so assets aren't threaded through
    # constructors. Assets are named by their root-relative path.
    @assets = Platform::AssetManager.new(root: media_root)
    @renderer = Platform::GosuRenderer.new(assets: @assets)
    @window = Platform::GameWindow.new(
      width:, height:, caption:, root:, renderer: @renderer, mapper: @action_mapper
    )
    @started = false
  end

  def start
    return if @started

    root = @window.root
    root.context = self
    root.enter_tree # brings the root subtree live: components attach, then on_add
    @window.show
    @started = true
  end
end
