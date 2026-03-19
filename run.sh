#!/bin/bash
# Builds Lua, compiles the fuzzer harness, and runs both the standalone
# Requires: clang (with libFuzzer), gcc, make

set -e

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
LUA_SRC="$DEPLOY_DIR/../lua-5.5.0/src"

echo "Build plain Lua binary (for bug_repro.lua)"
make -C "$LUA_SRC" clean
make -j"$(nproc)" -C "$LUA_SRC" lua CC=gcc MYCFLAGS="-g -O1"

echo ""
echo "Run standalone bug reproduction"
"$LUA_SRC/lua" "$DEPLOY_DIR/bug_repro.lua" || true

echo ""
echo "Build Lua static library (ASan + fuzzer instrumentation)"
make -C "$LUA_SRC" clean
make -j"$(nproc)" -C "$LUA_SRC" liblua.a \
    CC=clang \
    MYCFLAGS="-fsanitize=address,fuzzer-no-link -g -O1"

echo ""
echo "Compile fuzzer harness"
clang -fsanitize=address,fuzzer -g -O1 \
    -I"$LUA_SRC" \
    "$DEPLOY_DIR/lua_b_str2int_fuzz.c" \
    "$LUA_SRC/liblua.a" \
    -lm \
    -o "$DEPLOY_DIR/lua_b_str2int_fuzz"

echo ""
echo "Run fuzzer(60s limit)"
mkdir -p "$DEPLOY_DIR/crashes"
"$DEPLOY_DIR/lua_b_str2int_fuzz" \
    -max_total_time=60 \
    -artifact_prefix="$DEPLOY_DIR/crashes/" \
    -print_final_stats=1
