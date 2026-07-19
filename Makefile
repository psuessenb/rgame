CC ?= gcc
CFLAGS ?= -std=c17 -Wall -Wextra -g -fPIC
INCLUDES := -Iinclude

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

.PHONY: all run test clean

all: $(APP_BIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(CORE_OBJ): src/core.c src/frame_loop.h include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(FRAME_LOOP_OBJ): src/frame_loop.c src/frame_loop.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(CORE_LIB): $(CORE_OBJ) $(FRAME_LOOP_OBJ)
	ar rcs $@ $^

$(APP_OBJ): src/main.c include/rgame/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(APP_BIN): $(APP_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(APP_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS)

$(TEST_OBJ): test/test_frame_loop.c src/frame_loop.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(CHECK_CFLAGS) -c $< -o $@

$(TEST_BIN): $(TEST_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(TEST_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS) $(CHECK_LIBS)

run: all
	./$(APP_BIN)

test: $(TEST_BIN)
	./$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR)
