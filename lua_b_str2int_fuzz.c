/*
 lua_b_str2int_fuzz.c
 
  Fuzzer harness targeting the silent overflow in Lua's b_str2int,
  reachable via tonumber(s, 10).
  Based off of : https://github.com/ligurio/lunapark/blob/master/tests/capi/lua_stringtonumber_test.c
  
  Oracle — differential test (base 10):
    Path A: lua_stringtonumber(s)  // has overflow guard, falls back to float when value exceeds int64
    Path B: tonumber(s, 10)        // goes through b_str2int, no overflow guard
                                     
 
    Both paths parse the same decimal string. If Path A returns a float
    and Path B returns an integer, then we have a contradiction, which 
    must be a bug. __builtin_trap() converts that contradiction into a 
    real crash that libFuzzer can utilize. 
 */

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define lua_c
#include "lprefix.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size == 0) return 0;

    char *str = (char *)malloc(size + 1);
    if (!str) return 0;
    memcpy(str, data, size);
    str[size] = '\0';

    lua_State *L = luaL_newstate();
    if (!L) { free(str); return 0; }

    /* Open only the base library, all we need is tonumber without full stdlib overhead */
    luaL_requiref(L, "_G", luaopen_base, 1);
    lua_pop(L, 1);

    /* Path A: lua_stringtonumber
      Path goes through luaO_str2num -> luaO_str2int. Has overflow guard
    */
    int path_a_valid    = 0;
    int path_a_is_float = 0;

    size_t pushed = lua_stringtonumber(L, str);
    if (pushed > 0) {
        path_a_valid    = 1;
        path_a_is_float = !lua_isinteger(L, -1);
        lua_pop(L, 1);
    }

    /* Path B: tonumber(s, 10)
      Routes through luaB_tonumber -> b_str2int. No overflow guard 
     */
    int path_b_valid      = 0;
    int path_b_is_integer = 0;

    lua_getglobal(L, "tonumber");
    lua_pushstring(L, str);
    lua_pushinteger(L, 10);

    if (lua_pcall(L, 2, 1, 0) == LUA_OK) {
        if (!lua_isnil(L, -1)) {
            path_b_valid      = 1;
            path_b_is_integer = lua_isinteger(L, -1);
        }
        lua_pop(L, 1);
    } else {
        lua_pop(L, 1);
    }

    /*  
    Oracle: Check for the contradiction where 
    Path A returned float (since the converted string 
    was too large to fit in an int64) but Path B returned integer.
    */
    if (path_a_valid && path_a_is_float && path_b_valid && path_b_is_integer)
        __builtin_trap();

    lua_close(L);
    free(str);
    return 0;
}
