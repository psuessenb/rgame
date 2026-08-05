CC ?= gcc
CFLAGS ?= -std=c17 -Wall -Wextra -g -fPIC

# The engine sources live in ext/rgame_core/ (a Ruby extension directory) so
# that `gem install` can build them via extconf.rb without reaching outside ext/.
# This Makefile builds those same sources into a standalone binary.
EXT_CORE_DIR := ext/rgame_core
EXT_UTIL_DIR := ext/rgame_util
# Util's colour header is header-only; see ext/rgame_core/extconf.rb.
INCLUDES := -I$(EXT_CORE_DIR)/include -I$(EXT_UTIL_DIR)

SDL_CFLAGS := $(shell pkg-config --cflags sdl2)
SDL_LIBS := $(shell pkg-config --libs sdl2)
GL_LIBS := -lGL
MATH_LIBS := -lm

CHECK_CFLAGS := $(shell pkg-config --cflags check)
CHECK_LIBS := $(shell pkg-config --libs check)

BUILD_DIR := build

# Engine objects, named after their sources in $(EXT_CORE_DIR).
APP_OBJ := $(BUILD_DIR)/app.o
FRAME_LOOP_OBJ := $(BUILD_DIR)/frame_loop.o
DEVICE_SLOTS_OBJ := $(BUILD_DIR)/device_slots.o
INPUT_OBJ := $(BUILD_DIR)/input.o
TRANSFORM_OBJ := $(BUILD_DIR)/transform.o
CLIP_OBJ := $(BUILD_DIR)/clip.o
DRAW_QUEUE_OBJ := $(BUILD_DIR)/draw_queue.o
CANVAS_OBJ := $(BUILD_DIR)/canvas.o
TEXTURE_OBJ := $(BUILD_DIR)/texture.o
PRIMITIVES_OBJ := $(BUILD_DIR)/primitives.o
GL_BACKEND_OBJ := $(BUILD_DIR)/gl_backend.o
RECORDING_OBJ := $(BUILD_DIR)/recording.o
ATLAS_OBJ := $(BUILD_DIR)/atlas.o
GLYPH_CACHE_OBJ := $(BUILD_DIR)/glyph_cache.o
FONT_OBJ := $(BUILD_DIR)/font.o
FONT_ATLAS_OBJ := $(BUILD_DIR)/font_atlas.o
IMAGE_OBJ := $(BUILD_DIR)/image.o
# Every vendored single-header library gets one implementation TU named
# stb_<name>_impl.c; the pattern rule below builds all of them the same way.
VENDOR_OBJS := $(BUILD_DIR)/stb_image_impl.o $(BUILD_DIR)/stb_truetype_impl.o
BACKEND_OBJ := $(BUILD_DIR)/backend.o
# Util is a separate extension, but its pure modules are Check-tested too.
COLOR_OBJ := $(BUILD_DIR)/color.o
GAMEPAD_OBJ := $(BUILD_DIR)/gamepad.o
CORE_LIB := $(BUILD_DIR)/librgame_core.a

# The standalone binary and its entry point (src/main.c).
MAIN_OBJ := $(BUILD_DIR)/main.o
MAIN_BIN := $(BUILD_DIR)/rgame

# One Check binary for every layer-1 suite: each test/test_<x>.c exposes a
# Suite, declared in test/suites.h, that test_main.c runs. Adding a module
# means adding to TEST_OBJS, not adding another binary.
TEST_OBJS := $(BUILD_DIR)/test_main.o \
             $(BUILD_DIR)/test_frame_loop.o \
             $(BUILD_DIR)/test_device_slots.o \
             $(BUILD_DIR)/test_input.o \
             $(BUILD_DIR)/test_color.o \
             $(BUILD_DIR)/test_transform.o \
             $(BUILD_DIR)/test_clip.o \
             $(BUILD_DIR)/test_draw_queue.o \
             $(BUILD_DIR)/test_canvas.o \
             $(BUILD_DIR)/test_backend.o \
             $(BUILD_DIR)/test_texture.o \
             $(BUILD_DIR)/test_primitives.o \
             $(BUILD_DIR)/test_recording.o \
             $(BUILD_DIR)/test_atlas.o \
             $(BUILD_DIR)/test_glyph_cache.o \
             $(BUILD_DIR)/test_font.o \
             $(BUILD_DIR)/recording_backend.o
TEST_BIN := $(BUILD_DIR)/test_rgame

EXT_CORE_SO := $(EXT_CORE_DIR)/core_ext.so
EXT_UTIL_SO := $(EXT_UTIL_DIR)/util_ext.so

LIB_CORE_SO := lib/rgame/core_ext.so
LIB_UTIL_SO := lib/rgame/util_ext.so

.PHONY: all run test clean ext ext-core ext-util ext-clean

all: $(MAIN_BIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(APP_OBJ): $(EXT_CORE_DIR)/app.c $(EXT_CORE_DIR)/frame_loop.h $(EXT_CORE_DIR)/input.h \
            $(EXT_CORE_DIR)/gamepad.h $(EXT_CORE_DIR)/canvas.h $(EXT_CORE_DIR)/primitives.h \
            $(EXT_CORE_DIR)/gl_backend.h $(EXT_CORE_DIR)/image_internal.h \
            $(EXT_CORE_DIR)/font_internal.h \
            $(EXT_CORE_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(FRAME_LOOP_OBJ): $(EXT_CORE_DIR)/frame_loop.c $(EXT_CORE_DIR)/frame_loop.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(DEVICE_SLOTS_OBJ): $(EXT_CORE_DIR)/device_slots.c $(EXT_CORE_DIR)/device_slots.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(INPUT_OBJ): $(EXT_CORE_DIR)/input.c $(EXT_CORE_DIR)/input.h $(EXT_CORE_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(GAMEPAD_OBJ): $(EXT_CORE_DIR)/gamepad.c $(EXT_CORE_DIR)/gamepad.h $(EXT_CORE_DIR)/input.h $(EXT_CORE_DIR)/device_slots.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(TRANSFORM_OBJ): $(EXT_CORE_DIR)/transform.c $(EXT_CORE_DIR)/transform.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(CLIP_OBJ): $(EXT_CORE_DIR)/clip.c $(EXT_CORE_DIR)/clip.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(DRAW_QUEUE_OBJ): $(EXT_CORE_DIR)/draw_queue.c $(EXT_CORE_DIR)/draw_queue.h \
                   $(EXT_CORE_DIR)/clip.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(BACKEND_OBJ): $(EXT_CORE_DIR)/backend.c $(EXT_CORE_DIR)/backend.h \
                $(EXT_CORE_DIR)/draw_queue.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Test-only: the recording backend the Check suite substitutes for real GL.
$(BUILD_DIR)/recording_backend.o: test/support/recording_backend.c \
                                  test/support/recording_backend.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(EXT_CORE_DIR) -I$(EXT_UTIL_DIR) -Itest/support $(CHECK_CFLAGS) -c $< -o $@

$(CANVAS_OBJ): $(EXT_CORE_DIR)/canvas.c $(EXT_CORE_DIR)/canvas.h \
               $(EXT_CORE_DIR)/draw_queue.h $(EXT_CORE_DIR)/transform.h \
               $(EXT_CORE_DIR)/clip.h $(EXT_CORE_DIR)/recording.h \
               $(EXT_UTIL_DIR)/color.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(TEXTURE_OBJ): $(EXT_CORE_DIR)/texture.c $(EXT_CORE_DIR)/texture.h \
                $(EXT_CORE_DIR)/clip.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(PRIMITIVES_OBJ): $(EXT_CORE_DIR)/primitives.c $(EXT_CORE_DIR)/primitives.h \
                   $(EXT_CORE_DIR)/canvas.h $(EXT_CORE_DIR)/texture.h \
                   $(EXT_UTIL_DIR)/color.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(ATLAS_OBJ): $(EXT_CORE_DIR)/atlas.c $(EXT_CORE_DIR)/atlas.h \
              $(EXT_CORE_DIR)/clip.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(GLYPH_CACHE_OBJ): $(EXT_CORE_DIR)/glyph_cache.c $(EXT_CORE_DIR)/glyph_cache.h \
                    $(EXT_CORE_DIR)/clip.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Needs the extension directory on the include path for "vendor/stb_truetype.h".
$(FONT_OBJ): $(EXT_CORE_DIR)/font.c $(EXT_CORE_DIR)/font.h \
             $(EXT_CORE_DIR)/glyph_cache.h $(EXT_CORE_DIR)/vendor/stb_truetype.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -I$(EXT_CORE_DIR) -c $< -o $@

$(FONT_ATLAS_OBJ): $(EXT_CORE_DIR)/font_atlas.c $(EXT_CORE_DIR)/font_internal.h \
                   $(EXT_CORE_DIR)/font.h $(EXT_CORE_DIR)/atlas.h \
                   $(EXT_CORE_DIR)/glyph_cache.h $(EXT_CORE_DIR)/app_gl.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -I$(EXT_CORE_DIR) $(SDL_CFLAGS) -c $< -o $@

$(RECORDING_OBJ): $(EXT_CORE_DIR)/recording.c $(EXT_CORE_DIR)/recording.h \
                  $(EXT_CORE_DIR)/draw_queue.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(GL_BACKEND_OBJ): $(EXT_CORE_DIR)/gl_backend.c $(EXT_CORE_DIR)/gl_backend.h \
                   $(EXT_CORE_DIR)/backend.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(IMAGE_OBJ): $(EXT_CORE_DIR)/image.c $(EXT_CORE_DIR)/texture.h $(EXT_CORE_DIR)/app_gl.h \
              $(EXT_CORE_DIR)/vendor/stb_image.h $(EXT_CORE_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -I$(EXT_CORE_DIR) $(SDL_CFLAGS) -c $< -o $@

# The vendored translation units, and the only place warnings are relaxed.
# stb's headers are public-domain third-party code that does not survive
# -Wall -Wextra; carving out exactly these files keeps everything we wrote
# clean. One rule rather than one per library, so the second one cannot drift
# from the first. See ext/rgame_core/vendor/README.md.
$(BUILD_DIR)/stb_%_impl.o: $(EXT_CORE_DIR)/stb_%_impl.c $(EXT_CORE_DIR)/vendor/stb_%.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -w -I$(EXT_CORE_DIR) -c $< -o $@

$(CORE_LIB): $(APP_OBJ) $(FRAME_LOOP_OBJ) $(DEVICE_SLOTS_OBJ) $(INPUT_OBJ) $(GAMEPAD_OBJ) \
             $(TRANSFORM_OBJ) $(CLIP_OBJ) $(DRAW_QUEUE_OBJ) \
             $(CANVAS_OBJ) $(BACKEND_OBJ) $(TEXTURE_OBJ) $(PRIMITIVES_OBJ) \
             $(RECORDING_OBJ) $(ATLAS_OBJ) $(GLYPH_CACHE_OBJ) $(FONT_OBJ) $(FONT_ATLAS_OBJ) $(GL_BACKEND_OBJ) $(IMAGE_OBJ) $(VENDOR_OBJS)
	ar rcs $@ $^

$(MAIN_OBJ): src/main.c $(EXT_CORE_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(MAIN_BIN): $(MAIN_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(MAIN_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS)

$(COLOR_OBJ): $(EXT_UTIL_DIR)/color.c $(EXT_UTIL_DIR)/color.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/test_%.o: test/test_%.c test/suites.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(EXT_CORE_DIR) -I$(EXT_CORE_DIR)/include -I$(EXT_UTIL_DIR) -Itest \
	       -Itest/support $(CHECK_CFLAGS) -c $< -o $@

$(TEST_BIN): $(TEST_OBJS) $(CORE_LIB) $(COLOR_OBJ)
	$(CC) $(CFLAGS) -o $@ $(TEST_OBJS) $(CORE_LIB) $(COLOR_OBJ) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS) $(CHECK_LIBS)

run: all
	./$(MAIN_BIN)

test: $(TEST_BIN)
	./$(TEST_BIN)

# Ruby C extensions. mkmf generates each ext dir's Makefile from its extconf.rb.
# There are two, split by dependency — see CLAUDE.md:
#
#   ext/rgame_core -> core_ext.so       RGame::Core; links SDL2 + OpenGL
#   ext/rgame_util     -> util_ext.so       RGame::Util; links neither
#
# Each is then copied to lib/rgame/, which is where `require "rgame/<x>_ext"`
# finds it (mirrors how rake-compiler installs a compiled ext into lib/<gem>/).
# Needs `ruby` on PATH (installed via mise — see README).
ext: ext-util ext-core

# core extension: the SDL/GL engine. Note it depends on the same app.c /
# frame_loop.c that the standalone binary above builds — one copy of the source,
# two build systems.
ext-core: $(LIB_CORE_SO)

$(LIB_CORE_SO): $(EXT_CORE_SO)
	cp $(EXT_CORE_SO) $@

$(EXT_CORE_SO): $(EXT_CORE_DIR)/core_ext.c $(EXT_CORE_DIR)/app.c \
                $(EXT_CORE_DIR)/frame_loop.c $(EXT_CORE_DIR)/Makefile
	$(MAKE) -C $(EXT_CORE_DIR)

# Regenerate when a source is *added*, not just when extconf.rb changes: mkmf
# bakes the object list in at generation time, so a new .c would otherwise be
# silently left out and surface as an undefined symbol at require time.
$(EXT_CORE_DIR)/Makefile: $(EXT_CORE_DIR)/extconf.rb $(wildcard $(EXT_CORE_DIR)/*.c)
	cd $(EXT_CORE_DIR) && ruby extconf.rb

# util extension: pure data, no graphics libraries linked in.
ext-util: $(LIB_UTIL_SO)

$(LIB_UTIL_SO): $(EXT_UTIL_SO)
	cp $(EXT_UTIL_SO) $@

$(EXT_UTIL_SO): $(EXT_UTIL_DIR)/tensor.c $(EXT_UTIL_DIR)/color.c \
                $(EXT_UTIL_DIR)/color_ext.c $(EXT_UTIL_DIR)/util_ext.c \
                $(EXT_UTIL_DIR)/Makefile
	$(MAKE) -C $(EXT_UTIL_DIR)

$(EXT_UTIL_DIR)/Makefile: $(EXT_UTIL_DIR)/extconf.rb $(wildcard $(EXT_UTIL_DIR)/*.c)
	cd $(EXT_UTIL_DIR) && ruby extconf.rb

ext-clean:
	[ -f $(EXT_CORE_DIR)/Makefile ] && $(MAKE) -C $(EXT_CORE_DIR) distclean || true
	[ -f $(EXT_UTIL_DIR)/Makefile ] && $(MAKE) -C $(EXT_UTIL_DIR) distclean || true
	rm -f $(EXT_CORE_DIR)/Makefile $(EXT_UTIL_DIR)/Makefile
	rm -f $(LIB_CORE_SO) $(LIB_UTIL_SO)

clean: ext-clean
	rm -rf $(BUILD_DIR)
