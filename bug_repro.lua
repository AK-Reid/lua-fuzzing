-- Reproducing the b_str2int silent overflow bug in Lua's tonumber(s, base)
-- No fuzzing, no harness, just pure Lua.
--
-- lua_stringtonumber("99999999999999999999") falls back to strtod -> float
-- tonumber("99999999999999999999", 10)  calls b_str2int -> unsigned wrap -> wrong integer
--
-- These two results are contradictory: one says the value is too large to be
-- an integer, the other claims it fits. That contradiction is the bug.

local s = "99999999999999999999"  -- 20 nines, > UINT64_MAX/2

local without_base = tonumber(s)        -- lua_stringtonumber path -> float
local with_base    = tonumber(s, 10)    -- b_str2int path -> wraps, wrong integer

print(string.format("tonumber(\"%s\")     = %s  (type: %s)", s, tostring(without_base), math.type(without_base)))
print(string.format("tonumber(\"%s\", 10) = %s  (type: %s)", s, tostring(with_base),    math.type(with_base)))
print()

-- Oracle: both paths parsed the same decimal string.
-- If one returns a float (too large for int64) and the other returns an
-- integer (claims it fits), they are making contradictory type claims.
if math.type(without_base) == "float" and math.type(with_base) == "integer" then
    print("BUG CONFIRMED: b_str2int wrapped silently!")
    print(string.format("  without base: %g (correct: too large for int64, float fallback)", without_base))
    print(string.format("  with base 10: %d (wrong: unsigned accumulator wrapped)", with_base))
    assert(false, "Oracle violated: tonumber(s) and tonumber(s, 10) disagree on whether value fits in int64")
end

print("No bug triggered (or Lua version has been patched).")
