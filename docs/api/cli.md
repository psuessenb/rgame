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

`rgame new` refuses a name that would not make a Ruby constant, and refuses a
directory that already exists and has anything in it. An existing *empty*
directory is written into.

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

The name is turned into a class name by splitting on underscores and dashes and
capitalising each part, so `tic_tac_toe` and `tic-tac-toe` both give
`TicTacToeGame`.

Two versions are recorded, both taken from whatever generated the project rather
than baked into a template. The `Gemfile` pins the engine loosely
(`gem 'rgame', '~> 0.2'`), and `.ruby-version` records the exact Ruby that ran
`rgame new` — the one interpreter the project is actually known to work on. The
Gemfile points at that file rather than repeating the number:

```ruby
ruby file: '.ruby-version'
```

Every version manager reads `.ruby-version`, and so does Bundler, so the two
cannot drift apart.

Bundler treats it as a **hard, exact** requirement: on any other Ruby,
`bundle install` refuses rather than resolving against it — and `4.0` does not
match `4.0.5`, it matches only `4.0`. To accept a range instead, state the
requirement in the `Gemfile` rather than in `.ruby-version`, which has to stay a
plain version number for version managers to read:

```ruby
ruby '~> 4.0'   # instead of `ruby file: '.ruby-version'`
```

## Why the layout is shaped like this

The generated tree is not a folder convention — it is the engine's own layering,
made the path of least resistance in a new project. Three files carry it.

**`game.rb` is the only file that requires `rgame/game`,** and therefore the only
one that loads SDL and OpenGL. It is the local counterpart of
[`RGame::Game`](game.md): the class that is allowed to know both halves of the
engine, because introducing them is what it is for.

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

The bare `**` forwards every keyword through to `RGame::Game`, so everything it
accepts still works — `players: 2` for split-screen, or `input:` to hand the game
a scripted input backend and drive it with no hardware attached.

**`nodes/` requires `rgame`,** the graphics-free half: `RGame::Util` and
`RGame::Engine`, with no graphics library in the process at all. A node is
*handed* a renderer at draw time and calls it by name; it never stores one and
never learns what class answered.

```ruby
require 'rgame'

class Root < RGame::Engine::Node2D
  GREETING = 'Hello from tictactoe!'

  def on_draw(renderer, _view)
    renderer.text(GREETING, 20, 20)
  end
end
```

Override `on_control(actions)`, `on_update(dt)` and `on_draw(renderer, view)` —
not `control`, `update` or `draw`. The engine does its bookkeeping in the outer
methods and calls these, so there is no `super` to forget. See
[Scene graph](scene_graph.md).

**`spec/spec_helper.rb` requires `rgame` too,** which is what makes the generated
suite headless: no window, no GPU, no clock, and `RGame::Core` an undefined
constant. A spec that reached for it fails loudly rather than quietly opening a
window.

That is also why the generated example uses a plain spy rather than a verified
double — the renderer it stands in for lives on the other side of a line the
suite deliberately does not cross, and the generated `.rubocop.yml` turns
`RSpec/VerifiedDoubles` off with that reason written down:

```ruby
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

Put new game logic under `nodes/` and this holds however large the game gets:
the whole simulation stays testable in milliseconds on a machine with no
display. Put it in `game.rb` and it stops being.

## The generated RuboCop configuration

A stock config — `rubocop-performance` and `rubocop-rspec`, the `Metrics/*`
relaxations a game's `update`/`draw` methods need, and short coordinate names
allowed. The engine's own five custom cops (`Game/DrawInLocalSpace` and
friends) are **not** part of it: they live in the engine's repository rather than
in the gem, and two of them police a layer boundary that only exists inside it.

## Adding to the generator

`rgame new` derives its file list from
`lib/rgame/cli/templates/`, so a new file in a generated project is a new
template and nothing else — there is no manifest to update. Templates are ERB,
and may call `app_name`, `game_class`, `caption` and `rgame_requirement`.

One rule: **no template may be named with a leading dot.** The gemspec packages
`lib/**/*` with `Dir.glob`, which does not match dotfiles, so a template called
`.gitignore` would silently be missing from the installed gem while working
perfectly in a checkout. Templates for dotfiles are stored under a plain name
(`gitignore.tt`) and renamed on the way out through
`RGame::CLI::NewProject::DOTFILES`. `spec/packaging_spec.rb` fails if one ever
appears.
