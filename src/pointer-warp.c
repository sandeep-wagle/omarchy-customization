// omarchy-pointer-warp: absolute cursor warp for Hyprland/omarchy.
//
// Why this exists: omarchy's Hyprland build routes `hyprctl dispatch` through
// a Lua sandbox that exposes no cursor API (no movecursor reachable from
// shell), so scripts cannot warp the pointer with stock tools. This tiny
// client speaks wlr-virtual-pointer-unstable-v1 directly (the same protocol
// wlrctl uses) and sends one absolute motion event.
//
// Usage: omarchy-pointer-warp ABS_X ABS_Y LAYOUT_W LAYOUT_H
//   ABS_X/ABS_Y  = target in global compositor coordinates (hyprctl cursorpos
//                  space), LAYOUT_W/H = total layout size (hyprctl monitors).
//        omarchy-pointer-warp hold
//                 = press-and-HOLD LMB until killed (SIGTERM/SIGINT): sends
//                   button-down now, button-up on exit. Used for button-free
//                   drag-look: while held, every mouse motion arrives in the
//                   emulator as a touch-drag, so the game camera follows the
//                   mouse with no button pressed (BlueStacks shooting-mode
//                   feel). The press point should be neutral ground (window
//                   center = crosshair/look area, where a tap does nothing).
//        omarchy-pointer-warp release
//                 = one-shot LMB-up (redundant safety after killing a holder).
//
// Build (one-time; deps: gcc, wayland-client, wayland-scanner):
//   wayland-scanner client-header wlr-virtual-pointer-unstable-v1.xml vp.h
//   wayland-scanner private-code  wlr-virtual-pointer-unstable-v1.xml vp.c
//   gcc -O2 -o ~/.local/bin/omarchy-pointer-warp src/pointer-warp.c vp.c \
//     $(pkg-config --cflags --libs wayland-client)
//
// Source lives in the omarchy-customization repo as src/pointer-warp.c;
// the compiled binary is deployed to ~/.local/bin (see build lines above).

#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <linux/input-event-codes.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *g_seat = NULL;
static struct zwlr_virtual_pointer_manager_v1 *g_mgr = NULL;

static void registry_global(void *data, struct wl_registry *reg,
                            uint32_t name, const char *iface, uint32_t ver) {
    (void)data; (void)ver;
    if (strcmp(iface, wl_seat_interface.name) == 0) {
        g_seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
    } else if (strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
        g_mgr = wl_registry_bind(reg, name,
                                 &zwlr_virtual_pointer_manager_v1_interface, 1);
    }
}
static void registry_global_remove(void *data, struct wl_registry *reg,
                                   uint32_t name) {
    (void)data; (void)reg; (void)name;
}
static const struct wl_registry_listener kRegListener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

// ---- shared connection setup for the button modes ----
static struct wl_display *g_dpy = NULL;
static struct zwlr_virtual_pointer_v1 *g_vp = NULL;

static int vp_connect(void) {
    g_dpy = wl_display_connect(NULL);
    if (!g_dpy) { fprintf(stderr, "no wayland display\n"); return 0; }
    struct wl_registry *reg = wl_display_get_registry(g_dpy);
    wl_registry_add_listener(reg, &kRegListener, NULL);
    wl_display_roundtrip(g_dpy);
    if (!g_mgr) { fprintf(stderr, "no virtual-pointer manager\n"); return 0; }
    g_vp = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(g_mgr, g_seat);
    if (!g_vp) { fprintf(stderr, "create_virtual_pointer failed\n"); return 0; }
    return 1;
}

static void vp_button(uint32_t btn, uint32_t state) {
    zwlr_virtual_pointer_v1_button(g_vp, now_ms(), btn, state);
    zwlr_virtual_pointer_v1_frame(g_vp);
    wl_display_flush(g_dpy);
}

static volatile sig_atomic_t g_done = 0;
static void on_term(int sig) {
    (void)sig;
    g_done = 1;
}

// hold: LMB down now, up on SIGTERM/SIGINT/EXIT. The process must stay alive
// for the whole hold (the compositor drops the press if we disconnect).
static int mode_hold(void) {
    if (!vp_connect()) return 1;
    signal(SIGTERM, on_term);
    signal(SIGINT, on_term);
    vp_button(BTN_LEFT, 1); // pressed
    while (!g_done) pause();
    vp_button(BTN_LEFT, 0); // released -- always, even on signal death
    struct timespec fifty_ms = { .tv_sec = 0, .tv_nsec = 50 * 1000 * 1000 };
    nanosleep(&fifty_ms, NULL);
    zwlr_virtual_pointer_v1_destroy(g_vp);
    wl_display_disconnect(g_dpy);
    return 0;
}

// release: one-shot LMB-up (redundant safety net after killing a holder).
static int mode_release(void) {
    if (!vp_connect()) return 1;
    vp_button(BTN_LEFT, 0);
    struct timespec fifty_ms = { .tv_sec = 0, .tv_nsec = 50 * 1000 * 1000 };
    nanosleep(&fifty_ms, NULL);
    zwlr_virtual_pointer_v1_destroy(g_vp);
    wl_display_disconnect(g_dpy);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "hold") == 0) return mode_hold();
    if (argc == 2 && strcmp(argv[1], "release") == 0) return mode_release();
    if (argc != 5) {
        fprintf(stderr, "usage: %s ABS_X ABS_Y LAYOUT_W LAYOUT_H\n", argv[0]);
        fprintf(stderr, "       %s hold | release\n", argv[0]);
        return 2;
    }
    double tx = atof(argv[1]), ty = atof(argv[2]);
    double lw = atof(argv[3]), lh = atof(argv[4]);
    if (lw <= 0 || lh <= 0) return 2;

    // Protocol extent: use full uint32 range for max precision.
    const double EXT = 16777215.0;
    uint32_t x = (uint32_t)(tx / lw * EXT + 0.5);
    uint32_t y = (uint32_t)(ty / lh * EXT + 0.5);

    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) { fprintf(stderr, "no wayland display\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &kRegListener, NULL);
    wl_display_roundtrip(dpy);
    if (!g_mgr) { fprintf(stderr, "no virtual-pointer manager\n"); return 1; }

    struct zwlr_virtual_pointer_v1 *vp =
        zwlr_virtual_pointer_manager_v1_create_virtual_pointer(g_mgr, g_seat);
    if (!vp) { fprintf(stderr, "create_virtual_pointer failed\n"); return 1; }
    zwlr_virtual_pointer_v1_motion_absolute(vp, now_ms(), x, y,
                                            (uint32_t)EXT, (uint32_t)EXT);
    zwlr_virtual_pointer_v1_frame(vp);
    wl_display_flush(dpy);
    // Give the compositor a moment to consume the event before we exit.
    struct timespec fifty_ms = { .tv_sec = 0, .tv_nsec = 50 * 1000 * 1000 };
    nanosleep(&fifty_ms, NULL);
    zwlr_virtual_pointer_v1_destroy(vp);
    wl_display_disconnect(dpy);
    return 0;
}
