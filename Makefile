CC ?= gcc
CFLAGS ?= -std=c17 -Wall -Wextra -g -fPIC

# The engine sources live in ext/rgame_core/ (a Ruby extension directory) so
# that `gem install` can build them via extconf.rb without reaching outside ext/.
# This Makefile builds those same sources into a standalone binary.
EXT_CORE_DIR := ext/rgame_core
INCLUDES := -I$(EXT_CORE_DIR)/include

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
CORE_LIB := $(BUILD_DIR)/librgame_core.a

# The standalone binary and its entry point (src/main.c).
MAIN_OBJ := $(BUILD_DIR)/main.o
MAIN_BIN := $(BUILD_DIR)/rgame

TEST_OBJ := $(BUILD_DIR)/test_frame_loop.o
TEST_BIN := $(BUILD_DIR)/test_frame_loop

EXT_UTIL_DIR := ext/rgame_util

EXT_CORE_SO := $(EXT_CORE_DIR)/core_ext.so
EXT_UTIL_SO := $(EXT_UTIL_DIR)/util_ext.so

LIB_CORE_SO := lib/rgame/core_ext.so
LIB_UTIL_SO := lib/rgame/util_ext.so

.PHONY: all run test clean ext ext-core ext-util ext-clean

all: $(MAIN_BIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(APP_OBJ): $(EXT_CORE_DIR)/app.c $(EXT_CORE_DIR)/frame_loop.h $(EXT_CORE_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(FRAME_LOOP_OBJ): $(EXT_CORE_DIR)/frame_loop.c $(EXT_CORE_DIR)/frame_loop.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(CORE_LIB): $(APP_OBJ) $(FRAME_LOOP_OBJ)
	ar rcs $@ $^

$(MAIN_OBJ): src/main.c $(EXT_CORE_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(MAIN_BIN): $(MAIN_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(MAIN_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS)

$(TEST_OBJ): test/test_frame_loop.c $(EXT_CORE_DIR)/frame_loop.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(EXT_CORE_DIR) $(CHECK_CFLAGS) -c $< -o $@

$(TEST_BIN): $(TEST_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(TEST_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS) $(CHECK_LIBS)

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

$(EXT_CORE_DIR)/Makefile: $(EXT_CORE_DIR)/extconf.rb
	cd $(EXT_CORE_DIR) && ruby extconf.rb

# util extension: pure data, no graphics libraries linked in.
ext-util: $(LIB_UTIL_SO)

$(LIB_UTIL_SO): $(EXT_UTIL_SO)
	cp $(EXT_UTIL_SO) $@

$(EXT_UTIL_SO): $(EXT_UTIL_DIR)/tensor.c $(EXT_UTIL_DIR)/Makefile
	$(MAKE) -C $(EXT_UTIL_DIR)

$(EXT_UTIL_DIR)/Makefile: $(EXT_UTIL_DIR)/extconf.rb
	cd $(EXT_UTIL_DIR) && ruby extconf.rb

ext-clean:
	[ -f $(EXT_CORE_DIR)/Makefile ] && $(MAKE) -C $(EXT_CORE_DIR) distclean || true
	[ -f $(EXT_UTIL_DIR)/Makefile ] && $(MAKE) -C $(EXT_UTIL_DIR) distclean || true
	rm -f $(EXT_CORE_DIR)/Makefile $(EXT_UTIL_DIR)/Makefile
	rm -f $(LIB_CORE_SO) $(LIB_UTIL_SO)

clean: ext-clean
	rm -rf $(BUILD_DIR)
