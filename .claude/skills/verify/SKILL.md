---
name: verify
description: How to verify rgame changes — the four test tiers (Check/C, RSpec/Ruby, headless live window with synthetic keyboard input, manual), and how to prove new C code does not leak. Use when writing or reviewing engine code, adding a C class or Ruby extension, testing input handling, checking for memory leaks, or deciding what kind of test a change needs.
---

# Verifying rgame

Four tiers. **Pick the highest one that can answer the question**, because the
cheap tiers are the ones that stay green.

| Tier | Command | Covers | Speed |
|---|---|---|---|
| 1. C unit | `make test` | Pure logic in C (no SDL/GL) | instant |
| 2. Ruby unit | `bundle exec rspec` | Ruby-visible API contract | fast |
| 3. Live window | `ruby .claude/skills/verify/scripts/smoke_live_window.rb` | Real SDL window + GL + input, **headless** | ~5s |
| 4. Manual | `make run` / `ruby ext/.../example.rb` | Does it look right | human |

Tiers 1–3 are all automated and need no display. Tier 3 is the one most
projects skip; here it works, and the harness is in `scripts/`.

The architecture exists to keep things in tier 1 — see CLAUDE.md's layering
rules and `docs/plans/gosu-replacement/`. If a thing is hard to test, that is
usually a sign the pure-logic part has not been separated out yet.

---

## What goes in which tier

**Tier 1 — Check, `test/test_*.c`.** Anything with no SDL/GL/IO: the
fixed-timestep accumulator, transform composition, clip-rect intersection,
z-sort and batching, glyph cache eviction, tile culling, the gamepad slot
table. This is most of what is actually hard to get right. Write these first,
before touching SDL.

**Tier 2 — RSpec, `spec/`.** The Ruby-visible API contract: argument shapes,
keyword defaults, return values, error classes. Also where C-extension
lifetime checks live (see "Leaks", below). Specs must not touch
`RGame::Core` — if something there needs a spec, the testable part belongs in
`Util`.

**Tier 3 — live window.** "Did a real SDL window open, take real input, and
render without a GL error." Use it for the layer-3 shim only. Do not use it for
logic that tier 1 could cover.

**Tier 4 — manual.** Subjective/visual only. Never the only evidence for a
correctness claim.

---

## Tier 3: the live window (verified working)

The whole tier runs headless on a private Xvfb with Mesa's software rasterizer,
so it needs no GPU, no display, and does not touch the user's desktop session.

```
ruby .claude/skills/verify/scripts/smoke_live_window.rb
```

Building your own:

```ruby
require_relative '.claude/skills/verify/scripts/live_window'

LiveWindow.run(cmd: ['build/rgame'], title: 'rgame', display: ':99') do |w|
  w.keys.tap('Left')                 # discrete press+release
  w.keys.hold('space') { sleep 0.3 } # the "is held" polling path
  w.keys.tap('Escape')
  status = w.wait_for_exit
  # then assert on w.log, which is the app's stdout+stderr
end
```

Input goes in through **XTEST** (`scripts/xkeys.rb`, via Ruby's stdlib
`fiddle`). No gems, no dev headers, no root, nothing to install.

**Verified on this machine:** synthetic keys reach both a Gosu window and
rgame's own SDL window; both the discrete-event path (`button_down`/`up`) and
the held-key polling path work; `Escape` shuts the engine down cleanly.

### Why XTEST and not xdotool

XTEST injects at the X server's input layer, so events are indistinguishable
from real keypresses — that part is measured, it works. The rest of this
paragraph is *reasoning, not measurement* (xdotool is not installed here):
`xdotool key --window <id>` uses `XSendEvent`, whose events carry
`send_event=True`, which SDL is documented to ignore, so it should silently do
nothing; plain `xdotool key` is XTEST and should work. Either way `fiddle`
gives us XTEST with no package to install, so the question stays academic.

### The app must report what it saw

The harness can only assert on the app's output, so the app under test has to
say what it received. For a throwaway probe, log one line per event to a
`sync`-ed file or stdout, and always include a frame-count timeout so a broken
run can never hang.

---

## Leaks

Leak checking is part of **writing** the code, not a separate test suite. The
rule: any commit that adds C which allocates gets run once through the relevant
check below before it is called done.

### C code — AddressSanitizer (reliable, use this)

```
make clean
make CFLAGS="-std=c17 -Wall -Wextra -g -fPIC -fsanitize=address,undefined -fno-omit-frame-pointer"
make test CFLAGS="-std=c17 -Wall -Wextra -g -fPIC -fsanitize=address,undefined -fno-omit-frame-pointer"
ruby .claude/skills/verify/scripts/smoke_live_window.rb   # also checks the SDL path
make clean && make                                        # restore a normal build
```

ASan + UBSan are already available (`gcc -print-file-name=libasan.so`) — nothing
to install, and no valgrind needed.

**Verified:** a deliberate `malloc` with no `free` in a Check test is caught,
reported with a full stack, and **fails the run** (exit 1). Under Check's
default fork mode it surfaces as an `Error` attributed to the specific test,
which is exactly what you want. `CK_FORK=no` also catches it but reports it
after the summary line.

**Verified:** the current engine's full create → run → destroy cycle under
Xvfb is clean — no leaks, no UB.

### Mutation-check a new suite — and do it under ASan

A Check suite that goes green the first time has not been shown to be
load-bearing. Break the implementation deliberately, once per behaviour you
believe is covered, and confirm the suite fails:

```
cp ext/rgame_core/<mod>.c /tmp/orig.c
# edit in a bug, then:
make test          # must FAIL
cp /tmp/orig.c ext/rgame_core/<mod>.c
```

**Run the mutations under the sanitizer build too**, not just the plain one:

```
make test CFLAGS="-std=c17 -Wall -Wextra -g -fPIC -fsanitize=address,undefined -fno-omit-frame-pointer"
```

Measured, twice, on real modules here:

- A reconnect test passed for the wrong reason — the slot it expected was also
  the lowest free slot, so "reclaimed by GUID" and "took the first gap" were
  indistinguishable. Fixed by making the expected slot *not* the obvious one.
- Deleting a negative-index guard **survived a plain build** and was caught only
  under ASan (`stack-buffer-underflow`). Out-of-bounds reads usually return a
  plausible zero, so a guard against them looks like dead code until the
  sanitizer is watching.

If a mutation survives for a reason you can explain and accept — a guard that
only becomes load-bearing in later work, say — write the reason into a comment
at the guard, so the next person doesn't delete it as redundant.

### Ruby extensions — a live-object counter (reliable, use this)

Sanitizers do **not** work through Ruby (see "Dead ends"). Instead, have the
extension count outstanding C allocations and assert the count returns to its
baseline after GC. This directly tests the bug that actually happens: a
TypedData `dfree` that is missing, or that frees the wrapper but not an inner
buffer.

In the extension, behind a debug-only method:

```c
static long live_things = 0;   /* ++ where you allocate, -- in dfree */

static VALUE debug_live_things(VALUE m) { (void)m; return LONG2NUM(live_things); }
/* rb_define_singleton_method(mCore, "debug_live_things", debug_live_things, 0); */
```

In a spec:

```ruby
def settle = 3.times { GC.start(full_mark: true, immediate_sweep: true) }

it 'frees its C buffer when collected' do
  settle
  before = RGame::Core.debug_live_things
  500.times { RGame::Core::Thing.new(...) }
  settle
  expect(RGame::Core.debug_live_things).to eq(before)
end
```

**Verified:** against a correct class this reports 0 → 0; against a class whose
`dfree` forgets the inner buffer it reports 0 → 500. Exact, deterministic, no
sanitizer, runs in the normal spec suite.

Also worth doing once per new TypedData class, since it catches GC-mark bugs
that leak nothing but crash later:

```ruby
GC.verify_compaction_references(expand_heap: true, toward: :empty)
```

### Dead ends — do not retry these

Both were tried on this machine and measured. They do not work; the failure
mode of each is *silence*, which is why they are recorded here.

- **ASan/LSan through Ruby** (`LD_PRELOAD=libasan.so`, with or without
  `RUBY_FREE_AT_EXIT=1`). The exit-time leak check never fires under Ruby at
  all. Driving it on demand via `__lsan_do_recoverable_leak_check` does fire,
  but a deliberate 20 × 4096-byte leak in an extension was reported **3 times
  out of 20, with the extension never appearing in any stack trace** — Ruby's
  conservative machine-stack scanning makes most leaked blocks look reachable.
  It also drowns the report in ~11,000 allocations of Ruby's own. Unusable.
- **RSS growth loops.** Churning objects and watching `VmRSS` gave a **28 MB
  rise on a class with no leak at all** — Ruby's heap high-water mark and
  malloc arena retention dominate the signal completely. Unusable as a leak
  signal at any threshold worth setting.

---

## Gotchas that cost time

- **Xvfb sidesteps Wayland.** This is a Wayland session, where synthetic input
  to the real display is unreliable. Do not fight that — every automated test
  runs on its own Xvfb, where XTEST works normally and there is no compositor
  or window manager involved.
- **`LIBGL_ALWAYS_SOFTWARE=1` and `GALLIUM_DRIVER=llvmpipe` are required.**
  Xvfb has no GPU; without them `SDL_GL_CreateContext` fails.
- **Focus is usually already correct.** SDL takes input focus for its own
  window when it maps it, and a bare Xvfb has no window manager to argue with
  it — measured: the window owns focus before the harness does anything.
  `w.keys.focus(id)` exists for the multi-window / WM case; it is insurance,
  not the fix. If keys seem lost, check `w.keys.focused_window` before assuming
  a focus problem.
- **`bundle exec` needs an absolute `BUNDLE_GEMFILE`** when spawned from
  another cwd. `LiveWindow` sets it. Without it you get a bare "Could not
  locate Gemfile" on the child's stderr and the window never appears — which
  looks identical to a broken injector.
- **`tap` needs a settle longer than one frame** (16 ms at 60 fps), or the
  event pump can miss the press/release pair. The default 50 ms is fine.
- **Give each concurrent run its own display number.** `:99` is the default;
  parallel tests must differ.
- **Test both input paths.** Discrete events (`button_down`) and held-key
  polling (`down?`) are different code paths and break independently.

---

## Extending this skill

This is a living document. When a verification problem costs more than a few
minutes, add what was learned — especially **negative** results, since those
are what otherwise get retried. Keep the "verified" claims tied to something
actually run; if a claim here is not reproducible, fix or delete it rather than
softening it.
