# Makefile for Keel Autonomous Maritime VTS & COLREGs Kernel

CC ?= clang
CFLAGS ?= -O3 -Wall -Wextra -Werror -pedantic -std=c11 -fPIC
AR ?= ar
ARFLAGS ?= rcs

SRC_DIR := src
C_SRC_DIR := $(SRC_DIR)/c_fastpath
BUILD_DIR := build
BIN_DIR := bin
TEST_DIR := test
BENCH_DIR := benchmarks

C_SRCS := $(C_SRC_DIR)/keel_fastpath.c $(C_SRC_DIR)/keel_c_api.c
C_OBJS := $(BUILD_DIR)/keel_fastpath.o $(BUILD_DIR)/keel_c_api.o
STATIC_LIB := $(BUILD_DIR)/libkeel_fastpath.a
TEST_BIN := $(BIN_DIR)/keel_test
BENCH_BIN := $(BIN_DIR)/fastpath_bench

.PHONY: all clean test bench dirs

all: dirs $(STATIC_LIB) $(TEST_BIN)

dirs:
	@mkdir -p $(BUILD_DIR) $(BIN_DIR)

$(BUILD_DIR)/%.o: $(C_SRC_DIR)/%.c
	$(CC) $(CFLAGS) -I$(C_SRC_DIR) -c $< -o $@

$(STATIC_LIB): $(C_OBJS)
	$(AR) $(ARFLAGS) $@ $^

$(TEST_BIN): dirs $(STATIC_LIB) $(TEST_DIR)/c_test_runner.c
	$(CC) $(CFLAGS) -I$(C_SRC_DIR) $(TEST_DIR)/c_test_runner.c $(STATIC_LIB) -lm -o $@

test: $(TEST_BIN)
	@./$(TEST_BIN)

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR) *.o *.a
