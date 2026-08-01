#ifndef RGAME_CORE_H
#define RGAME_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Public API of the core engine.
 *
 * This header intentionally exposes no SDL or OpenGL types. Callers (the
 * standalone app in src/main.c, the Ruby C extension in core_ext.c) only ever
 * see an opaque handle. That keeps the door open for wrapping this library
 * from Ruby without leaking C-library-specific types into ruby.h-using code.
 */

typedef struct rgame_app rgame_app;

/* Creates the window, GL context and internal state. Returns NULL on failure. */
rgame_app *rgame_app_create(int width, int height, const char *title);

/* Destroys the GL context/window and frees the app. Safe to call with NULL. */
void rgame_app_destroy(rgame_app *app);

/*
 * ---------------------------------------------------------------------------
 * Input: devices and buttons
 * ---------------------------------------------------------------------------
 *
 * One flat button-id space covers every input device, so a single "is this
 * held" query serves them all. It is partitioned into ranges rather than
 * packed into bit fields, which means adding a device class later appends to
 * an unused range instead of renumbering anything that already exists:
 *
 *   0x0000–0x0FFF  keyboard (SDL scancode values)
 *   0x1000–0x10FF  gamepad buttons and dpad
 *
 * (The range a mouse would have occupied is deliberately left unused — mouse
 * input is not part of this engine; see docs/plans/gosu-replacement/.)
 *
 * Keyboard ids are SDL scancodes, but callers must not need SDL to name them:
 * src/main.c includes only this header, so the constants it uses have to live
 * here. app.c carries a _Static_assert for every one, so these can never
 * silently drift from the SDL values they mirror.
 */
#define RGAME_BUTTON_KEYBOARD_FIRST 0x0000
#define RGAME_BUTTON_KEYBOARD_LAST 0x0FFF
#define RGAME_BUTTON_GAMEPAD_FIRST 0x1000
#define RGAME_BUTTON_GAMEPAD_LAST 0x10FF

/* Keyboard ids == SDL scancodes. Only the keys the engine actually binds are
 * named; adding one is a #define plus a _Static_assert in app.c. */
#define RGAME_KEY_RETURN 40
#define RGAME_KEY_ESCAPE 41
#define RGAME_KEY_SPACE 44
#define RGAME_KEY_F1 58
#define RGAME_KEY_RIGHT 79
#define RGAME_KEY_LEFT 80
#define RGAME_KEY_DOWN 81
#define RGAME_KEY_UP 82

/*
 * Which device a query is about. The keyboard is device 0 so single-player
 * code can ignore the parameter entirely; gamepads follow, one per player
 * slot, in the stable slot order the hot-plug table hands out.
 */
#define RGAME_INPUT_KEYBOARD 0
#define RGAME_INPUT_GAMEPAD_FIRST 1
#define RGAME_INPUT_MAX_GAMEPADS 4
#define RGAME_INPUT_GAMEPAD(slot) (RGAME_INPUT_GAMEPAD_FIRST + (slot))
#define RGAME_INPUT_DEVICE_COUNT (RGAME_INPUT_GAMEPAD_FIRST + RGAME_INPUT_MAX_GAMEPADS)

/*
 * Per-frame and event callbacks.
 *
 * These are deliberately fixed-arity (each takes exactly the arguments it
 * needs, plus an opaque userdata pointer) rather than variadic. A variadic
 * calling convention on a per-frame hot path allocates/marshals on every
 * single call for no benefit — see docs/c_engine_feature_specs.md section 4,
 * which calls this out as a concrete cost worth designing out from the start.
 */
typedef void (*rgame_frame_begin_fn)(void *userdata);
typedef void (*rgame_update_fn)(void *userdata, double dt_seconds);
typedef void (*rgame_draw_fn)(void *userdata);
typedef int (*rgame_needs_redraw_fn)(void *userdata);
typedef void (*rgame_button_fn)(void *userdata, int button_id);
typedef void (*rgame_resize_fn)(void *userdata, int width, int height);

/*
 * The callbacks rgame_app_run drives, gathered into one struct rather than
 * passed as an ever-growing list of positional arguments. Every member may be
 * NULL, in which case that hook is simply skipped.
 *
 *  - `frame_begin` runs once per rendered frame, before that frame's
 *    simulation ticks. It is the place to sample input once and reuse the
 *    result across every catch-up tick, so a key held for one frame behaves
 *    the same however many ticks that frame ends up running.
 *  - `update` runs at a fixed timestep via an internal accumulator, so it may
 *    be called zero or several times per rendered frame; dt_seconds is that
 *    fixed step, not wall-clock frame time.
 *  - `needs_redraw` is polled before drawing; returning 0 skips the draw for
 *    that frame (simulation still advances). NULL means always redraw.
 *  - `draw` renders one frame.
 *  - `button_down`/`button_up` report discrete key presses and releases. Key
 *    repeats are filtered out, so holding a key reports exactly one press.
 *  - `resize` reports a new window size; the GL viewport is already updated.
 *  - `userdata` is forwarded to every callback; may be NULL.
 */
typedef struct {
    rgame_frame_begin_fn frame_begin;
    rgame_update_fn update;
    rgame_needs_redraw_fn needs_redraw;
    rgame_draw_fn draw;
    rgame_button_fn button_down;
    rgame_button_fn button_up;
    rgame_resize_fn resize;
    void *userdata;
} rgame_app_callbacks;

/*
 * Runs the main loop until the window is closed or rgame_app_close is called.
 *
 * The engine owns the loop and calls back out through `callbacks`. Note there
 * is no built-in quit key: closing on Escape is a game decision, so it belongs
 * in a button_down handler rather than in here.
 */
void rgame_app_run(rgame_app *app, const rgame_app_callbacks *callbacks);

/*
 * Asks the loop to stop. Safe to call from inside a callback — the loop checks
 * between steps, so it exits without starting further work this frame.
 */
void rgame_app_close(rgame_app *app);

/* Current window size, in window coordinates. */
int rgame_app_width(const rgame_app *app);
int rgame_app_height(const rgame_app *app);

/* Window title. The returned string is owned by the window, not the caller. */
const char *rgame_app_title(const rgame_app *app);
void rgame_app_set_title(rgame_app *app, const char *title);

/*
 * Is `button_id` currently held on `device`?
 *
 * This reads a snapshot taken once per frame, when the event queue is pumped —
 * not live hardware state. That is deliberate: the answer is then identical
 * for every simulation tick within one frame, so a key held for a single frame
 * behaves the same whether that frame ran one catch-up tick or five. Sampling
 * live state would make the result depend on tick count, which is exactly the
 * nondeterminism a fixed timestep exists to remove.
 *
 * A device only answers for buttons in its own range, so asking a gamepad
 * about a keyboard key is 0 rather than an error.
 */
int rgame_app_input_down(const rgame_app *app, int device, int button_id);

/* Monotonic milliseconds since startup. For time-based animation phase, etc. */
unsigned int rgame_app_ticks_ms(const rgame_app *app);

/* Most recent frames-per-second reading (updated ~once per second). */
double rgame_app_fps(const rgame_app *app);

#ifdef __cplusplus
}
#endif

#endif /* RGAME_CORE_H */
