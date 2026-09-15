#ifndef RGAME_LOCALE_H
#define RGAME_LOCALE_H

#include <stddef.h>

/*
 * The pure half of reading the user's preferred locales: joining them into one
 * "de-AT,en" string in a caller's buffer. No SDL, so the Check suite covers the
 * truncation contract on every platform, whatever locales the machine it runs
 * on happens to prefer. locale.c's rgame_preferred_locales is the SDL shim
 * that feeds it.
 */

/*
 * Appends one locale to a list whose full length so far is `length`: a comma
 * unless the list is empty, then `language`, then "-" and `country` when a
 * country is given. Returns the list's new full length.
 *
 * It behaves like snprintf: `out` receives as much as fits in `capacity`,
 * always NUL-terminated when `capacity` is non-zero, and the return value is
 * the length the whole list needs, so a result >= `capacity` means it was
 * truncated. `length` may already exceed `capacity`. A NULL or empty
 * `language` appends nothing.
 */
size_t rgame_locale_append(char *out, size_t capacity, size_t length, const char *language,
                           const char *country);

#endif /* RGAME_LOCALE_H */
