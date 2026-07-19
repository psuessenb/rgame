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
CORE_LIB := $(BUILD_DIR)/libctest_core.a
APP_OBJ := $(BUILD_DIR)/main.o
APP_BIN := $(BUILD_DIR)/ctest

TEST_OBJ := $(BUILD_DIR)/test_core.o
TEST_BIN := $(BUILD_DIR)/test_core

.PHONY: all run test clean

all: $(APP_BIN)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(CORE_OBJ): src/core.c src/internal.h include/ctest/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(CORE_LIB): $(CORE_OBJ)
	ar rcs $@ $^

$(APP_OBJ): src/main.c include/ctest/core.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SDL_CFLAGS) -c $< -o $@

$(APP_BIN): $(APP_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(APP_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS)

$(TEST_OBJ): test/test_core.c src/internal.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(CHECK_CFLAGS) -c $< -o $@

$(TEST_BIN): $(TEST_OBJ) $(CORE_LIB)
	$(CC) $(CFLAGS) -o $@ $(TEST_OBJ) $(CORE_LIB) $(SDL_LIBS) $(GL_LIBS) $(MATH_LIBS) $(CHECK_LIBS)

run: all
	./$(APP_BIN)

test: $(TEST_BIN)
	./$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR)
