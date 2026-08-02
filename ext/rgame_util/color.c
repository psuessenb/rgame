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

int rgame_color_r(rgame_color color) { return (int)((color >> 24) & 0xFFu); }
int rgame_color_g(rgame_color color) { return (int)((color >> 16) & 0xFFu); }
int rgame_color_b(rgame_color color) { return (int)((color >> 8) & 0xFFu); }
int rgame_color_a(rgame_color color) { return (int)(color & 0xFFu); }

void rgame_color_bytes(rgame_color color, unsigned char out[4]) {
    out[0] = (unsigned char)rgame_color_r(color);
    out[1] = (unsigned char)rgame_color_g(color);
    out[2] = (unsigned char)rgame_color_b(color);
    out[3] = (unsigned char)rgame_color_a(color);
}
