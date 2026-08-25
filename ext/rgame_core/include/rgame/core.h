#ifndef RGAME_CORE_H
#define RGAME_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

/* size_t only — this header still exposes no SDL or GL types. */
#include <stddef.h>

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
 * (The range a mouse would have occupied is deliberately left unused. Mouse
 * input is not part of this engine — see RGame::Core::Input — and leaving the
 * gap costs nothing while renumbering later would cost every saved keybinding.)
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

/* Keyboard ids == SDL scancodes, which are physical *positions* rather than
 * letters: RGAME_KEY_A is the key marked A on a QWERTY board and Q on AZERTY.
 * The set is what a Western keyboard can be relied on to have. No numpad (most
 * laptops have none), no GUI/Windows/Command key, no print-screen cluster, and
 * nothing whose position depends on the layout. Those can be added when
 * something needs them; each is a #define plus a _Static_assert in app.c. */
#define RGAME_KEY_A 4
#define RGAME_KEY_B 5
#define RGAME_KEY_C 6
#define RGAME_KEY_D 7
#define RGAME_KEY_E 8
#define RGAME_KEY_F 9
#define RGAME_KEY_G 10
#define RGAME_KEY_H 11
#define RGAME_KEY_I 12
#define RGAME_KEY_J 13
#define RGAME_KEY_K 14
#define RGAME_KEY_L 15
#define RGAME_KEY_M 16
#define RGAME_KEY_N 17
#define RGAME_KEY_O 18
#define RGAME_KEY_P 19
#define RGAME_KEY_Q 20
#define RGAME_KEY_R 21
#define RGAME_KEY_S 22
#define RGAME_KEY_T 23
#define RGAME_KEY_U 24
#define RGAME_KEY_V 25
#define RGAME_KEY_W 26
#define RGAME_KEY_X 27
#define RGAME_KEY_Y 28
#define RGAME_KEY_Z 29
#define RGAME_KEY_1 30
#define RGAME_KEY_2 31
#define RGAME_KEY_3 32
#define RGAME_KEY_4 33
#define RGAME_KEY_5 34
#define RGAME_KEY_6 35
#define RGAME_KEY_7 36
#define RGAME_KEY_8 37
#define RGAME_KEY_9 38
#define RGAME_KEY_0 39
#define RGAME_KEY_RETURN 40
#define RGAME_KEY_ESCAPE 41
#define RGAME_KEY_BACKSPACE 42
#define RGAME_KEY_TAB 43
#define RGAME_KEY_SPACE 44
#define RGAME_KEY_MINUS 45
#define RGAME_KEY_EQUALS 46
#define RGAME_KEY_LEFTBRACKET 47
#define RGAME_KEY_RIGHTBRACKET 48
#define RGAME_KEY_BACKSLASH 49
#define RGAME_KEY_SEMICOLON 51
#define RGAME_KEY_APOSTROPHE 52
#define RGAME_KEY_GRAVE 53
#define RGAME_KEY_COMMA 54
#define RGAME_KEY_PERIOD 55
#define RGAME_KEY_SLASH 56
#define RGAME_KEY_CAPSLOCK 57
#define RGAME_KEY_F1 58
#define RGAME_KEY_F2 59
#define RGAME_KEY_F3 60
#define RGAME_KEY_F4 61
#define RGAME_KEY_F5 62
#define RGAME_KEY_F6 63
#define RGAME_KEY_F7 64
#define RGAME_KEY_F8 65
#define RGAME_KEY_F9 66
#define RGAME_KEY_F10 67
#define RGAME_KEY_F11 68
#define RGAME_KEY_F12 69
#define RGAME_KEY_INSERT 73
#define RGAME_KEY_HOME 74
#define RGAME_KEY_PAGEUP 75
#define RGAME_KEY_DELETE 76
#define RGAME_KEY_END 77
#define RGAME_KEY_PAGEDOWN 78
#define RGAME_KEY_RIGHT 79
#define RGAME_KEY_LEFT 80
#define RGAME_KEY_DOWN 81
#define RGAME_KEY_UP 82
#define RGAME_KEY_LCTRL 224
#define RGAME_KEY_LSHIFT 225
#define RGAME_KEY_LALT 226
#define RGAME_KEY_RCTRL 228
#define RGAME_KEY_RSHIFT 229
#define RGAME_KEY_RALT 230

/* Gamepad button ids: the gamepad range plus SDL's controller button number.
 * app.c asserts each against the SDL constant it mirrors, as with the keys. */
#define RGAME_PAD_A (RGAME_BUTTON_GAMEPAD_FIRST + 0)
#define RGAME_PAD_B (RGAME_BUTTON_GAMEPAD_FIRST + 1)
#define RGAME_PAD_X (RGAME_BUTTON_GAMEPAD_FIRST + 2)
#define RGAME_PAD_Y (RGAME_BUTTON_GAMEPAD_FIRST + 3)
#define RGAME_PAD_BACK (RGAME_BUTTON_GAMEPAD_FIRST + 4)
#define RGAME_PAD_GUIDE (RGAME_BUTTON_GAMEPAD_FIRST + 5)
#define RGAME_PAD_START (RGAME_BUTTON_GAMEPAD_FIRST + 6)
#define RGAME_PAD_LEFT_STICK (RGAME_BUTTON_GAMEPAD_FIRST + 7)
#define RGAME_PAD_RIGHT_STICK (RGAME_BUTTON_GAMEPAD_FIRST + 8)
#define RGAME_PAD_LEFT_SHOULDER (RGAME_BUTTON_GAMEPAD_FIRST + 9)
#define RGAME_PAD_RIGHT_SHOULDER (RGAME_BUTTON_GAMEPAD_FIRST + 10)
#define RGAME_PAD_DPAD_UP (RGAME_BUTTON_GAMEPAD_FIRST + 11)
#define RGAME_PAD_DPAD_DOWN (RGAME_BUTTON_GAMEPAD_FIRST + 12)
#define RGAME_PAD_DPAD_LEFT (RGAME_BUTTON_GAMEPAD_FIRST + 13)
#define RGAME_PAD_DPAD_RIGHT (RGAME_BUTTON_GAMEPAD_FIRST + 14)
#define RGAME_PAD_MISC1 (RGAME_BUTTON_GAMEPAD_FIRST + 15)
#define RGAME_PAD_PADDLE1 (RGAME_BUTTON_GAMEPAD_FIRST + 16)
#define RGAME_PAD_PADDLE2 (RGAME_BUTTON_GAMEPAD_FIRST + 17)
#define RGAME_PAD_PADDLE3 (RGAME_BUTTON_GAMEPAD_FIRST + 18)
#define RGAME_PAD_PADDLE4 (RGAME_BUTTON_GAMEPAD_FIRST + 19)
#define RGAME_PAD_TOUCHPAD (RGAME_BUTTON_GAMEPAD_FIRST + 20)

/*
 * Analog axes are their own small id space rather than part of the button
 * space: they are float-valued and read through a different call, so folding
 * them in would only invite asking for an axis as if it were a button.
 *
 * Stick axes read -1.0 to 1.0 (Y is positive *downwards*, as SDL reports it);
 * triggers read 0.0 to 1.0. No dead zone is applied — where to put one is a
 * game decision, and a resting stick genuinely does report small non-zero
 * values.
 */
#define RGAME_AXIS_LEFT_X 0
#define RGAME_AXIS_LEFT_Y 1
#define RGAME_AXIS_RIGHT_X 2
#define RGAME_AXIS_RIGHT_Y 3
#define RGAME_AXIS_TRIGGER_LEFT 4
#define RGAME_AXIS_TRIGGER_RIGHT 5

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
typedef void (*rgame_frame_end_fn)(void *userdata);
typedef int (*rgame_needs_redraw_fn)(void *userdata);
typedef void (*rgame_button_fn)(void *userdata, int button_id);
typedef void (*rgame_resize_fn)(void *userdata, int width, int height);
typedef void (*rgame_gamepad_fn)(void *userdata, int slot);

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
 *  - `frame_end` runs once per rendered frame, after that frame's drawing has
 *    been submitted to the GPU but *before* the buffer swap — the only point
 *    at which the frame just drawn can be read back deterministically. Never
 *    called when `needs_redraw` skipped the draw. Rarely needed: it exists for
 *    reading pixels back for a test, not for game code, since a real driver is
 *    free to swap however it likes once `draw` returns.
 *  - `button_down`/`button_up` report discrete key presses and releases. Key
 *    repeats are filtered out, so holding a key reports exactly one press.
 *  - `resize` reports a new window size; the GL viewport is already updated.
 *  - `gamepad_connected`/`gamepad_disconnected` report a controller arriving
 *    at or leaving a player slot. A slot is stable across a momentary
 *    unplug/replug, so "player 2" stays player 2.
 *  - `userdata` is forwarded to every callback; may be NULL.
 */
typedef struct {
    rgame_frame_begin_fn frame_begin;
    rgame_update_fn update;
    rgame_needs_redraw_fn needs_redraw;
    rgame_draw_fn draw;
    rgame_frame_end_fn frame_end;
    rgame_button_fn button_down;
    rgame_button_fn button_up;
    rgame_resize_fn resize;
    rgame_gamepad_fn gamepad_connected;
    rgame_gamepad_fn gamepad_disconnected;
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

/*
 * Current value of an analog axis on `device`, read from the same per-frame
 * snapshot as rgame_app_input_down. Sticks read -1.0..1.0, triggers 0.0..1.0.
 * An unknown device or axis, or a slot with no controller, reads 0.0.
 */
float rgame_app_input_axis(const rgame_app *app, int device, int axis_id);

/* Is a controller plugged into player `slot` (0-based, < RGAME_INPUT_MAX_GAMEPADS)? */
int rgame_app_gamepad_connected(const rgame_app *app, int slot);

/*
 * Human-readable name of the controller in `slot`, for "Player 2: connect a
 * controller" UI. Returns NULL when the slot is empty. The string is owned by
 * the engine and is only valid while that controller stays connected.
 */
const char *rgame_app_gamepad_name(const rgame_app *app, int slot);

/* How many controllers are currently connected. */
int rgame_app_gamepad_count(const rgame_app *app);

/* Monotonic milliseconds since startup. For time-based animation phase, etc. */
unsigned int rgame_app_ticks_ms(const rgame_app *app);

/* Most recent frames-per-second reading (updated ~once per second). */
double rgame_app_fps(const rgame_app *app);

/*
 * ---------------------------------------------------------------------------
 * Images
 * ---------------------------------------------------------------------------
 *
 * An image is a rectangle of an uploaded texture. `rgame_image_load` decodes a
 * PNG and uploads it; `rgame_image_subimage` and `rgame_image_tile` carve that
 * upload into sprites *without decoding or uploading anything again* — they
 * are views sharing one GPU texture, which is what makes slicing a sprite
 * sheet into hundreds of frames cheap.
 *
 * Every handle returned here, views included, must be passed to
 * `rgame_image_destroy`. The shared texture is deleted when the last of them
 * goes, in whatever order they go — so a sheet can be dropped while its tiles
 * are still in use.
 *
 * Images belong to the `app` whose GL context they were uploaded into, but they
 * do not have to be destroyed before it. Destroying the app first closes the
 * window immediately and takes its textures with it — a GL context frees
 * everything in it — and the images left behind stay valid handles that free
 * cleanly afterwards. Either order works, which matters because a garbage
 * collector picks the order, not the programmer.
 *
 * Images are scaled with nearest-neighbour sampling, always: the engine exists
 * to draw pixel art, and smoothing it is never the intent.
 */
typedef struct rgame_image rgame_image;

/*
 * Decodes the PNG at `path` and uploads it. Returns NULL on failure, writing a
 * human-readable reason into `err` (which may be NULL if the caller does not
 * want one). Failure is ordinary — a missing or corrupt asset file — so it is
 * reported rather than logged and swallowed.
 */
rgame_image *rgame_image_load(rgame_app *app, const char *path, char *err, size_t err_size);

/*
 * A view of part of `image`, in pixels relative to `image` itself — so a
 * subimage of a subimage composes, and none of them can address pixels outside
 * what they were cut from. Returns NULL if the rectangle does not fit.
 */
rgame_image *rgame_image_subimage(const rgame_image *image, int x, int y, int width, int height);

/*
 * Grid slicing, for sprite sheets. `rgame_image_tile_count` reports how many
 * whole tiles of that size fit (a partial tile at the right or bottom edge is
 * padding and is not counted); `rgame_image_tile` returns the index-th of
 * them, counting left to right and then top to bottom, or NULL if the index is
 * out of range.
 */
int rgame_image_tile_count(const rgame_image *image, int tile_width, int tile_height);
rgame_image *rgame_image_tile(const rgame_image *image, int tile_width, int tile_height,
                              int index);

int rgame_image_width(const rgame_image *image);
int rgame_image_height(const rgame_image *image);

/* Releases this handle's share of the texture. Safe to call with NULL. */
void rgame_image_destroy(rgame_image *image);

/*
 * ---------------------------------------------------------------------------
 * Drawing
 * ---------------------------------------------------------------------------
 *
 * Every call here is only valid **inside the draw callback**. The app opens a
 * frame before calling it and closes the frame afterwards, sorting and
 * submitting what was drawn; outside that window there is no frame to draw
 * into, and these calls do nothing. `rgame_app_is_drawing` says which state the
 * app is in, so a binding can raise instead of silently discarding.
 *
 * Drawing is not immediate. A call appends to a queue that is z-sorted and
 * batched when the frame closes, so the order calls are made in does not
 * decide what ends up on top — `z` does, and equal z keeps call order.
 *
 * Colours are packed 0xRRGGBBAA, matching RGame::Util::Color#packed.
 *
 * Coordinates are in screen pixels with (0,0) at the top-left and y growing
 * downwards, transformed by whatever is on the stack (see the push/pop calls
 * below). Angles are in degrees, and positive turns clockwise on screen.
 */

/* Is the app between opening and closing a frame — that is, inside `draw`? */
int rgame_app_is_drawing(const rgame_app *app);

void rgame_app_draw_rect(rgame_app *app, float x, float y, float width, float height,
                         unsigned int color, double z);

/*
 * `xy8` is four points, `xy6` three, as flat x,y pairs. A quad's corners are
 * taken in loop order — for a rectangle: top-left, top-right, bottom-right,
 * bottom-left — so listing them in Z order gives an hourglass, not a shape.
 */
void rgame_app_draw_quad(rgame_app *app, const float *xy8, unsigned int color, double z);
void rgame_app_draw_triangle(rgame_app *app, const float *xy6, unsigned int color, double z);

/* A line of real thickness, drawn as a quad — GL's own line width is a
 * suggestion drivers may ignore above 1px. */
void rgame_app_draw_line(rgame_app *app, float x1, float y1, float x2, float y2,
                         float thickness, unsigned int color, double z);

/* A filled circle as a fan of `segments` triangles. */
void rgame_app_draw_circle(rgame_app *app, float cx, float cy, float radius, int segments,
                           unsigned int color, double z);

/*
 * Images. Both return 0 without drawing if the image belongs to a *different*
 * app, and 1 otherwise.
 *
 * That check is not pedantry. A GL texture lives in one context and is not
 * shared with another, so drawing another window's image samples nothing and
 * paints a plain white quad — no GL error, nothing in a log, just a white
 * rectangle where the sprite should be. Reporting it lets a binding raise.
 */

/* An image with its top-left at (x, y), at its natural size. */
int rgame_app_draw_image(rgame_app *app, const rgame_image *image, float x, float y,
                         unsigned int color, double z);

/*
 * An image with its top-left at (x, y), scaled independently per axis. A
 * negative scale mirrors the image *inside the same rectangle* rather than
 * about the anchor, so (x, y) is the top-left corner whatever the sign; a zero
 * scale draws nothing.
 */
int rgame_app_draw_image_scaled(rgame_app *app, const rgame_image *image, float x, float y,
                                float scale_x, float scale_y, unsigned int color, double z);

/* An image centred on (cx, cy), rotated clockwise about that centre and
 * uniformly scaled. */
int rgame_app_draw_image_rot(rgame_app *app, const rgame_image *image, float cx, float cy,
                             float angle_degrees, float scale, unsigned int color, double z);

/*
 * The transform, clip and layer stacks. Every push is undone by the same
 * `rgame_app_pop`, so a caller can never pop the wrong one; a push that cannot
 * be honoured (a full stack) is still counted, so pops stay balanced and the
 * drawing comes out untransformed rather than desynchronised.
 *
 * A clip *narrows*: pushing one can only shrink the visible region, never widen
 * it, so a child can never draw outside what its parent allowed. That is what
 * makes split-screen a matter of one push per viewport.
 */
void rgame_app_push_translate(rgame_app *app, float dx, float dy);
void rgame_app_push_rotate(rgame_app *app, float degrees, float pivot_x, float pivot_y);
void rgame_app_push_scale(rgame_app *app, float sx, float sy);
/*
 * Returns 0 without pushing if a recording is open — see the recording section
 * below for why a clip cannot be baked — and 1 otherwise. The other pushes
 * always succeed as far as the caller is concerned.
 */
int rgame_app_push_clip(rgame_app *app, int x, int y, int width, int height);

/*
 * The layer stack: what every subsequent `z` is measured from, until the
 * matching pop. It *replaces* rather than accumulates, and starts at 0, so a
 * caller that never pushes one gets exactly the z it passes.
 *
 * `rgame_app_next_layer_slot` is the other half: one counter per band, reset at
 * the start of each frame, handing out increasing indices. It counts and
 * nothing more — what a band means, and how a slot index becomes a base, is
 * decided a layer up (RGame::Util::Z). Bands outside 0..7 answer 0.
 *
 * Together they are how a scene graph gives each node its own narrow window of
 * z values: the traversal takes the next slot as it reaches a node, so draw
 * order is tree order, and a node's `z:` can only reorder its own drawing.
 */
void rgame_app_push_layer(rgame_app *app, double base);
double rgame_app_layer(rgame_app *app);
unsigned int rgame_app_next_layer_slot(rgame_app *app, int band);

void rgame_app_pop(rgame_app *app);

/*
 * ---------------------------------------------------------------------------
 * Text
 * ---------------------------------------------------------------------------
 *
 * A font is a typeface at **one pixel size**, with a glyph atlas behind it.
 * Two sizes are two fonts. Glyphs are rasterised the first time they are drawn
 * and kept, so the cost is bounded by the character set a game uses rather than
 * by how many strings it draws — a score that changes every frame costs nothing
 * after the first ten digits.
 *
 * Like an image, a font belongs to the app whose GL context its atlas lives in,
 * and either may be destroyed first.
 *
 * Measuring needs no GL and works outside a frame, which is where laying out a
 * menu happens. Drawing, like everything else, is only valid inside `draw`.
 */
typedef struct rgame_font rgame_font;

/*
 * Loads a TrueType font at `pixel_height`. Returns NULL on failure, writing a
 * reason into `err` (which may be NULL). There is no font-*name* lookup and no
 * system font database: a caller names a file. The engine ships one — see
 * lib/rgame/fonts/ — and the Ruby binding defaults to it.
 */
rgame_font *rgame_font_load(rgame_app *app, const char *path, int pixel_height, char *err,
                            size_t err_size);
void rgame_font_destroy(rgame_font *font);

/* The size the font was loaded at, which is also the line height to step by for
 * a second line. */
int rgame_font_height(const rgame_font *font);

/*
 * The width a string would draw at, in pixels, kerning included. `text` is
 * UTF-8; malformed bytes measure as one replacement character each.
 *
 * This and `rgame_app_draw_text` walk the same code, so a label measured and
 * then centred lands where it was measured to.
 */
float rgame_font_measure(const rgame_font *font, const char *text, size_t length);

/*
 * Draws one line of UTF-8 text with its top-left corner at (x, y) — the top of
 * the line box, not the baseline, so a caller places text the way it places
 * everything else.
 *
 * Newlines are not special: this draws one line. A caller wanting two splits
 * the string and steps by `rgame_font_height`.
 *
 * Returns 0 without drawing if the font belongs to a different app, for the
 * same reason images do.
 */
int rgame_app_draw_text(rgame_app *app, rgame_font *font, const char *text, size_t length,
                        float x, float y, unsigned int color, double z);

/*
 * ---------------------------------------------------------------------------
 * Audio
 * ---------------------------------------------------------------------------
 *
 * The one subsystem that touches neither SDL nor OpenGL. It talks to the
 * platform's sound system directly — ALSA or PulseAudio on Linux, found at
 * runtime — so a sound belongs to an `rgame_audio`, not to an `rgame_app`, and
 * none of the window-lifetime rules that govern images and fonts apply here.
 *
 * With no working sound device the engine falls back to a silent one rather
 * than failing: a game with no audio hardware runs, quietly. That is also what
 * lets the whole stack be tested with no sound card.
 *
 * Two kinds of sound:
 *
 *   rgame_sample   short, decoded up front, played many times and overlapping
 *   rgame_song     long, streamed from disk, one at a time, stoppable
 *
 * A three-minute track decoded up front would be some forty megabytes of PCM,
 * and a footstep re-decoded on every step would be silly. Hence two types
 * rather than one with a flag: each has only the operations that make sense for
 * it, so there is no `playing?` on a fire-and-forget effect to answer wrongly.
 *
 * Ogg Vorbis and WAV. Both are read by code the engine ships; nothing has to be
 * installed for sound to work.
 */
typedef struct rgame_audio rgame_audio;
typedef struct rgame_sample rgame_sample;
typedef struct rgame_song rgame_song;

/*
 * Opens the sound device. Returns NULL only if the audio engine could not be
 * created at all, writing a reason into `err` (which may be NULL) — a machine
 * with no sound hardware still gets a working, silent `rgame_audio`.
 */
rgame_audio *rgame_audio_create(char *err, size_t err_size);
void rgame_audio_destroy(rgame_audio *audio);

/*
 * Master volume, applied to everything. 1.0 is unchanged, 0.0 is silence, and
 * above 1.0 amplifies — which can clip, and is the caller's business. Negative
 * values are clamped to zero.
 */
void rgame_audio_set_volume(rgame_audio *audio, float volume);
float rgame_audio_volume(const rgame_audio *audio);

/* Which sound system is in use — "PulseAudio", "ALSA", "Null" and so on. For
 * diagnostics and for tests that want to know whether they are hearing
 * anything. */
const char *rgame_audio_backend(const rgame_audio *audio);

/*
 * A short sound, decoded into memory once. Playing it again while it is still
 * sounding starts a second voice rather than restarting it, which is what makes
 * a rapid-fire effect sound right.
 *
 * There is deliberately no stop and no `playing?`: a one-shot has no single
 * voice to ask about. Volume is per sample rather than per play, and applies to
 * voices already sounding.
 */
rgame_sample *rgame_sample_load(rgame_audio *audio, const char *path, char *err,
                                size_t err_size);
void rgame_sample_destroy(rgame_sample *sample);
void rgame_sample_play(rgame_sample *sample);
void rgame_sample_set_volume(rgame_sample *sample, float volume);
float rgame_sample_volume(const rgame_sample *sample);

/*
 * A long sound, streamed from disk. One voice, so playing it again while it
 * sounds restarts it rather than layering.
 *
 * "Only one song at a time" is *not* enforced here — that is a policy a game
 * decides, and the Ruby layer owns it.
 */
rgame_song *rgame_song_load(rgame_audio *audio, const char *path, char *err, size_t err_size);
void rgame_song_destroy(rgame_song *song);
void rgame_song_play(rgame_song *song, int looping);
void rgame_song_stop(rgame_song *song);
int rgame_song_playing(const rgame_song *song);
/* Whether the last `play` asked for looping. */
int rgame_song_looping(const rgame_song *song);
void rgame_song_set_volume(rgame_song *song, float volume);
float rgame_song_volume(const rgame_song *song);

/*
 * ---------------------------------------------------------------------------
 * Recordings: drawing baked once and replayed cheaply
 * ---------------------------------------------------------------------------
 *
 * A tile layer is a couple of thousand quads that have not changed since the
 * level loaded. Between `rgame_app_begin_record` and `rgame_app_end_record`,
 * draw calls are captured instead of added to the frame; what comes back is the
 * finished, already-batched geometry, which replays as one call per texture
 * however many draws went into it.
 *
 * Recording happens *inside* a frame (there is drawing to capture, after all),
 * and nests nowhere: begin_record returns 0 if the app is not drawing or is
 * already recording.
 *
 * Transforms inside the block are baked in; the transform in effect at replay
 * is applied on top, which is what lets a baked layer scroll under a camera.
 * Clips are not baked — clipping happens when pixels are rasterised, so a clip
 * rectangle captured at one place on screen would be wrong everywhere else the
 * recording is drawn. `rgame_app_push_clip` refuses while recording; clip the
 * replay instead.
 */
typedef struct rgame_recording rgame_recording;

/* Starts capturing. Returns 1 on success, 0 if not drawing or already
 * recording. */
int rgame_app_begin_record(rgame_app *app);

/*
 * Ends capturing and returns the baked result, which the caller owns and must
 * pass to `rgame_recording_free`. Returns NULL if no recording was open or if
 * memory ran out.
 */
rgame_recording *rgame_app_end_record(rgame_app *app);

/* Ends capturing and throws the result away — for unwinding when whatever was
 * being recorded failed part-way through. */
void rgame_app_cancel_record(rgame_app *app);

void rgame_recording_free(rgame_recording *recording);

/*
 * Replays a recording with its origin at (x, y), at `z`, tinted by `color`
 * (0xFFFFFFFF leaves the recorded colours alone). Unlike the layer this
 * replaces, a recording is not limited to drawing white.
 */
void rgame_app_draw_recording(rgame_app *app, const rgame_recording *recording, float x,
                              float y, unsigned int color, double z);

#ifdef __cplusplus
}
#endif

#endif /* RGAME_CORE_H */
