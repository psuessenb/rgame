CC ?= gcc
CFLAGS ?= -std=c17 -Wall -Wextra -g -fPIC

# The engine sources live in ext/rgame/ (the Ruby extension directory) so that
# `gem install` can build them via extconf.rb without reaching outside ext/.
# This Makefile builds those same sources into a standalone binary.
EXT_DIR := ext/rgame
INCLUDES := -I$(EXT_DIR)/include

SDL_CFLAGS := $(shell pkg-config --cflags sdl2)
SDL_LIBS := $(shell pkg-config --libs sdl2)
GL_LIBS := -lGL
MATH_LIBS := -lm

CHECK_CFLAGS := $(shell pkg-config --cflags check)
CHECK_LIBS := $(shell pkg-config --libs check)

BUILD_DIR := build

CORE_OBJ := $(BUILD_DIR)/core.o
FRAME_LOOP_OBJ := $(BUILD_DIR)/frame_loop.o
CORE_LIB := $(BUILD_DIR)/librgame_core.a
APP_OBJ := $(BUILD_DIR)/main.o
APP_BIN := $(BUILD_DIR)/rgame

TEST_OBJ := $(BUILD_DIR)/test_frame_loop.o
TEST_BIN := $(BUILD_DIR)/test_frame_loop

EXT_UTIL_DIR := ext/rgame_util
EXT_UTIL_SO := $(EXT_UTIL_DIR)/util_ext.so
LIB_UTIL_SO := lib/rgame/util_ext.so

.PHONY: all run test clean ext ext-util ext-clean

all: $(APP_BIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(CORE_OBJ): $(EXT_DIR)/core.c $(EXT_DIR)/frame_loop.h $(EXT_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(FRAME_LOOP_OBJ): $(EXT_DIR)/frame_loop.c $(EXT_DIR)/frame_loop.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(CORE_LIB): $(CORE_OBJ) $(FRAME_LOOP_OBJ)
	ar rcs $@ $^

$(APP_OBJ): src/main.c $(EXT_DIR)/include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(APP_BIN): $(APP_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(APP_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS)

$(TEST_OBJ): test/test_frame_loop.c $(EXT_DIR)/frame_loop.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(EXT_DIR) $(CHECK_CFLAGS) -c $< -o $@

$(TEST_BIN): $(TEST_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(TEST_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS) $(CHECK_LIBS)

run: all
	./$(APP_BIN)

test: $(TEST_BIN)
	./$(TEST_BIN)

# Ruby C extensions. mkmf generates each ext dir's Makefile from its extconf.rb.
# `make ext` builds both: the SDL/GL engine (ext/rgame -> rgame.so) and the
# pure-data util extension (ext/rgame_util -> util_ext.so). Needs `ruby` on PATH
# (installed via mise — see README).
ext: ext-util $(EXT_DIR)/Makefile
	$(MAKE) -C $(EXT_DIR)

$(EXT_DIR)/Makefile: $(EXT_DIR)/extconf.rb
	cd $(EXT_DIR) && ruby extconf.rb

# util extension: build util_ext.so, then copy it onto the Ruby load path at
# lib/rgame/util_ext.so, which is where `require "rgame/util_ext"` looks for it
# (mirrors how rake-compiler installs a compiled ext into lib/<gem>/).
ext-util: $(LIB_UTIL_SO)

$(LIB_UTIL_SO): $(EXT_UTIL_SO)
	cp $(EXT_UTIL_SO) $@

$(EXT_UTIL_SO): $(EXT_UTIL_DIR)/tensor.c $(EXT_UTIL_DIR)/Makefile
	$(MAKE) -C $(EXT_UTIL_DIR)

$(EXT_UTIL_DIR)/Makefile: $(EXT_UTIL_DIR)/extconf.rb
	cd $(EXT_UTIL_DIR) && ruby extconf.rb

ext-clean:
	[ -f $(EXT_DIR)/Makefile ] && $(MAKE) -C $(EXT_DIR) distclean || true
	[ -f $(EXT_UTIL_DIR)/Makefile ] && $(MAKE) -C $(EXT_UTIL_DIR) distclean || true
	rm -f $(EXT_DIR)/Makefile $(EXT_UTIL_DIR)/Makefile $(LIB_UTIL_SO)

clean: ext-clean
	rm -rf $(BUILD_DIR)
