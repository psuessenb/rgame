# How other engines answer these questions

Seven questions, and what Unreal, Unity, Godot and miniaudio do about each. The
useful part is the last line of every section: what none of them hands us.

## Input: a trigger per action, not a timer per caller

**Unreal's Enhanced Input** puts *triggers* on an action. A `Hold` trigger fires
once the input has been held for `HoldTimeThreshold` seconds, defaulting to one
second, with an optional one-shot setting. A `Tap` trigger fires on a quick
press and release. **One key may drive two actions, one with each trigger: hold
it long enough and the tap is cancelled, so the hold fires instead.** A `Chorded
Action` trigger fires only while another action is active, and its *Consume
Last Input* option — **on by default** — makes the chord fire rather than the
step that completed it. A `Combo` trigger takes a chain of actions.
([Enhanced Input](https://dev.epicgames.com/documentation/unreal-engine/enhanced-input-in-unreal-engine))

**Unity's Input System** calls the same thing an *interaction*, installed on a
binding or on an action: `Press`, `Hold` (`duration`), `Tap` (`duration`),
`SlowTap`, `MultiTap` (`tapCount`, `tapDelay`). Only one interaction drives an
action at a time, and one higher in the stack cancelling lets a lower one take
over — which is how a tap and a hold on the same control resolve. The durations
default to project-wide settings rather than to literals.
([Interactions](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.11/manual/Interactions.html))

**Godot** ships neither. `Input.is_action_pressed` is a level and
`is_action_just_pressed` an edge, and a hold is a timer the game keeps.

**They agree on the shape**, and it is the one this plan takes: a hold and a tap
are declared where the binding is declared, not counted by the caller; the
threshold is a number on the declaration; and a chord swallows the input that
completed it.

**What none of them gives us** is our table. An rgame `InputMap` is a flat,
per-player map of physical ids that a rebinding screen edits, with no asset, no
editor and no control paths. `hold:`, `tap:` and `all:` have to read as entries
in that table, not as objects installed on it.

## Debug drawing: a flag the game may set

**Godot** puts *Visible Collision Shapes* in the editor's Debug menu, and the
same switch is a property the running game may set:
`get_tree().debug_collisions_hint = true`.
([SceneTree](https://docs.godotengine.org/en/stable/classes/class_scenetree.html))
**Unreal** has `showdebug`, a console command with a category per subsystem.
**Unity** draws gizmos, which exist in the editor and not in a build.

**They agree** that debug drawing is a switch per category rather than a widget,
and that a shape draws itself where it is rather than being collected by a
drawing pass.

**What none of them gives us** is a game's own category in the same list.
Godot's flags are fixed, and Unreal's `showdebug` categories are engine
subsystems. An `Engine::Debug` that takes `define(:paths) { ... }` costs one
hash and makes the layer worth keeping in a game.

## Scene changes: the engine switches, the game keeps what survives

**Godot** replaces the current scene with `change_scene_to_file`, and everything
in it is freed. What must survive goes in an *autoload* — a node the scene tree
keeps outside the current scene — which is also where the community's scene
switchers and fade transitions live.
([Singletons](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html))
**Unity** loads a scene through `SceneManager` and keeps objects across it with
`DontDestroyOnLoad`.

**They agree** that something must survive a scene change, and that the engine
does not say what. Neither ships a transition: a fade is an overlay plus a tween
in both, written by the game.

**What none of them gives us**, and what this plan takes from
[F4](01-current-state.md#f4), is that in rgame a node that moves between scenes
re-registers with the new scene's systems by itself. So the survivor can be the
hero node rather than a global — the thing both engines route around.

## Pushing: everybody writes it

**Godot's** character bodies do not push rigid bodies at all: a `CharacterBody2D`
that runs into one is stopped as if it were static, and pushing means reading
the collision normal after the move and applying a force scaled by a
`push_force` you tune by hand.
([Godot recipes: character vs rigid body](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/))
**Unity's** character controller is the same story with `OnControllerColliderHit`.
Sokoban-style pushing — one cell per press, refused if the next cell is taken —
is hand-written everywhere it appears.

**They agree** on nothing helpful, and the reason is worth stating: both engines
solve the general problem with a physics simulation, so "push" becomes a force
and the feel comes out of mass and friction. rgame has no simulation. Its
collision answers one question — *what is in the way* — and pushing is the same
question asked from the other side: **the mover moves what it would have been
stopped by, as far as that thing's own blockers allow.** No forces, no mass, and
the crate against a wall stops the pusher because the crate's own resolve
returns zero.

**What none of them gives us** is therefore also what makes ours small.

## Tabs: the shoulder buttons belong to the tab bar

**Unreal's CommonUI** ships `CommonTabListWidgetBase`, a list of tabs that
activates a widget in a linked switcher, with a *Next Tab* and *Previous Tab*
input action on the list itself. The convention it encodes: **the bumpers are
routed to the tab bar at the top, while the face buttons go to whatever
cardinal navigation has focused.**
([CommonTabListWidgetBase](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/CommonTabListWidgetBase),
[Switchers and tabs](https://unrealist.org/commonui-switchers-and-tabs/))

**They agree** that tabs are a separate input route rather than a set of buttons
in the same focus order. That is what makes a tabbed screen feel right on a pad:
the tab never has to be focused to be changed.

**What none of them gives us** is a keyboard answer.
[Open question 2](README.md#open-questions) picks it.

## Particles: a parameter list worth copying

**Godot's `CPUParticles2D`** is the vocabulary: `lifetime` with a randomness
ratio, `spread` around the node's direction, an initial linear velocity,
gravity, accelerations, a scale curve and a colour ramp the particle walks over
its life, and `one_shot` for a burst.
([CPUParticles2D](https://docs.godotengine.org/en/stable/classes/class_cpuparticles2d.html))
Unity's particle system is the same set spread over modules.

**They agree** that a particle's colour and size are read from a curve over its
own life, not stepped by the game, and that a burst and a stream are one
emitter with a flag.

**What none of them gives us** is the small version. Both are hundreds of
parameters; sparkles, dust and a puff of smoke need a handful, and the rest can
arrive when something asks for it.

## Audio fades: a volume ramp, and an argument about the clock

**miniaudio**, which is already vendored here, fades a sound with
`ma_sound_set_fade_in_milliseconds(sound, from, to, ms)`, where `-1` means
"from wherever it is now" — a ramp applied on the audio thread. It also has
`ma_sound_group` for a volume per category, and `ma_sound_set_stop_time_in_*`
for a stop scheduled in the future. (`ext/rgame_core/vendor/miniaudio.h`, the
"Fading and Volume Ramping" section.)

**Unity** does not fade a source at all: it transitions a mixer between
snapshots over `timeToReach` seconds, so the fade belongs to the mixer graph
rather than to the sound.
([TransitionToSnapshots](https://docs.unity3d.com/ScriptReference/Audio.AudioMixer.TransitionToSnapshots.html))
**Godot** tweens `volume_db` on the player, which is the fade driven from the
frame loop.

**They agree** that a fade is a volume ramp over a duration, and disagree about
who holds the clock. Unity's mixer and miniaudio run it on the audio side, where
it is smooth and unpauseable. Godot's tween runs it on the game side, where it
is pauseable and testable.

**What decides it here** is that rgame's whole engine layer is specced with no
device at all: a fade driven by `update(dt)` can be asserted at 0.25 s by
passing 0.25, and one on the audio thread cannot be asserted at all. So the
engine holds the clock, and miniaudio's ramp is the fallback if 60 volume steps
a second are audible — see
[decision 14](README.md#decisions-already-taken).

## Cutscenes: a list of commands, or a timeline

**Unreal's Sequencer** and **Unity's Timeline** are editor timelines: tracks,
keyframes, and a scrubber. They are authoring tools first, and a game without an
editor gets nothing out of their shape.

**RPG Maker's event commands** are the other tradition, and the one that fits
here: a numbered list of commands run in order — move this character, wait,
show this text, play this sound — where each command finishes before the next
starts.

**They agree** that a cutscene is a sequence with waits, and that the
interesting part is what a step may wait *for*.

**What none of them gives us** is the wait this engine already has:
`Components::PathFollow` emits `on_finished`, `Components::Tween` emits
`on_finished`, and `Engine::Dialogue` emits `on_ended`. A step that ends "on a
signal" needs no polling, because everything that takes time here already says
when it is done.
