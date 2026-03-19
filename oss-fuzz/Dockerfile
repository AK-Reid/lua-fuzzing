FROM gcr.io/oss-fuzz-base/base-builder
RUN git clone https://github.com/ligurio/lunapark testdir
WORKDIR testdir
COPY build.sh $SRC/testdir/
WORKDIR $SRC
COPY build.sh $SRC/
COPY fuzz_lua.c $SRC/
COPY fuzz_lua_stringtonumber.c $SRC/
COPY corpus_dir $SRC/corpus_dir
