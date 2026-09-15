/*
 * locale_ext.c — the Ruby binding for RGame::Core.preferred_locales.
 *
 *   RGame::Core.preferred_locales   # => ["de-AT", "en"]
 *
 * A module function rather than an App method because SDL answers without an
 * app, or even SDL_Init. The reading is locale.c; this file only sizes a buffer
 * and splits the list. Choosing a language from the answer is
 * RGame::Engine::I18n.choose, which the glue calls.
 */

#include "ruby/core_ext.h"

#include "rgame/core.h"

/*
 * The user's preferred locales as Strings, most preferred first, or [] when the
 * OS names none. Never contains nil or an empty String.
 */
static VALUE core_preferred_locales(VALUE self) {
    (void)self;

    char stack[256];
    size_t length = rgame_preferred_locales(stack, sizeof stack);
    if (length < sizeof stack) {
        return rb_str_split(rb_utf8_str_new(stack, (long)length), ",");
    }

    /* Too long for the stack. The environment is read on every call, so the
     * list can grow between two of them: size again until what was written fits. */
    for (;;) {
        VALUE list = rb_utf8_str_new(NULL, (long)length);
        size_t written = rgame_preferred_locales(RSTRING_PTR(list), length + 1);
        if (written <= length) {
            rb_str_set_len(list, (long)written);
            return rb_str_split(list, ",");
        }
        length = written;
    }
}

void rgame_init_locale(VALUE mCore) {
    rb_define_module_function(mCore, "preferred_locales", core_preferred_locales, 0);
}
