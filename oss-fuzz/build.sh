#!/bin/bash -eu

# For some reason the linker will complain if address sanitizer is not used
# in introspector builds.
if [ "$SANITIZER" == "introspector" ]; then
  export CFLAGS="${CFLAGS} -fsanitize=address"
  export CXXFLAGS="${CXXFLAGS} -fsanitize=address"
fi

PACKAGES="build-essential ninja-build cmake make"
if [ "$ARCHITECTURE" = "i386" ]; then
    PACKAGES="$PACKAGES zlib1g-dev:i386 libreadline-dev:i386 libunwind-dev:i386"
elif [ "$ARCHITECTURE" = "aarch64" ]; then
    PACKAGES="$PACKAGES zlib1g-dev:arm64 libreadline-dev:arm64 libunwind-dev:arm64"
else
    PACKAGES="$PACKAGES zlib1g-dev libreadline-dev libunwind-dev"
fi
apt-get update
apt-get install -y $PACKAGES

# For fuzz-introspector, exclude all functions in the tests directory,
# libprotobuf-mutator and protobuf source code.
# See https://github.com/ossf/fuzz-introspector/blob/main/doc/Config.md#code-exclusion-from-the-report
export FUZZ_INTROSPECTOR_CONFIG=$SRC/fuzz_introspector_exclusion.config
cat > $FUZZ_INTROSPECTOR_CONFIG <<EOF
FILES_TO_AVOID
testdir/build/tests/capi/external.protobuf_mutator
testdir/build/tests/capi/luaL_loadbuffer_proto/
EOF

cd $SRC/testdir

# Avoid compilation issue due to some undefined references. They are defined in
# libc++ and used by Centipede so -lc++ needs to come after centipede's lib.
if [[ $FUZZING_ENGINE == centipede ]]
then
    sed -i \
        '/$ENV{LIB_FUZZING_ENGINE}/a \ \ \ \ \ \ \ \ -lc++' \
        tests/capi/CMakeLists.txt
fi

# Clean up potentially persistent build directory.
[[ -e $SRC/testdir/build ]] && rm -rf $SRC/testdir/build

case $SANITIZER in
  address) SANITIZERS_ARGS="-DENABLE_ASAN=ON" ;;
  undefined) SANITIZERS_ARGS="-DENABLE_UBSAN=ON" ;;
  *) SANITIZERS_ARGS="" ;;
esac

export LSAN_OPTIONS="verbosity=1:log_threads=1"

# Workaround for a LeakSanitizer crashes,
# see https://github.com/google/oss-fuzz/issues/11798.
if [ "$ARCHITECTURE" = "aarch64" ]; then
    export ASAN_OPTIONS=detect_leaks=0
fi

: ${LD:="${CXX}"}
: ${LDFLAGS:="${CXXFLAGS}"}  # to make sure we link with sanitizer runtime

cmake_args=(
    -DUSE_LUA=ON
    -DOSS_FUZZ=ON
    $SANITIZERS_ARGS

    # C compiler
    -DCMAKE_C_COMPILER="${CC}"
    -DCMAKE_C_FLAGS="${CFLAGS}"

    # C++ compiler
    -DCMAKE_CXX_COMPILER="${CXX}"
    -DCMAKE_CXX_FLAGS="${CXXFLAGS}"

    # Linker
    -DCMAKE_LINKER="${LD}"
    -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}"
    -DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}"
    -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}"
)

# To deal with a host filesystem from inside of container.
git config --global --add safe.directory '*'

# Build the project and fuzzers.
[[ -e build ]] && rm -rf build
cmake "${cmake_args[@]}" -S . -B build -G Ninja
cmake --build build --parallel --verbose

LUALIB_PATH="$SRC/testdir/build/lua-master/source/"
$CC $CFLAGS -I$LUALIB_PATH -c $SRC/fuzz_lua.c -o fuzz_lua.o
$CXX $CXXFLAGS $LIB_FUZZING_ENGINE fuzz_lua.o -o $OUT/fuzz_lua $LUALIB_PATH/liblua.a
$CC $CFLAGS -I$LUALIB_PATH -c $SRC/fuzz_lua_stringtonumber.c -o fuzz_lua_stringtonumber.o
$CXX $CXXFLAGS $LIB_FUZZING_ENGINE fuzz_lua_stringtonumber.o -o $OUT/fuzz_lua_stringtonumber $LUALIB_PATH/liblua.a

# If the dict filename is the same as your target binary name
# (i.e. `%fuzz_target%.dict`), it will be automatically used.
# If the name is different (e.g. because it is shared by several
# targets), specify this in .options file.
#cp corpus_dir/*.dict corpus_dir/*.options $OUT/

# Add dict and seed corpus for fuzz_lua_stringtonumber
if [[ -f $SRC/corpus_dir/fuzz_lua_stringtonumber.dict ]]; then
  cp $SRC/corpus_dir/fuzz_lua_stringtonumber.dict $OUT/
fi
if [[ -d $SRC/corpus_dir/fuzz_lua_stringtonumber ]]; then
  find $SRC/corpus_dir/fuzz_lua_stringtonumber -maxdepth 1 -type f \
    | zip -@ -j $OUT/fuzz_lua_stringtonumber_seed_corpus.zip
fi
