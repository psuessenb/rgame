# The `rgame` command

Installing the gem puts one command on your PATH.

```
gem install rgame
rgame new tictactoe
```

| Command | Does |
|---|---|
| `rgame new NAME` | Creates the directory `NAME` and writes a runnable project into it |
| `rgame version` | Prints the installed engine version |
| `rgame help` | Prints usage |

`rgame new` refuses a name that cannot become a Ruby constant. It also refuses a
directory that exists and holds anything. It writes into an existing *empty*
directory.

## What `rgame new tictactoe` writes

```
tictactoe/
├── Gemfile           rgame, plus rspec and rubocop for development
├── Rakefile          rake spec, rake rubocop, rake
├── README.md
├── .ruby-version     the Ruby that ran `rgame new`
├── .gitignore  .rspec  .rubocop.yml
├── main.rb           boots the game and nothing else
├── game.rb           class TictactoeGame < RGame::Game
├── assets/           the game's media_root
├── nodes/
│   └── root.rb       class Root < RGame::Engine::Node2D
└── spec/
    ├── spec_helper.rb
    └── nodes/
        └── root_spec.rb
```

Then:

```
cd tictactoe
bundle install
bundle exec rspec     # passes
bundle exec rubocop   # green
ruby main.rb          # a window saying "Hello from tictactoe!"
```

The generator builds the class name from the project name. It splits on
underscores and dashes and capitalises each part. `tic_tac_toe` and
`tic-tac-toe` both give `TicTacToeGame`.

The project records two versions, both taken from the running generator rather
than from a template. The `Gemfile` pins the engine loosely
(`gem 'rgame', '~> 0.2'`). `.ruby-version` records the exact Ruby that ran
`rgame new`, the one interpreter the project is known to work on. The Gemfile
reads that file instead of repeating the number:

```ruby
ruby file: '.ruby-version'
```

Version managers and Bundler both read `.ruby-version`, so the two cannot drift
apart.

**Bundler treats that line as an exact requirement.** On any other Ruby,
`bundle install` refuses to run. `4.0` does not match `4.0.5`; it matches only
`4.0`. To accept a range, state it in the `Gemfile`. `.ruby-version` must stay a
plain version number, because version managers read it:

```ruby
ruby '~> 4.0'   # instead of `ruby file: '.ruby-version'`
```

## Why the layout looks like this

**The generated tree follows the engine's own layering.** The layout makes the
right split the easy one in a new project. Three files carry it.

**`game.rb` is the only file that requires `rgame/game`,** so it is the only one
that loads SDL and OpenGL. It is the project's counterpart of
[`RGame::Game`](game.md): the one class allowed to know both halves of the
engine.

```ruby
require 'rgame/game'
require_relative 'nodes/root'

class TictactoeGame < RGame::Game
  WIDTH = 640
  HEIGHT = 480

  def initialize(**)
    super(root: Root.new,
          caption: 'Tictactoe',
          width: WIDTH,
          height: HEIGHT,
          media_root: File.join(__dir__, 'assets'),
          **)
  end
end
```

The bare `**` forwards every keyword to `RGame::Game`, so all its options still
work. Pass `players: 2` for split-screen. Pass `input:` to drive the game from a
scripted input backend with no hardware attached.

**`nodes/` requires `rgame`,** the graphics-free half. That loads `RGame::Util`
and `RGame::Engine`, and no graphics library. A node receives a renderer at draw
time and calls its methods by name. It never stores the renderer and never
learns its class.

```ruby
require 'rgame'

class Root < RGame::Engine::Node2D
  GREETING = 'Hello from tictactoe!'

  def on_draw(renderer, _view)
    renderer.text(GREETING, 20, 20)
  end
end
```

Override `on_control(actions)`, `on_update(dt)` and `on_draw(renderer, view)`,
not `control`, `update` or `draw`. The engine does its bookkeeping in the outer
methods and calls these hooks, so there is no `super` to forget. See
[Scene graph](scene_graph.md).

**`spec/spec_helper.rb` also requires `rgame`,** so the generated suite runs
headless. It has no window, no GPU and no clock, and `RGame::Core` is undefined.
A spec that names Core fails loudly instead of opening a window.

For the same reason, the generated spec uses a plain spy, not a verified double.
The renderer it replaces lives on the far side of a line the suite does not
cross. The generated `.rubocop.yml` turns `RSpec/VerifiedDoubles` off and writes
down that reason:

```ruby
require 'spec_helper'

RSpec.describe Root do
  describe '#on_draw' do
    it 'draws its greeting' do
      renderer = spy('renderer')

      described_class.new.on_draw(renderer, nil)

      expect(renderer).to have_received(:text).with(Root::GREETING, 20, 20)
    end
  end
end
```

Put new game logic under `nodes/`, and the whole simulation stays testable in
milliseconds with no display, however large the game grows. Logic in `game.rb`
loses that.

## The generated RuboCop configuration

The generator writes a stock configuration. It loads `rubocop-performance` and
`rubocop-rspec`, relaxes the `Metrics/*` cops for a game's long `update` and
`draw` methods, and allows short coordinate names. It does **not** include the
engine's five custom cops, such as `Game/DrawInLocalSpace`. Those live in the
engine's repository, not in the gem, and two of them guard a layer boundary that
exists only inside the engine.

## Adding to the generator

`rgame new` derives its file list from `lib/rgame/cli/templates/`. A new file in
a generated project needs a new template and nothing else; there is no manifest.
Templates are ERB and may call `app_name`, `game_class`, `caption`,
`ruby_version` and `rgame_requirement`.

**No template may have a name starting with a dot.** The gemspec packages
`lib/**/*` with `Dir.glob`, which skips dotfiles. A template called `.gitignore`
would work in a checkout but be missing from the installed gem. Dotfile
templates therefore use a plain name (`gitignore.tt`).
`RGame::CLI::NewProject::DOTFILES` renames them on the way out.
`spec/packaging_spec.rb` fails if a dotfile template appears.
