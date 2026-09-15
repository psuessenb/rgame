/*
 * locale.c — the user's preferred locales, as the operating system reports
 * them through SDL.
 *
 * rgame_preferred_locales is a thin shim over SDL_GetPreferredLocales; the
 * joining and the buffer contract are rgame_locale_append, which is pure and
 * Check-tested. Choosing among the locales is not here at all: it is
 * RGame::Engine::I18n.choose, specced headless.
 *
 * SDL answers without SDL_Init (measured on 2.0.20 under Linux, where it reads
 * LANG and then LANGUAGE), so none of this belongs to an app.
 */

#include "app/locale.h"

#include <SDL2/SDL.h>
#include <string.h>

#include "rgame/core.h"

static size_t append_text(char *out, size_t capacity, size_t length, const char *text) {
    for (; *text; text++, length++) {
        if (length + 1 < capacity) {
            out[length] = *text;
        }
    }
    return length;
}

size_t rgame_locale_append(char *out, size_t capacity, size_t length, const char *language,
                           const char *country) {
    if (language == NULL || language[0] == '\0') {
        return length;
    }

    if (length > 0) {
        length = append_text(out, capacity, length, ",");
    }
    length = append_text(out, capacity, length, language);
    if (country != NULL && country[0] != '\0') {
        length = append_text(out, capacity, length, "-");
        length = append_text(out, capacity, length, country);
    }

    if (capacity > 0) {
        out[length < capacity ? length : capacity - 1] = '\0';
    }
    return length;
}

size_t rgame_preferred_locales(char *out, size_t capacity) {
    if (capacity > 0) {
        out[0] = '\0';
    }

    SDL_Locale *locales = SDL_GetPreferredLocales();
    if (locales == NULL) {
        return 0;
    }

    size_t length = 0;
    for (const SDL_Locale *locale = locales; locale->language != NULL; locale++) {
        length = rgame_locale_append(out, capacity, length, locale->language, locale->country);
    }
    SDL_free(locales);
    return length;
}
