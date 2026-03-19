#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>

typedef enum {
    INVALID = 0,
    POS_INTEGER,
    NEG_INTEGER,
    FLOAT
} kind;

/* "Safe" stringtonumber conversion to minimally test fuzzer doesn't detect an overflow here.
 * If value would overflow int64, it reports FLOAT instead of POS_INTEGER.
 */
static kind safe_stringtonumber(const char *s) {
    if (*s == '\0') return INVALID;
    uint64_t n = 0;
    const uint64_t limit = INT64_MAX;

    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if (!isdigit(*p))
            return INVALID;

        unsigned digit = (unsigned)(*p - '0');

        if (n > (limit - digit) / 10) {
	   // Overflow, so report float
            return FLOAT;
        }

        n = n * 10 + digit;
    }

    // No overflow, report integer
    return POS_INTEGER;
}

/* Buggy tonumber base 10 parser. Does not have an overflow check */
static kind buggy_tonumber(const char *s) {
    if (*s == '\0') return INVALID;
    uint64_t n = 0;

    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        if (!isdigit(*p))
            return INVALID;

        unsigned digit = (unsigned)(*p - '0');
	// No overflow check!
        n = n * 10 + digit;
    }

    return POS_INTEGER;
}

/* Safe exponent parser */
static kind safe_parse_exp(const char *s) {
    if (*s == '\0') return INVALID;

    // Skip sign parsing in both the safe and buggy as we're not testing that with this function
    if (*s == '+' || *s == '-') s++;

    if (!isdigit((unsigned char)*s)) return INVALID;

    uint64_t n = 0;
    const uint64_t limit = INT64_MAX;

    while (isdigit((unsigned char)*s)) {
        unsigned digit = *s - '0';

        if (n > (limit - digit) / 10)
            return FLOAT;

        n = n * 10 + digit;
        s++;
    }

    if (*s == 'e' || *s == 'E') {
        s++;
        if (*s == '+' || *s == '-') s++;
        if (!isdigit((unsigned char)*s)) return INVALID;

        while (isdigit((unsigned char)*s)) s++;
        return (*s == '\0') ? FLOAT : INVALID;
    }

    return (*s == '\0') ? POS_INTEGER : INVALID;
}

/* Buggy exponent handling */
static kind buggy_parse_exp(const char *s) {
    if (*s == '\0') return INVALID;

    // Skip sign parsing in both the safe and buggy as we're not testing that with this function
    if (*s == '+' || *s == '-') s++;

    if (!isdigit((unsigned char)*s)) return INVALID;

    uint64_t n = 0;
    const uint64_t limit = INT64_MAX;

    while (isdigit((unsigned char)*s)) {
        unsigned digit = *s - '0';
        if (n > (limit - digit) / 10)
            return FLOAT;

        n = n * 10 + digit;
        s++;
    }

    if (*s == 'e' || *s == 'E') {
	// BUG! No exponent handling
        while (*s) s++;
    }

    return (*s == '\0') ? POS_INTEGER : INVALID;
}

static kind safe_parse_sign(const char *s) {
    if (*s == '\0') return INVALID;

    int neg = 0;
    if (*s == '-') {
        neg = 1;
        s++;
    } else if (*s == '+') {
        s++;
    }

    if (!isdigit((unsigned char)*s)) return INVALID;

    uint64_t n = 0;
    const uint64_t limit = neg ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX;

    while (isdigit((unsigned char)*s)) {
        unsigned digit = *s - '0';

        if (n > (limit - digit) / 10)
            return FLOAT;

        n = n * 10 + digit;
        s++;
    }

    if (*s != '\0') return INVALID;

    return neg ? NEG_INTEGER : POS_INTEGER;
}

/* Ignores sign of number when converting it to a number */
static kind buggy_parse_sign(const char *s) {
    if (*s == '\0') return INVALID;

    /* BUG! sign ignored */
    if (*s == '+' || *s == '-') {
        s++;
    }

    if (!isdigit((unsigned char)*s)) return INVALID;

    uint64_t n = 0;
    while (isdigit((unsigned char)*s)) {
        unsigned digit = *s - '0';
	const uint64_t limit = INT64_MAX;
        if (n > (limit - digit) / 10)
            return FLOAT;

        n = n * 10 + digit;
        s++;
    }

    if (*s != '\0') return INVALID;

    return POS_INTEGER;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) return 0;

    char *str = (char *)malloc(size + 1);
    if (!str) return 0;
    memcpy(str, data, size);
    str[size] = '\0';

    /* Path A: "safe" stringtonumber */
    int path_a_valid    = 0;
    int path_a_is_float = 0;
    int path_a_is_pos_int = 0;

    kind a = safe_stringtonumber(str);
    // kind a = safe_parse_exp(str);
    // kind a = safe_parse_sign(str);
    if (a != INVALID) {
        path_a_valid    = 1;
        path_a_is_float = (a == FLOAT);
        path_a_is_pos_int = (a == POS_INTEGER);
    }

    /* Path B: buggy tonumber */
    int path_b_valid      = 0;
    int path_b_is_float = 0;
    int path_b_is_pos_int = 0;

    kind b = buggy_tonumber(str);
    // kind b = buggy_parse_exp(str);
    // kind b = buggy_parse_sign(str);
    if (b != INVALID) {
        path_b_valid      = 1;
        path_b_is_float = (b == FLOAT);
        path_b_is_pos_int = (b == POS_INTEGER);
    }

    if (path_a_valid != path_b_valid || path_a_is_float != path_b_is_float || path_a_is_pos_int != path_b_is_pos_int)
        __builtin_trap();

    free(str);
    return 0;
}
