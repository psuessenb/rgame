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

.PHONY: all run test clean ext ext-clean

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

# Ruby C extension. mkmf generates ext/rgame/Makefile from extconf.rb, which
# then builds rgame.so out of every .c in that directory. Needs `ruby` on PATH
# (installed via mise — see README).
ext: $(EXT_DIR)/Makefile
	$(MAKE) -C $(EXT_DIR)

$(EXT_DIR)/Makefile: $(EXT_DIR)/extconf.rb
	cd $(EXT_DIR) && ruby extconf.rb

ext-clean:
	[ -f $(EXT_DIR)/Makefile ] && $(MAKE) -C $(EXT_DIR) distclean || true
	rm -f $(EXT_DIR)/Makefile

clean: ext-clean
	rm -rf $(BUILD_DIR)
