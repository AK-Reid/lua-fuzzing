
###Lua Setup and Reproducing the Bug
Download Lua 5.5.0 Source code: https://www.lua.org/ftp/
Put the folder one level up from this repo dir.

Run Standalone Bug, no Fuzzing, Pure Lua
```
cd lua-5.5.0/src
make clean
make -j$(nproc) lua CC=gcc MYCFLAGS="-g -O1"
cd ../..
lua-5.5.0/src/lua fuzzing/bug_repro.lu
```

###Fuzzer Setup
Install Dependencies:
Ubuntu
```
sudo apt update
sudo apt install -y clang gcc make
```

MacOS
```
brew install llvm gcc make
export PATH="$(brew --prefix llvm)/bin:$PATH
export LDFLAGS="-L$(brew --prefix llvm)/lib"
export CPPFLAGS="-I$(brew --prefix llvm)/include"
```
Verifier clang is at least version 14
```
clang --version
```
Run the provided script,
```
chmod +x deploy/run.sh
./run.sh
```

Or if you want to run the steps individually.

Build Lua as a Static Library with Address Sanitizer and Fuzzer Instrumentation
```
cd lua-5.5.0/src
make clean
make -j$(nproc) liblua.a \
    CC=clang \
    MYCFLAGS="-fsanitize=address,fuzzer-no-link -g -O1"
cd ../..
```
Compiler Fuzzer Harness
```
LUASRC=lua-5.5.0/src

clang -fsanitize=address,fuzzer -g -O1 \
    -I$LUASRC \
    fuzzing/lua_b_str2int_fuzz.c \
    $LUASRC/liblua.a \
    -lm \
    -o fuzzing/lua_b_str2int_fuzz
```
Run Fuzzer!

```
mkdir -p fuzzing/crashes_b_str2int

./fuzzing/lua_b_str2int_fuzz \
    -max_total_time=60 \
    -artifact_prefix=./fuzzing/crashes_b_str2int/ \
    -print_final_stats=1
```
