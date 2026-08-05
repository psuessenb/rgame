/*
 * glyph_cache.c — an open-addressed table of rasterised glyphs.
 * See glyph_cache.h for why it caches per glyph and why nothing is ever evicted.
 */

#include "glyph_cache.h"

#include <stdlib.h>

/* Small enough that a font drawing only digits wastes nothing, big enough that
 * plain ASCII text never rehashes. */
#define RGAME_GLYPH_CACHE_MIN_CAPACITY 64

/* Grow at 3/4 full. Linear probing degrades sharply as a table approaches
 * full — the probe walk turns into a scan — so the table is kept loose. */
#define RGAME_GLYPH_CACHE_LOAD_NUMERATOR 3
#define RGAME_GLYPH_CACHE_LOAD_DENOMINATOR 4

void rgame_glyph_cache_init(rgame_glyph_cache *cache) {
    cache->entries = NULL;
    cache->capacity = 0;
    cache->count = 0;
}

void rgame_glyph_cache_destroy(rgame_glyph_cache *cache) {
    if (!cache) {
        return;
    }

    free(cache->entries);
    /* Left in the state init would produce, so a second destroy is a no-op and
     * a find afterwards is an ordinary miss rather than a use-after-free. */
    rgame_glyph_cache_init(cache);
}

/*
 * Knuth's multiplicative hash, masked to the table size.
 *
 * Note what this is *not*: a correctness requirement. Replacing it with the
 * identity function leaves every test passing, and rightly so — linear probing
 * resolves collisions whatever the hash does, so a worse one is slower, not
 * wrong. That mutation survives the suite deliberately.
 *
 * It stays because the cost is one multiply and the alternative is a bet on the
 * key distribution. Identity happens to spread the codepoints a Latin game
 * draws almost perfectly, since they arrive in contiguous runs (ASCII 32..126,
 * Latin-1 accents, a handful of punctuation). The bet is on the next game:
 * masking the low bits of a table this small means an emoji range, or CJK, or
 * any set whose members share their low bits, lands in a few buckets and turns
 * every lookup into a walk. Not worth finding out.
 */
static unsigned int slot_for(int codepoint, unsigned int capacity) {
    return ((unsigned int)codepoint * 2654435761u) & (capacity - 1);
}

/*
 * The slot a codepoint occupies, or the first free one after where it would be.
 *
 * One walk answers both "is it here?" and "where does it go?", which is what
 * lets insert find an existing entry and replace it rather than adding a
 * second. Nothing is ever deleted, so there are no tombstones to skip and the
 * walk stops at the first empty slot.
 *
 * Terminates because the table is never allowed to fill.
 */
static rgame_glyph *probe(rgame_glyph *entries, unsigned int capacity, int codepoint) {
    unsigned int slot = slot_for(codepoint, capacity);

    for (;;) {
        rgame_glyph *entry = &entries[slot];
        if (entry->codepoint == 0 || entry->codepoint == codepoint) {
            return entry;
        }
        slot = (slot + 1) & (capacity - 1);
    }
}

/* Reallocates into a bigger table and re-probes every entry — slots depend on
 * the capacity, so the old positions mean nothing in the new table. */
static int grow(rgame_glyph_cache *cache) {
    unsigned int capacity = cache->capacity ? cache->capacity * 2
                                            : RGAME_GLYPH_CACHE_MIN_CAPACITY;

    rgame_glyph *entries = calloc(capacity, sizeof(rgame_glyph));
    if (!entries) {
        return 0;
    }

    for (unsigned int i = 0; i < cache->capacity; i++) {
        if (cache->entries[i].codepoint != 0) {
            *probe(entries, capacity, cache->entries[i].codepoint) = cache->entries[i];
        }
    }

    free(cache->entries);
    cache->entries = entries;
    cache->capacity = capacity;
    return 1;
}

int rgame_glyph_cache_find(const rgame_glyph_cache *cache, int codepoint, rgame_glyph *out) {
    if (!cache || !out || !cache->entries || codepoint == 0) {
        return 0;
    }

    const rgame_glyph *entry = probe(cache->entries, cache->capacity, codepoint);
    if (entry->codepoint != codepoint) {
        return 0;
    }

    *out = *entry;
    return 1;
}

int rgame_glyph_cache_insert(rgame_glyph_cache *cache, const rgame_glyph *glyph) {
    if (!cache || !glyph || glyph->codepoint == 0) {
        return 0; /* 0 is the empty marker; storing it would hide the entry */
    }

    /* Grown *before* the insert, not after, so the table can never be full at
     * the moment probe() walks it — that walk has no exit condition other than
     * finding a free slot. */
    if ((cache->count + 1) * RGAME_GLYPH_CACHE_LOAD_DENOMINATOR >=
        cache->capacity * RGAME_GLYPH_CACHE_LOAD_NUMERATOR) {
        if (!grow(cache)) {
            return 0;
        }
    }

    rgame_glyph *entry = probe(cache->entries, cache->capacity, glyph->codepoint);
    /* An existing entry is overwritten in place, so the count only moves when
     * the codepoint is genuinely new. */
    if (entry->codepoint == 0) {
        cache->count++;
    }
    *entry = *glyph;
    return 1;
}

unsigned int rgame_glyph_cache_count(const rgame_glyph_cache *cache) {
    return cache ? cache->count : 0;
}
