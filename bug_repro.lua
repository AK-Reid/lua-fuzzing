-- Reproducing the b_str2int silent overflow bug in Lua's tonumber(s, base)
-- No fuzzing, no harness, just pure Lua. 
-- lua_stringtonumber("99999999999999999999") falls back to strtod -> float
-- tonumber("99999999999999999999", 10)  calls b_str2int -> unsigned wrap -> wrong integer
--
-- These two results are contradictory: one says the value is too large to be
-- an integer, the other claims it fits. 

local s = "99999999999999999999"  -- 20 nines, > UINT64_MAX/2

local without_base = tonumber(s)          -- lua_stringtonumber path -> float
local with_base    = tonumber(s, 10)      -- b_str2int path -> wraps, wrong

print(string.format("tonumber(\"%s\")     = %s  (type: %s)", s, tostring(without_base), type(without_base)))
print(string.format("tonumber(\"%s\", 10) = %s  (type: %s)", s, tostring(with_base),    type(with_base)))
print()

local function is_integer(n)
    return math.type(n) == "integer"
end

local function is_float(n)
    return math.type(n) == "float"
end

if is_float(without_base) and is_integer(with_base) then
    -- They disagree, one says "too big for int", the other says "fits in int"!
    local expected_magnitude = 1e19  
    if math.abs(with_base) < expected_magnitude then
        print("BUG CONFIRMED: b_str2int wrapped silently!")
        print(string.format("  without base: %g (float, correct fallback for overflow)", without_base))
        print(string.format("  with base 10: %d (integer, but value is wrong - unsigned wrap occurred)", with_base))
        assert(false, "Oracle violated: tonumber(s) and tonumber(s,10) give contradictory type+magnitude results")
    end
end

print("No bug triggered (or Lua version has been patched).")
