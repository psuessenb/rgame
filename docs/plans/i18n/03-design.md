# Design

Sketches, not final signatures. [04-roadmap.md](04-roadmap.md) says which step
builds each part, and each step's landed note records what came out
differently.

## What a game author writes

```yaml
# assets/locales/en.yml
en:
  title_menu:
    play: Play
    quit: Quit
  hud:
    score: "Score: %{score}"
    apples:
      zero: No apples
      one: "%{count} apple"
      other: "%{count} apples"
```

```yaml
# assets/locales/de.yml
de:
  title_menu:
    play: Spielen
    quit: Beenden
  hud:
    score: "Punkte: %{score}"
    apples:
      one: "%{count} Apfel"
      other: "%{count} Äpfel"
```

```ruby
class Hud < RGame::Engine::Node2D
  def initialize
    super
    @score  = RGame::Engine::Text.new('hud.score', :score)
    @apples = RGame::Engine::Text.new('hud.apples', :count)
  end

  def on_draw(renderer, _view)
    renderer.text(@score.with(score: @points), 12, 10)
    renderer.text(@apples.with(count: @apples_held), 12, 30)
  end
end

menu = RGame::Engine::UI::Menu.new(layout: ..., scope: 'title_menu')
menu.add(RGame::Engine::UI::PanelButton.new(label: 'play')).on_activated { start }
menu.add(RGame::Engine::UI::PanelButton.new(label: 'quit')).on_activated { close }

RGame::Engine::I18n.locale = :de      # every Text and every button follows
```

A game writes no loading code and no locale detection. `RGame::Game` does both.

## `Engine::I18n`: the tables

```ruby
module RGame::Engine::I18n
  class << self
    def load(yaml, source: nil)   # Rails format; merges deeply into what is loaded
    def load_hash(hash)           # { en: { ... } }, for specs and generated data
    def available                 # => [:en, :de, :'de-AT']
    def default / default=        # the last link of every chain; starts :en
    def locale / locale=          # normalizes; unknown locales are allowed (see below)
    def chain                     # => [:'de-AT', :de, :en], rebuilt on switch
    def generation                # moves on every load and every switch
    def missing / missing=        # :key (default), :raise, or a callable(key, locale)
    def plural_rule(language, &rule)
    def choose(preferred)         # => first of `preferred` whose chain meets a table, else default
    def missing_keys(locale)      # => keys the default has and `locale`'s chain lacks
    def t(key, scope: nil, **vars) # convenience for code off the frame path; allocates
    def reset
  end
end
```

**Compiled at load.** `load` parses with `YAML.safe_load(yaml, aliases: true)`,
flattens nested keys into one frozen Hash per locale keyed by the full dotted
String (`'hud.apples'`), and compiles each value:

- a String becomes a `Template`: a frozen Array alternating literal Strings and
  variable Symbols, plus its frozen list of variable names. `%%{` is a literal
  `%{`.
- a Hash whose keys are all CLDR categories (`zero one two few many other`)
  becomes a `Plural` of Templates. Any other Hash is a nesting level.

Both are internal classes under `I18n`. Resolving is one Hash lookup per link of
the chain. Rendering appends parts into a new String, and happens only when a
`Text` has something to rebuild.

**Locale identifiers.** `normalize` maps `de_AT`, `de-at` and `'de-AT'` to
`:'de-AT'`, and `DE` to `:de`. The chain of `:'de-AT'` is `[:'de-AT', :de,
default]`, deduplicated. Switching to a locale with no table is allowed and
resolves through its chain, so `locale = :'de-CH'` shows German when only `de`
exists.

**Plural rules** are integer rules per language, looked up by the *language
that supplied the text*, not the current locale. German text reached through a
fallback from `pl` pluralizes as German. An explicit `zero:` wins for 0 in
every language. `count` that is not an Integer uses `other` unless a rule says
otherwise. The built-in table covers the languages in decision 6.

**Missing keys.** A key is missing when no link of the chain has it. The policy:

| `missing` | Effect |
|---|---|
| `:key` (default) | the key itself is shown |
| `:raise` | `I18n::MissingKey` naming the key and the chain |
| a callable | called with the key and chain; its return value is shown |

The same policy applies to a `Text` whose declared variables do not match the
template's: an undeclared `%{x}` in the table, or a declared name the table does
not use. A mismatch is a bug in either the table or the code, and `:raise` is
what finds it in specs.

**Why `generation` moves on load.** A `Text` resolved before a table arrives
caches the missing-key answer (fact C15). With load bumping the generation, the
next read re-resolves.

## `Engine::Text`: the thing a node draws

```ruby
class RGame::Engine::Text
  def initialize(key, *names, scope: nil)
  def self.literal(string)                  # never translated; same interface
  def self.computed(*names, &block)         # block receives the keywords, may call I18n.t
  def with(**)                              # generated per name set, see below
  def to_s                                  # a Text with no names
  attr_reader :key
  def scope=(scope)                         # set by a Menu as a button is added
end
```

**`with` is a real method with a declared signature.** `Text.new('hud.where',
:name, :level)` gets `with(name:, level:)`. It comes from a module generated once
per name list, cached by that list and `extend`ed onto the instance, so a
thousand score labels share one generated method. The body compares each
keyword against the ivar it was last called with, and `I18n.generation` against
the last generation seen. If nothing differs it returns the cached String:
zero objects. That was measured for a method generated onto a singleton class;
step 1 re-measures it for the `extend`ed module. Otherwise it re-renders. A missing or
unknown keyword is Ruby's `ArgumentError`, raised on the first frame.

**`count` is not special to `Text`.** It is special to a `Plural` entry. A
`Text` whose key resolves to a `Plural` needs a `:count` among its names, and
the missing-key policy reports one that lacks it.

**`computed`** is `CachedLabel`'s block form. Its block runs when a keyword or
the generation changes, so a block calling `I18n.t` inside follows the language
too:

```ruby
@clock = RGame::Engine::Text.computed(:seconds) { |seconds:| format_clock(seconds) }
```

**`literal`** answers `with` and `to_s` with its string, and `computed` answers
them the same way. Widgets therefore never ask what kind of `Text` they hold.

## Loading, in `RGame::Game`

```ruby
RGame::Game.new(root: ..., locales: 'locales')   # the default; relative to media_root
```

In `initialize`, after `install_asset_loaders`:

```ruby
assets.add_loader(:locale) { |path| RGame::Engine::I18n.load(File.read(path), source: path) }
assets.glob(File.join(locales, '**', '*.yml')).each { |path| assets.locale(path) }
RGame::Engine::I18n.locale = RGame::Engine::I18n.choose(preferred_locales)
```

The `:locale` loader reads the path it is handed, exactly as every other leaf
loader does. A future pack format changes how *all* leaves read, in one place,
rather than locale files differently. Loading in `initialize` rather than
`start` means a game can override the choice between `Game.new` and `start`,
which is where a saved language goes:

```ruby
game = MyGame.new
RGame::Engine::I18n.locale = settings[:language] if settings[:language]
game.start
```

**`AssetManager#glob(pattern)`** returns paths relative to the root, sorted, so
load order and therefore merge order is deterministic on every platform. A
missing directory is an empty list, not an error. A game with no locales gets no
tables and every key shows as itself.

**`App#preferred_locales`** returns `['de-AT', 'en']`: SDL's list, joined with
a hyphen when a country is present, in preference order, or `[]` when SDL has
nothing. It is a thin shim with one C function in `core.h`, whose pure half
(choosing among them) is `I18n.choose`, specced headless.

## UI widgets

- **`Button#label`** holds a `Text`. `label: 'play'` builds
  `Text.new('play')`; `label: some_text` uses it as is. The drawn string is
  `label.to_s`, which is free when unchanged.
- **`Menu.new(scope:)`** sets `scope` on each button's `Text` as it is added,
  unless that `Text` already has one. A scope written on a button wins.
- **`OptionButton`** drops its constructor-built `@captions` and memoized
  `@column_width`. Each caption is a `Text`, and the column width is re-measured
  when `I18n.generation` moves. `display:` returns a key or a `Text`. Its
  default for Symbol values is open question 2.

## Specs

- **The engine's `spec/spec_helper.rb`** sets `I18n.missing = :raise` and calls
  `I18n.reset` around every example. Neither is a rule a spec author has to
  remember.
- **A generated project's `spec_helper.rb`** loads `assets/locales/**/*.yml`
  with `File.read` into `I18n.load`, sets `:raise`, and resets the locale around
  each example.
- **A generated `spec/locales_spec.rb`** asserts `I18n.missing_keys(locale)` is
  empty for every available locale. A key added to `en.yml` and not to `de.yml`
  fails `rake`.

## Docs

**A new page, `docs/api/localization.md`,** replaces `toolbox.md`'s I18n
section: the YAML format, `Text`, plurals, variables, scopes, the missing-key
policy, loading, language detection, and a saved language choice. Linked from
`docs/api/README.md` and `components.md`'s table. `text.md` and `toolbox.md`'s
`CachedLabel` section become `Text`, and the house rule in CLAUDE.md follows.
