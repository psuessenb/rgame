# Current state

Everything below was read at `f4617da`.

## `Engine::I18n` today

`lib/rgame/engine/i18n.rb`, 97 lines. A global module with `load(locale, hash)`,
`load_file(locale, path)`, `locale=`, `default=`, `available`, `reset`,
`generation`, and `t(key, count: nil, **vars)`.

What it gets right, and what survives:

- **A global, reachable from a constructor.** Kept (decision 1).
- **`generation` as a cheap "has anything changed" signal.** Kept, and widened.
  Today it moves only on a locale *switch*, so a label resolved before a table
  loads would cache the raw key for ever. It must move on load too.
- **Fallback to a default locale, and `%{var}`.** Kept.

What blocks the goal:

| # | Problem | Evidence |
|---|---|---|
| C1 | **`t` allocates 5–12 objects per call** *(measured)*: `key.to_s.split('.')`, a Symbol per segment, the `**vars` Hash, `vars.merge(count:)`, and `String#%` | `i18n.rb:60-85` |
| C2 | **Pluralization is one/other for every language.** Russian, Polish, Czech and Arabic are wrong. | `i18n.rb:71-75` |
| C3 | **`load_file(locale, path)` reads a file itself** and expects one locale per file with no locale key, which is not Rails' format | `i18n.rb:37-39` |
| C4 | **A missing key silently returns the key.** Nothing can make it loud. | `i18n.rb:63` |
| C5 | **Its header compares it to `EventDispatcher`**, which went with Gosu | `i18n.rb:10` |
| C6 | **No caller anywhere**, so nothing constrains a rewrite *(measured)* | grep |

## Text that does not know the language exists

| # | Problem | Evidence |
|---|---|---|
| C7 | **`CachedLabel` keys on one value.** A label depending on a count *and* the language cannot express both, and `[count, I18n.generation]` allocates the Array it exists to avoid. This is the known issue. | `cached_label.rb`, `basic-examples.md` #23 |
| C8 | **`UI::OptionButton` builds and freezes `@captions` in its constructor and memoizes `@column_width` for ever.** A language switch leaves both stale. This problem was not recorded anywhere. | `option_button.rb:44-46, 116` |
| C9 | **`UI::Button#label` is a plain String** (`attr_accessor :label`), drawn as is by `TextButton` and `OptionButton` and measured by `text_width` on every draw | `button.rb:79-89`, `text_button.rb` |
| C10 | **`rgame new` generates `GREETING = 'Hello from …!'`** and a spec asserting the literal. The first file a new user reads teaches hardcoding. | `cli/templates/nodes/root.rb.tt`, `spec/nodes/root_spec.rb.tt` |
| C11 | **CLAUDE.md's house rule "A label built from a changing value" teaches `"Score: #{score}"`**, and so do `docs/api/text.md` and `toolbox.md` | CLAUDE.md, docs |
| C12 | **Every example draws literals.** `menu_navigation`'s option rows carry `display: ->(on) { on ? 'on' : 'off' }` and `"#{percent}%"`. | `examples/menu_navigation/main.rb:103-113` |

## Loading

| # | Fact | Evidence |
|---|---|---|
| C13 | **The asset manager is Core, so `Engine` cannot use it.** A loader that turns a file into an engine object is installed by the glue, the way `:tilemap` is. | `game.rb#install_asset_loaders` |
| C14 | **A leaf loader receives a resolved absolute path and opens it itself.** `read` is `File.read(path)`. There is no listing method: nothing today needs to ask "which files are there". | `asset_manager.rb#default_loaders` |
| C15 | **A root node is built before `Game.new` runs** (`Game.new(root: Root.new)`), so any `Text` built in a node's `initialize` exists before a table can load. Resolution has to be lazy. | `game.rb`, `cli/templates/game.rb.tt` |
| C16 | **Every example shares `examples/assets/` as its media root** | `examples/*/main.rb` |

### What would stand in the way of a packed asset format

The user asked about this for a possible Steam release (decision 5). This design
adds nothing to the list. Listed so a later plan need not re-derive it:

- `ext/rgame_core/graphics/image.c:68` and `text/font_atlas.c:150` `fopen` a
  path. A pack needs `stbi_load_from_memory` and a font read from a buffer.
- `ext/rgame_core/audio/audio.c:338, 376, 499` call `ma_decoder_init_file` and
  `ma_sound_init_from_file`. A pack needs miniaudio's VFS
  (`ma_resource_manager` with a custom `ma_vfs`), which `vorbis_decoder.c`'s
  `onInit` entry point already reads through.
- `AssetManager#resolve` is `File.expand_path`. That is the Ruby seam, and it is
  already the only one.

## What already resembles this

The three piles CLAUDE.md asks for.

### Reuse it

| Existing | Used for |
|---|---|
| `AssetManager#add_loader`, `#read` | the `:locale` loader and its bytes |
| `Game#install_asset_loaders` | where that loader is installed, beside `:tilemap` |
| `spec/support/allocate_nothing_matcher.rb` | constraint 2 |
| `Util::SaveFile` | remembering a player's language choice, in the example |
| `UI::Menu`, `UI::OptionButton` | the example's language switch |
| `Signal` | not used by `Text`, by decision (it polls) |

### Extend or generalize it

- **`CachedLabel` → `Text`.** *The same question about a different input.*
  Both answer "what string does this node draw, rebuilt only when its inputs
  change". A translation adds one input, the language. Two objects would be a
  parallel vocabulary: a formatted label and a translated label, each caching,
  each with its own change rule. The first caller wanting both, a translated
  score, would have had to pick one and lose the other. That is issue C7.
- **`AssetManager` grows `glob`.** It already owns "where does this path point".
  "Which paths exist under here" is the same question about a set, and putting
  it anywhere else would open a second file-access seam (decision 5).
- **`UI::Button#label` becomes a `Text`.** It already answers "what text does
  this widget show". Only the source changes.
- **`Menu` grows `scope:`.** A menu already configures the buttons it holds as
  they are added (layout, focus).
- **`I18n.generation` moves on load as well as on switch.** It already answers
  "has what `t` returns changed".

### Genuinely new

- **CLDR plural rules.** No existing code maps numbers to categories.
- **Locale identifiers and their fallback chain** (`de-AT` → `de` → default).
- **`App#preferred_locales`**, a C shim over `SDL_GetPreferredLocales`. Nothing
  in Core reads OS preferences today; the nearest, the save directory helper in
  `Util::SaveFile`, reads environment variables per OS. Both answer "what does
  this OS say about the user". But `SaveFile`'s answer is a path that needs no
  SDL, and SDL already solves the locale question on all three platforms, so
  sharing would mean reimplementing SDL's per-platform code in Ruby.
