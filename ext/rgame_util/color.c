#include "color.h"

static int clamp_component(int value) {
    if (value < 0) {
        return 0;
    }
    if (value > 255) {
        return 255;
    }
    return value;
}

rgame_color rgame_color_rgba(int r, int g, int b, int a) {
    return ((rgame_color)clamp_component(r) << 24) |
           ((rgame_color)clamp_component(g) << 16) |
           ((rgame_color)clamp_component(b) << 8) |
           (rgame_color)clamp_component(a);
}

