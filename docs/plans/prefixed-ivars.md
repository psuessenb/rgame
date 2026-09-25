# Prefixed ivars for the classes a game subclasses

**Status: planned.** Three steps, each one branch and one pull request. All
three are detailed; the plan is small enough that nothing waits on a re-plan.

## Verdict

**Every ivar of a `Node2D` or `Component` descendant in `RGame::Engine` starts
with `rgame_`.** A game then names its own ivars freely: no engine ivar can
share a name it would pick. `rgame_` already means "the base class's own; a
subclass leaves it alone" for methods, so ivars take the same prefix rather
than a new one.

Two guards hold the rule without anyone remembering it:

- **A spec on the engine side.** It asks Ruby for every descendant, parses the
  methods each one defines with Prism, and fails on an ivar without the prefix.
- **A house cop on the game side**, `Game/NoEngineIvar`. It ships in the
  RuboCop plugin, and flags an `@rgame_` ivar in a game's code.

Public readers keep their names and their speed. A class macro, `sealed_reader`
and its siblings, stores `opacity` in `@rgame_opacity` and aliases a private
`attr_reader`. The alias runs as fast as a plain `attr_reader`.

## Goal

A game names an ivar in a `Node2D` or `Component` subclass without checking a
table of taken names first. Today the write-example skill keeps that table, and
three collisions have shipped anyway:

| Ivar | What happened |
|---|---|
| `@player` | The input system was handed a `Node2D`. The comment above `Node2D#input_owner` records it |
| `@paused` | `examples/music` paused its scene by keeping "is the music paused" there. The write-example skill records it |
| `@footing` | `examples/pits` lost its `Footing` to y-sort's sorting collider on the first draw. Step 2 of top-down platforming renamed the engine's ivar |

Each one failed silently, far from its cause. Renaming the engine's ivar each
time fixes one name and leaves the rest.

## Hard constraints

1. **The public API keeps its names.** `node.opacity`, `node.width = 16` and
   every other reader and writer stay as they are. Only ivars change.
2. **A per-frame path allocates nothing, and gets no slower.** A reader that
   `Node2D`'s traversal calls on another node, such as `one.z` in the y-sort,
   keeps `attr_reader` speed. `rake drive:allocations` decides the first half.
3. **The engine layer may not name `RGame::Core`.** Nothing here reaches it.
4. **A game written before the sweep runs unchanged**, unless it reads or
   writes an engine ivar. Such a game is the bug this plan removes, and step 1
   fixes the three this repository has.

## Decisions already taken

Settled in conversation. They are not reopened inside this plan.

1. **Reuse `rgame_`.** `_` means a hook, which a game overrides, and that is
   the opposite of "leave it alone". A new prefix would give one idea two
   names.
2. **All descendants, not only the two base classes.** Games subclass
   `Scene::Room`, `UI::Button`, `UI::PanelButton`, `UI::DialogueBox` and
   `ScreenFade` too, and a rule covering "the ones people subclass" would need
   a list to remember.
3. **A guard on each side**: one keeps the engine prefixed, the other keeps a
   game off the prefix. See "Considered and rejected" for why the engine side
   is a spec rather than a cop.

## Open questions

1. **Should the method seal cover all descendants too?** `SealedPrivates`
   seals the private `rgame_` methods of `Node2D` and `Component` only. After
   this plan the ivar rule is wider than the method rule. *Blocks nothing. Worth
   deciding once a collision on a descendant's private method has happened.*

## What was measured before planning

At `11b00ae`, on Ruby 4.0.5 without YJIT. The timings come from a scratch
script, 20 million calls each.

| What | Result |
|---|---|
| `rake spec` | 4105 examples, 0 failures |
| Descendants of `Node2D` or `Component` under `RGame::Engine` | 66: 23 nodes, 43 components |
| Engine modules mixed into them | 3: `Components::Collider`, `Components::WorldBounds`, `Culling` |
| Files defining them | 65. Five also hold a class that is neither: `particles.rb`, `rooms.rb`, `tile_map_layer.rb`, `dialogue_box.rb`, `tabs.rb` |
| Ivar names in those files | 313 distinct, 1914 occurrences |
| `attr_reader`, `attr_writer` and `attr_accessor` lines | 75, naming 134 attributes |
| `Node2D`'s own ivars | 39 |
| `Component`'s own ivars | 2: `@node`, through `attr_accessor :node`, and `@context` |
| Ivars already prefixed | 1: `@rgame_sibling_order`, through `attr_accessor` |
| Ivars the Signal DSL makes | one per signal, `@<name>_signal`, through `instance_variable_get` in `signal.rb` |
| `Collection.of(:@ivar)` in a descendant | 0. `Players` and `Dialogue::Transcript` use it, and neither is a node or a component |
| `instance_variable_get` on a descendant in `spec/` | 0 |
| Game code writing a `Node2D` ivar today | 3, each `@width` and `@height`: `examples/pathfinding`'s cursor, `examples/push_pull`'s `Wall`, and `test_projects/asteroids`' `PlayScene` |
| `attr_reader` | 44–46 ns a call, against 37 ns for an empty loop |
| `alias` of an `attr_reader` | 44 ns: the alias keeps the fast reader |
| `def opacity = @rgame_opacity` | 50 ns, 5 ns more than the reader |
| An ivar read through one `Struct` holding every field | 60 ns, against 50 ns for the ivar in a method |

The three game nodes set `@width` and `@height` for their own drawing, and set
the node's size with it by accident. Nothing reads the size of any of the three.
After the sweep each keeps its ivars as its own.

## What already resembles this

**Reuse it.**

- **`SealedPrivates`**, which `Node2D` and `Component` extend. It holds the
  prefix, `PREFIX = 'rgame_'`, and it is where the reader macro goes: every
  descendant inherits it.
- **`spec/rgame/engine/sealed_privates_spec.rb`**, the shape of the engine-side
  spec: a rule pinned against the classes Ruby reports.
- **The house cops** under `lib/rgame/rubocop/cop/game/`, and
  `spec/rgame/cli/generated_project_spec.rb`, which checks that each one fires in
  a generated project.

**Extend or generalise it.**

- **`rgame_` widens from methods to ivars.** One prefix, one meaning: the
  engine's own.
- **The Signal DSL's ivars** take the prefix with everything else, so a game's
  signal and a game's ivar cannot collide either.

**Genuinely new.**

- **The reader macro.** Nothing in the engine defines a reader over a
  differently named ivar today.
- **The game-side cop.** No existing cop reads ivar names.

## Prior art

**Python mangles** a class attribute written `__name` to `_ClassName__name`,
"to avoid name clashes of names with names defined by subclasses"
([the tutorial, Private Variables](https://docs.python.org/3/tutorial/classes.html#private-variables)).
The compiler does it, so no author remembers anything. **C#, Java and C++**
scope a `private` field to its class, so a subclass field of the same name is a
different field. **Ruby does neither.** Every ivar of an object shares one
namespace, whichever class wrote it, so the rule has to come from a convention
and a guard.

## Considered and rejected

- **`@_opacity`.** Short, and common in Ruby for "internal". But in `Node2D` a
  leading `_` means a hook the game overrides, and an ivar a game should keep
  off must not read like one.
- **A prefix of its own**, such as `@engine_`. It would say what `rgame_` says,
  under a second name.
- **`def opacity = @rgame_opacity` for every reader.** Simpler than a macro,
  and 5 ns slower a call. `Node2D`'s y-sort reads `z` and the sorting box of
  each child once per comparison, every frame, in every view.
- **All of `Node2D`'s state in one ivar**, a `Struct` of fields. One name to
  keep off instead of 39, but a read costs 60 ns against 50, and every hot path
  pays it.
- **A runtime guard.** Ruby calls nothing when an ivar is set, and a collision
  is two classes writing one name, which no check after the fact can tell from
  one class writing it twice.
- **An engine-side cop instead of the spec.** A cop reads one file.
  `UI::TextButton < UI::Button` names no `Node2D`, and neither does any other
  indirect subclass, so a cop would have to be told which classes descend from
  one: a list to remember. The spec asks Ruby.
- **Only `Node2D` and `Component`.** See decision 2.

## What this does not deliver

- A seal on a descendant's private methods (open question 1).
- A prefix on ivars of engine classes that are neither nodes nor components.
  `Tween`, `TileMap` and `Camera` are values a game holds, not classes it
  extends.
- A guard against a game *calling* `instance_variable_get(:@rgame_...)` with a
  name built at runtime. The cop sees a literal Symbol or String, nothing more.

---

## Roadmap

### Dependency shape

```
1 the engine side (macro, sweep, spec) ─→ 2 the game side (cop, docs) ─→ 3 fold back
```

Step 1 comes first because the cop in step 2 is only sound once no engine class
a game extends writes an unprefixed ivar. Step 1 is worth landing alone: it
removes every collision, and step 2 only makes a deliberate one loud.

> **A game never shares an ivar with the engine by accident.** Every ivar a
> `Node2D` or `Component` descendant in `RGame::Engine` writes starts with
> `rgame_`, and no game's code writes one that does.

### Step 1 — prefix every engine ivar a game could collide with *(pure)*

The sweep, and the spec that keeps it. The public API does not move.

#### 1a — `sealed_reader`, `sealed_writer`, `sealed_accessor`

```ruby
module RGame
  module Engine
    module SealedPrivates
      # A public reader `name` over the ivar `@rgame_<name>`, as fast as an
      # attr_reader: it is an alias of a private `rgame_<name>` reader, which
      # the seal then covers.
      #
      #   sealed_reader :opacity   # node.opacity reads @rgame_opacity
      def sealed_reader(*names)

      # A public writer `name=` over `@rgame_<name>`, for an attribute with no
      # check to run.
      def sealed_writer(*names)

      def sealed_accessor(*names)
    end
  end
end
```

`SealedPrivates` is extended by `Node2D` and `Component`, so every descendant
has the three. A private `rgame_opacity` is covered by `method_added` like any
other sealed method, in the two base classes.

#### 1b — `Node2D`, `Component` and the Signal DSL

`Node2D`'s 39 ivars and `Component`'s two take the prefix. Their `attr_*` lines
become `sealed_*` lines. The Signal DSL keeps a signal in `@rgame_<name>_signal`.
`SealedPrivates`' header drops "the prefix convention does not apply outside
these two classes", which stops being true.

The three game nodes that write `@width` and `@height` keep theirs as their
own ivars. Their headers say nothing about the node's size today, and nothing
reads it.

#### 1c — the other 64 descendants and the three modules

The same sweep over the remaining 62 files. In the five files that also hold
another class, only the node or component class changes.

#### 1d — the spec

`spec/rgame/engine/prefixed_ivars_spec.rb`. For every class under
`RGame::Engine` that descends from `Node2D` or `Component`, and every engine
module mixed into one, it takes each method the class defines itself, private
ones included. It finds the method's `source_location` and parses that `def`
with `Prism`. It collects the ivars read and written, and the Symbols given to
`attr_*`. It fails naming the class, the method, the line and the ivar.

#### Rules the tests pin

1. Every ivar a descendant's own methods read or write starts with `rgame_`.
2. So does every ivar a mixed-in engine module's methods touch.
3. `sealed_reader :opacity` answers `@rgame_opacity`, publicly, and a subclass
   of `Node2D` defining `rgame_opacity` raises.
4. A game's `Node2D` subclass writing `@footing`, `@paused`, `@player`,
   `@width` or `@opacity` for itself leaves the node's own attribute alone.
5. A signal's ivar is `@rgame_<name>_signal`.
6. The spec fails on a descendant defined in the spec with an unprefixed ivar,
   so it is seen to fire.

#### Tests

- `spec/rgame/engine/sealed_privates_spec.rb`: rule 3, for all three macros.
- `spec/rgame/engine/prefixed_ivars_spec.rb`, new: rules 1, 2 and 6.
- `spec/rgame/engine/node2d_spec.rb`: rule 4, one example per name, beside the
  `@footing` example `footing_spec.rb` already holds.
- `spec/rgame/engine/signal_spec.rb`: rule 5.

#### Verify

No `Node2D` or `Component` descendant in `RGame::Engine` writes an ivar a game
could write by accident.

- `rake spec`, `rake spec:core`, `make test`, and `rake drive:allocations`.
- A scratch benchmark of a y-sorted node drawing 200 children, before and
  after: no slower. `tools/bench_node_draw.rb` draws nothing y-sorted.
- `examples/pathfinding`, `examples/push_pull` and `test_projects/asteroids`
  driven with `--seed 1` before and after: the same draw calls, in the same
  numbers.

### Step 2 — `Game/NoEngineIvar`, and the rule in the docs *(the RuboCop plugin)*

#### 2a — the cop

```ruby
module RuboCop
  module Cop
    module Game
      # An ivar starting with `rgame_`, in a game's code. Every class a game
      # extends keeps its own ivars under that prefix, so a game's ivar with it
      # can only be one of the engine's.
      class NoEngineIvar < Base
        # on_ivar, on_ivasgn, on_op_asgn and on_or_asgn over an ivar, and a
        # Symbol or String starting with "@rgame_" given to
        # instance_variable_get, instance_variable_set or
        # instance_variable_defined?
      end
    end
  end
end
```

It is on in `lib/rgame/rubocop/default.yml`, so a game gets it through the
plugin. `.rubocop.yml` excludes `lib/rgame/**`, where the prefix is the rule.

#### 2b — the docs and the skills

- **CLAUDE.md**: the cop in the table of house cops, which becomes eight, and
  ivars in "A name says which mechanism it is".
- **write-ruby-code**: an ivar row in the table of names, and the reader
  macros.
- **write-example**: the list of `Node2D`'s taken ivars goes. A game's ivars
  are its own.
- **`Node2D#input_owner`**: the paragraph on why it is not `player` goes. It
  is still not `player`, since a public method can collide too, but a reader
  of the name no longer needs the story.
- **`docs/api/scene_graph.md` and `components.md`**: a sentence where a
  subclass is introduced. The engine keeps its ivars under `rgame_`, so a
  subclass names its own freely.
- **`CHANGELOG.md`**: an entry under Changed.

#### Rules the tests pin

1. The cop flags a read, a write and each compound assignment of an `@rgame_`
   ivar, and a literal `:@rgame_...` given to `instance_variable_get`.
2. It flags nothing else: `@rgame`, `@rgamer_x` and `rgame_x` pass.
3. It fires in a generated project.

#### Tests

- `spec/rubocop/cop/game/no_engine_ivar_spec.rb`, new: rules 1 and 2.
- `spec/rgame/cli/generated_project_spec.rb`: rule 3, as for the other cops.

#### Verify

A game that writes `@rgame_opacity` hears about it from RuboCop.

- `rake spec`, and `bundle exec rubocop` over the whole repository reports no
  new offence.

### Step 3 — fold the plan back and delete it

Whatever is still true is already in CLAUDE.md, the skills and `docs/api/` after
step 2. Open question 1 goes into `docs/plans/possible-todos.md` if it is still
open. Then this file goes.

#### Verify

- `CHANGELOG.md` covers both steps, per
  [update-changelog](../../.claude/skills/update-changelog/SKILL.md).
- `grep -rn 'prefixed-ivars' docs .claude CLAUDE.md` finds nothing.
