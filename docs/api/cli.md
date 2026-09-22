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

`rgame new` accepts a name made of letters, digits, underscores and dashes,
starting with a letter, and refuses anything else. It also refuses a
path that exists and is not a directory, and a directory that holds anything. It
writes into an existing *empty* directory.

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
│   └── locales/
│       └── en.yml    the English translation table
├── nodes/
│   └── root.rb       class Root < RGame::Engine::Node2D
└── spec/
    ├── spec_helper.rb
    ├── locales_spec.rb
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
(`gem 'rgame', '~> 0.3'` from rgame 0.3.0). `.ruby-version` records the exact Ruby that ran
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
  def initialize
    super
    @greeting = RGame::Engine::Text.new('root.greeting')
  end

  def _draw(renderer, _view)
    renderer.text(@greeting, 20, 20)
  end
end
```

Override `_control(actions)`, `_update(dt)` and `_draw(renderer, view)`,
not `control`, `update` or `draw`. The engine does its bookkeeping in the outer
methods and calls these hooks, so there is no `super` to forget. See
[Scene graph](scene_graph.md).

**`spec/spec_helper.rb` also requires `rgame`,** and `.rspec` loads it before
every spec. It requires every file under `nodes/` too. The generated suite
therefore runs headless. It has no window, no GPU and no clock, and `RGame::Core` is undefined.
A spec that names Core fails loudly instead of opening a window.

For the same reason, the generated spec uses a plain spy, not a verified double.
The renderer it replaces lives on the far side of a line the suite does not
cross. The generated `.rubocop.yml` turns `RSpec/VerifiedDoubles` off and writes
down that reason:

```ruby
RSpec.describe Root do
  describe '#_draw' do
    it 'draws its greeting from the English table' do
      renderer = spy('renderer')

      described_class.new._draw(renderer, nil)

      expect(renderer).to have_received(:text).with('Hello from tictactoe!', 20, 20)
    end
  end
end
```

The node passes its `Text` to `text`, so the spy records the `Text`. It still
matches the String, because a `Text` is `==` to the String it reads. See
[`Text`](toolbox.md#text--the-string-a-node-draws).

Put new game logic under `nodes/`, and the whole simulation stays testable in
milliseconds with no display, however large the game grows. Logic in `game.rb`
loses that.

## Text comes from a translation table

**The generated root node draws a key, not a String.** `assets/locales/en.yml`
holds the text, in Rails' format:

```yaml
en:
  root:
    greeting: "Hello from tictactoe!"
```

`RGame::Game` loads every `.yml` under `assets/locales/` and picks the player's
language from their operating system. See
[Game](game.md#translations-and-the-players-language). The node builds an
[`Engine::Text`](toolbox.md#text--the-string-a-node-draws) once and draws it
every frame. To add a language, add a file such as `de.yml` with the same keys.
[Localization](localization.md) covers the format, plurals and the fallback.

**The generated spec helper loads the same tables before every example.** It
reads the files once, then calls `I18n.reset`, loads each table and sets
`I18n.missing = :raise`. Every example therefore starts in the default locale
with the game's own tables, whatever the example before it loaded. A spec that
draws a key no table has fails with `I18n::MissingKey`.

The spec helper names `assets/locales` itself, because `spec/` cannot load
`game.rb`. Move the directory in one place and every spec that draws a key
fails. Reloading costs about 8 µs per key per example.

**`spec/locales_spec.rb` fails while a language lacks a key.** It checks that
the default locale has a table, and that `I18n.missing_keys` is empty for every
loaded locale. Its failure names each locale and its missing keys, such as
`{de: ["root.greeting"]}`. In the game itself, a missing key falls back to the
default locale's text, and a key no table has shows as itself.

## The generated RuboCop configuration

The generator loads `rubocop-performance`, `rubocop-rspec` and rgame's own cops,
relaxes the `Metrics/*` cops for a game's long `update` and `draw` methods, and
allows short coordinate names. `RSpec/SpecFilePathFormat` skips
`spec/locales_spec.rb`, which describes `I18n` but checks the tables rather than a
source file.

**The gem ships its cops as a RuboCop plugin.** The generated `.rubocop.yml`
loads it by path and class:

```yaml
plugins:
  - rgame/rubocop:
      plugin_class_name: RuboCop::Game::Plugin
```

The plain form, `- rgame`, would make RuboCop require the whole engine just to
lint. An existing project gets the cops by adding those three lines.

| Cop | Refuses | Where |
|---|---|---|
| `Game/NoInterpolationInHotPath` | string interpolation in a per-frame method | everywhere but `spec/` |
| `Game/NoNeedlessAllocation` | a throwaway Array or Range literal on a per-frame path | everywhere but `spec/` |
| `Game/DrawInLocalSpace` | a node's draw method reading its own `x`, `y` or `world_x` | everywhere |
| `Game/NoLiteralText` | a String literal passed to `text`, `text_width` or `text_lines` | everywhere |
| `Game/NoCoreInEngineLayer` | naming `RGame::Core`, or requiring `rgame/core` or `rgame/game` | `nodes/` and `spec/` |

A per-frame method is `update`, `control`, `draw`, `_update`, `_control` or
`_draw`, or any method with a `# hot-path` comment on the line above its
`def`. For a label that changes, the answer to the first cop is an
[`Engine::Text`](toolbox.md#text--the-string-a-node-draws).

`Game/NoCoreInEngineLayer` guards the headless line the layout above draws. A
spec that names `RGame::Core` already fails when it runs, but the cop also
catches a branch no spec reaches. A bare `Core` counts only inside
`module RGame`, so a game's own `Core` module passes.

`Game/NoEngineInCoreLayer` ships too, switched off. It guards the engine's own
repository, and a game has no layer for it to guard.

## Adding to the generator

`rgame new` derives its file list from `lib/rgame/cli/templates/`. A new file in
a generated project needs a new template and nothing else; there is no manifest.
The generator writes only files, so it creates a directory only by writing a
template into it.
Templates are ERB and may call `app_name`, `game_class`, `caption`,
`ruby_version` and `rgame_requirement`.

**No template may have a name starting with a dot.** The gemspec packages
`lib/**/*` with `Dir.glob`, which skips dotfiles. A template called `.gitignore`
would work in a checkout but be missing from the installed gem. Dotfile
templates therefore use a plain name (`gitignore.tt`).
`RGame::CLI::NewProject::DOTFILES` renames them on the way out.
`spec/packaging_spec.rb` fails if a dotfile template appears.
