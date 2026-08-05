/*
 * audio_ext.c — the Ruby bindings for RGame::Core::Audio, ::Sample and ::Song.
 *
 *   audio = RGame::Core::Audio.new
 *   hit   = RGame::Core::Sample.new(audio, 'assets/hit.ogg')
 *   hit.play
 *
 *   music = RGame::Core::Song.new(audio, 'assets/theme.ogg')
 *   music.play(looping: true)
 *
 * Three classes in one file, unlike the one-class-per-file rule the rest of the
 * extension follows. They share a single wrapping shape — a C handle plus a
 * marked reference to the device it belongs to — and a Sample or a Song apart
 * from its Audio is not a thing. Splitting them would triplicate the TypedData
 * boilerplate to separate ninety lines that are read together.
 *
 * All three are thin: audio.c does the work, and the interesting parts of that
 * are miniaudio's. What this file adds is turning a NULL return into an
 * exception that names the file, and keeping the device reachable for as long
 * as any sound made from it.
 */

#include "core_ext.h"

#include "audio_internal.h"
#include "rgame/core.h"

/* ------------------------------------------------------------------------- *
 * Audio — the device
 * ------------------------------------------------------------------------- */

static void audio_free(void *ptr) {
    rgame_audio_destroy((rgame_audio *)ptr);
}

static const rb_data_type_t audio_data_type = {
    .wrap_struct_name = "rgame_audio",
    .function = {
        .dmark = NULL, /* no Ruby objects inside */
        .dfree = audio_free,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cAudio;
static VALUE cSample;
static VALUE cSong;

static rgame_audio *audio_unwrap(VALUE self) {
    rgame_audio *audio;
    TypedData_Get_Struct(self, rgame_audio, &audio_data_type, audio);
    if (!audio) {
        rb_raise(rb_eRuntimeError, "audio device is not initialized");
    }
    return audio;
}

static VALUE audio_alloc(VALUE klass) {
    return TypedData_Wrap_Struct(klass, &audio_data_type, NULL);
}

static VALUE audio_initialize(VALUE self) {
    char error[256] = {0};
    rgame_audio *audio = rgame_audio_create(error, sizeof(error));
    if (!audio) {
        rb_raise(rb_eRuntimeError, "%s", error);
    }

    RTYPEDDATA_DATA(self) = audio;
    return self;
}

static VALUE audio_volume(VALUE self) {
    return DBL2NUM((double)rgame_audio_volume(audio_unwrap(self)));
}

static VALUE audio_set_volume(VALUE self, VALUE volume) {
    rgame_audio_set_volume(audio_unwrap(self), (float)NUM2DBL(volume));
    return volume;
}

/* Which sound system is in use — "PulseAudio", "ALSA", "Null". A game with no
 * sound hardware gets "Null" and plays silently rather than failing, so this is
 * how it would find out. */
static VALUE audio_backend(VALUE self) {
    return rb_str_new_cstr(rgame_audio_backend(audio_unwrap(self)));
}

static VALUE audio_inspect(VALUE self) {
    rgame_audio *audio;
    TypedData_Get_Struct(self, rgame_audio, &audio_data_type, audio);
    if (!audio) {
        return rb_sprintf("#<%" PRIsVALUE " (uninitialized)>", rb_obj_class(self));
    }
    return rb_sprintf("#<%" PRIsVALUE " %s>", rb_obj_class(self),
                      rgame_audio_backend(audio));
}

/*
 * Audio.debug_live_sounds — how many samples and songs are alive.
 *
 * Test-only, and named so. A leaked sound is silent in every sense: nothing
 * sounds wrong, nothing is slower, and memory grows across an hour of play.
 * The image and font sides have the same counter for the same reason.
 */
static VALUE audio_s_debug_live_sounds(VALUE klass) {
    (void)klass;
    return LONG2NUM(rgame_audio_live_sounds());
}

/* ------------------------------------------------------------------------- *
 * Sample and Song — one shape, two payloads
 * ------------------------------------------------------------------------- */

/*
 * Both wrap a C handle plus the Ruby Audio it came from. Marking the device is
 * what stops the collector taking it first: the sound is a voice inside that
 * device's mixer, and freeing the mixer out from under it would be a crash at
 * an unpredictable moment.
 */
typedef struct {
    void *handle; /* rgame_sample * or rgame_song * */
    VALUE audio;
} rgame_sound_ref;

static void sound_ref_mark(void *ptr) {
    rb_gc_mark(((rgame_sound_ref *)ptr)->audio);
}

static size_t sound_ref_size(const void *ptr) {
    (void)ptr;
    return sizeof(rgame_sound_ref);
}

static void sample_ref_free(void *ptr) {
    rgame_sound_ref *ref = ptr;
    rgame_sample_destroy((rgame_sample *)ref->handle); /* NULL-safe */
    xfree(ref);
}

static void song_ref_free(void *ptr) {
    rgame_sound_ref *ref = ptr;
    rgame_song_destroy((rgame_song *)ref->handle);
    xfree(ref);
}

static const rb_data_type_t sample_data_type = {
    .wrap_struct_name = "rgame_sample",
    .function = { .dmark = sound_ref_mark, .dfree = sample_ref_free, .dsize = sound_ref_size },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static const rb_data_type_t song_data_type = {
    .wrap_struct_name = "rgame_song",
    .function = { .dmark = sound_ref_mark, .dfree = song_ref_free, .dsize = sound_ref_size },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE sound_alloc(VALUE klass, const rb_data_type_t *type) {
    rgame_sound_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, rgame_sound_ref, type, ref);
    ref->handle = NULL;
    ref->audio = Qnil;
    return object;
}

static VALUE sample_alloc(VALUE klass) {
    return sound_alloc(klass, &sample_data_type);
}

static VALUE song_alloc(VALUE klass) {
    return sound_alloc(klass, &song_data_type);
}

static rgame_sound_ref *sound_unwrap(VALUE self, const rb_data_type_t *type) {
    rgame_sound_ref *ref;
    TypedData_Get_Struct(self, rgame_sound_ref, type, ref);
    if (!ref->handle) {
        rb_raise(rb_eRuntimeError, "sound is not initialized");
    }
    return ref;
}

/* Shared by both constructors: unwrap the device, load, raise on failure with
 * the file named. `load` differs; nothing else does. */
static VALUE sound_initialize(VALUE self, VALUE audio, VALUE path, const rb_data_type_t *type,
                              void *(*load)(rgame_audio *, const char *, char *, size_t),
                              VALUE error_class) {
    rgame_sound_ref *ref;
    TypedData_Get_Struct(self, rgame_sound_ref, type, ref);

    /* Raises TypeError on anything that is not an Audio, so there is no
     * separate check to keep in step. */
    rgame_audio *device;
    TypedData_Get_Struct(audio, rgame_audio, &audio_data_type, device);

    const char *path_str = StringValueCStr(path);

    char error[256] = {0};
    void *handle = load(device, path_str, error, sizeof(error));
    if (!handle) {
        rb_raise(error_class, "%s", error);
    }

    ref->handle = handle;
    ref->audio = audio;
    return self;
}

/* The two loaders, wrapped so their signatures match sound_initialize's. */
static void *load_sample(rgame_audio *audio, const char *path, char *err, size_t err_size) {
    return rgame_sample_load(audio, path, err, err_size);
}

static void *load_song(rgame_audio *audio, const char *path, char *err, size_t err_size) {
    return rgame_song_load(audio, path, err, err_size);
}

/* --- Sample --- */

static VALUE sample_initialize(VALUE self, VALUE audio, VALUE path) {
    return sound_initialize(self, audio, path, &sample_data_type, load_sample,
                            rb_const_get(cSample, rb_intern("LoadError")));
}

/*
 * #play — start another voice.
 *
 * Deliberately not "restart": playing a sample while it is already sounding
 * layers a second voice over the first, which is what makes rapid footsteps or
 * gunfire sound right. A Song does the opposite.
 */
static VALUE sample_play(VALUE self) {
    rgame_sample_play((rgame_sample *)sound_unwrap(self, &sample_data_type)->handle);
    return self;
}

static VALUE sample_volume(VALUE self) {
    return DBL2NUM(
        (double)rgame_sample_volume((rgame_sample *)sound_unwrap(self, &sample_data_type)->handle));
}

static VALUE sample_set_volume(VALUE self, VALUE volume) {
    rgame_sample_set_volume((rgame_sample *)sound_unwrap(self, &sample_data_type)->handle,
                            (float)NUM2DBL(volume));
    return volume;
}

/* --- Song --- */

static VALUE song_initialize(VALUE self, VALUE audio, VALUE path) {
    return sound_initialize(self, audio, path, &song_data_type, load_song,
                            rb_const_get(cSong, rb_intern("LoadError")));
}

/* #play_looping(true/false) — the raw form; Song#play in
 * lib/rgame/core/audio.rb is the one with the keyword. */
static VALUE song_play(VALUE self, VALUE looping) {
    rgame_song_play((rgame_song *)sound_unwrap(self, &song_data_type)->handle,
                    RTEST(looping) ? 1 : 0);
    return self;
}

static VALUE song_stop(VALUE self) {
    rgame_song_stop((rgame_song *)sound_unwrap(self, &song_data_type)->handle);
    return self;
}

static VALUE song_playing_p(VALUE self) {
    return rgame_song_playing((rgame_song *)sound_unwrap(self, &song_data_type)->handle) ? Qtrue
                                                                                        : Qfalse;
}

static VALUE song_looping_p(VALUE self) {
    return rgame_song_looping((rgame_song *)sound_unwrap(self, &song_data_type)->handle) ? Qtrue
                                                                                        : Qfalse;
}

static VALUE song_volume(VALUE self) {
    return DBL2NUM(
        (double)rgame_song_volume((rgame_song *)sound_unwrap(self, &song_data_type)->handle));
}

static VALUE song_set_volume(VALUE self, VALUE volume) {
    rgame_song_set_volume((rgame_song *)sound_unwrap(self, &song_data_type)->handle,
                          (float)NUM2DBL(volume));
    return volume;
}

void rgame_init_audio(VALUE mCore) {
    cAudio = rb_define_class_under(mCore, "Audio", rb_cObject);
    rb_define_alloc_func(cAudio, audio_alloc);
    rb_define_method(cAudio, "initialize", audio_initialize, 0);
    rb_define_method(cAudio, "volume", audio_volume, 0);
    rb_define_method(cAudio, "volume=", audio_set_volume, 1);
    rb_define_method(cAudio, "backend", audio_backend, 0);
    rb_define_method(cAudio, "inspect", audio_inspect, 0);
    rb_define_singleton_method(cAudio, "debug_live_sounds", audio_s_debug_live_sounds, 0);

    cSample = rb_define_class_under(mCore, "Sample", rb_cObject);
    /* A file that cannot be read or is not a sound the engine knows — an
     * everyday condition, so it gets a name a game can rescue. */
    rb_define_class_under(cSample, "LoadError", rb_eStandardError);
    rb_define_alloc_func(cSample, sample_alloc);
    rb_define_method(cSample, "initialize", sample_initialize, 2);
    rb_define_method(cSample, "play", sample_play, 0);
    rb_define_method(cSample, "volume", sample_volume, 0);
    rb_define_method(cSample, "volume=", sample_set_volume, 1);

    cSong = rb_define_class_under(mCore, "Song", rb_cObject);
    rb_define_class_under(cSong, "LoadError", rb_eStandardError);
    rb_define_alloc_func(cSong, song_alloc);
    rb_define_method(cSong, "initialize", song_initialize, 2);
    rb_define_method(cSong, "play_looping", song_play, 1);
    rb_define_method(cSong, "stop", song_stop, 0);
    rb_define_method(cSong, "playing?", song_playing_p, 0);
    rb_define_method(cSong, "looping?", song_looping_p, 0);
    rb_define_method(cSong, "volume", song_volume, 0);
    rb_define_method(cSong, "volume=", song_set_volume, 1);
}
