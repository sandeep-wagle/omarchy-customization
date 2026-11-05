// omarchy-emulator-keys: host keyboard/mouse -> guest touch injector for the
// Android emulator (Free Fire keymapping, BlueStacks-style).
//
// Model: while the mouse-capture lock is ON (see omarchy-emulator-mouse), this
// daemon grabs gameplay keys on the X root window and translates them into
// multitouch contacts on the guest's virtio touch device via a persistent
// `adb shell` + sendevent stream (protocol B slots: separate contacts for
// Dpad / fire / taps compose into real multitouch, e.g. run + shoot).
// While the lock is OFF everything is ungrabbed: normal typing/clicks.
//
//   TAP keys      press -> touch down+up at the mapped % position (one slot)
//   DPAD (WASD)   hold -> contact held at stick-center + direction*deflect
//                 (8-way, full deflection = sprint); release all -> lift
//   FIRE (LMB)    press -> touch down at the fire button; release -> lift
//                 (hold-capable spray)
//   SCOPE (RMB)   same as FIRE at the scope button
//
// Map file: emulator/freefire-HEY.map in omarchy-customization
//   (TAP <Key> <X%> <Y%> | DPAD ... | FIRE ...), deployed to
//   ~/.config/msi-center/freefire-HEY.map. % = fraction of the landscape
//   game view, scaled to the 0-32767 MT frame (rotation-independent).
//
// Usage: omarchy-emulator-keys MAPFILE [ADB_SERIAL]
// Started/stopped by omarchy-emulator-mouse with the capture lock; also
// safe to run standalone (it self-gates on the lock + emulator focus).
// Diagnostics: $XDG_RUNTIME_DIR/omarchy-emulator-mouse/keys.log (capped).
//
// Build (one-time; deps: gcc, libX11):
//   gcc -O2 -o ~/.local/bin/omarchy-emulator-keys src/emulator-keys.c -lX11
//
// Source lives in the omarchy-customization repo as src/emulator-keys.c;
// the compiled binary is deployed to ~/.local/bin (see build line above).

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <sys/select.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>

// ---- guest touch (sendevent numbers; linux/input-event-codes.h values) ----
#define EV_SYN 0
#define EV_KEY 1
#define EV_ABS 3
#define SYN_REPORT 0
#define SYN_MT_REPORT 2
#define BTN_TOUCH 330
#define ABS_MT_SLOT 47
#define ABS_MT_TRACKING_ID 57
#define ABS_MT_POSITION_X 53
#define ABS_MT_POSITION_Y 54
#define MT_MAX_DEFAULT 32767.0
// Touch frame is runtime-configurable: the emulator's virtio touch is a
// 0-32767 frame on event12, while the Redmi NVT panel is native pixels
// (0-1079 x 0-2339) on event2. Env (MT_NODE/MT_XMAX/MT_YMAX) selects;
// defaults preserve emulator behavior.
static char g_mt_node[64] = "/dev/input/event12";
static double g_mt_xmax = MT_MAX_DEFAULT, g_mt_ymax = MT_MAX_DEFAULT;

#define MAX_TAPS 64

typedef struct { char key[32]; int x, y; unsigned keycode; } Tap;
typedef struct {
    double cx, cy, r; // dpad center% + radius%
    unsigned kc_up, kc_down, kc_left, kc_right;
    int held_up, held_down, held_left, held_right;
    int active; // contact held?
} Dpad;

static Tap g_taps[MAX_TAPS];
static int g_ntaps = 0;
static Dpad g_dpad = {0};
static double g_fire_x = 79.24, g_fire_y = 78.98;
static int g_have_fire = 0;
static double g_scope_x = 0, g_scope_y = 0;
static int g_have_scope = 0;
// dpad key names (resolved to keycodes once the display is open)
static char g_dk_up[32] = "", g_dk_down[32] = "", g_dk_left[32] = "", g_dk_right[32] = "";
static unsigned g_fire_held = 0, g_scope_held = 0;

static Display *g_dpy = NULL;
static Window g_root = 0;
static FILE *g_adb = NULL;
static const char *g_adb_serial = "emulator-5554";
static int g_tracking = 100; // guest tracking ids (arbitrary range)
static int g_btn_refs = 0;

static char g_state_dir[256] = "";
static char g_lock_file[300] = "";

// slot assignment: 1=dpad, 2=fire(LMB), 3=scope(RMB), 4=taps
enum { SLOT_DPAD = 1, SLOT_FIRE = 2, SLOT_SCOPE = 3, SLOT_TAP = 4 };

static void log_msg(const char *msg) {
    char p[340];
    snprintf(p, sizeof p, "%s/keys.log", g_state_dir);
    FILE *f = fopen(p, "a");
    if (!f) return;
    time_t t = time(NULL);
    fprintf(f, "%ld %s\n", (long)t, msg);
    fclose(f);
    // cap: keep last 100 lines (cheap rotation)
    static int n = 0;
    if (++n % 50 == 0) {
        char tmp[360], cmd[700];
        snprintf(tmp, sizeof tmp, "%s/keys.log.tmp", g_state_dir);
        snprintf(cmd, sizeof cmd, "tail -n 100 '%s/keys.log' > '%s' 2>/dev/null && mv '%s' '%s/keys.log' 2>/dev/null", g_state_dir, tmp, tmp, g_state_dir);
        (void)!system(cmd);
    }
}

static int pct2x(double pct) { return (int)(pct / 100.0 * g_mt_xmax + 0.5); }
static int pct2y(double pct) { return (int)(pct / 100.0 * g_mt_ymax + 0.5); }

// ---- adb transport: one persistent shell, sendevent lines, reopen on rot --
static int adb_open(void) {
    char cmd[256];
    snprintf(cmd, sizeof cmd, "adb -s %s shell", g_adb_serial);
    signal(SIGPIPE, SIG_IGN);
    g_adb = popen(cmd, "w");
    if (!g_adb) { log_msg("adb popen failed"); return 0; }
    return 1;
}

static void adb_line(const char *line) {
    if (!g_adb && !adb_open()) return;
    if (fprintf(g_adb, "%s\n", line) < 0 || fflush(g_adb) != 0) {
        // transport died: reopen once, replay the line
        if (g_adb) pclose(g_adb);
        g_adb = NULL;
        if (adb_open()) {
            fprintf(g_adb, "%s\n", line);
            fflush(g_adb);
        } else {
            log_msg("adb reopen failed");
        }
    }
}

static void se(int type, int code, int value) {
    char line[128];
    snprintf(line, sizeof line, "sendevent %s %d %d %d", g_mt_node, type, code, value);
    adb_line(line);
}

// ---- contact primitives (protocol B) ----
static void contact_down(int slot, double xpct, double ypct) {
    int id = g_tracking++;
    int x = pct2x(xpct), y = pct2y(ypct);
    se(EV_ABS, ABS_MT_SLOT, slot);
    se(EV_ABS, ABS_MT_TRACKING_ID, id);
    se(EV_ABS, ABS_MT_POSITION_X, x);
    se(EV_ABS, ABS_MT_POSITION_Y, y);
    se(EV_KEY, BTN_TOUCH, 1);
    se(EV_SYN, SYN_MT_REPORT, 0);
    se(EV_SYN, SYN_REPORT, 0);
    g_btn_refs++;
}

static void contact_move(int slot, double xpct, double ypct) {
    int x = pct2x(xpct), y = pct2y(ypct);
    se(EV_ABS, ABS_MT_SLOT, slot);
    se(EV_ABS, ABS_MT_POSITION_X, x);
    se(EV_ABS, ABS_MT_POSITION_Y, y);
    se(EV_SYN, SYN_MT_REPORT, 0);
    se(EV_SYN, SYN_REPORT, 0);
}

static void contact_up(int slot) {
    se(EV_ABS, ABS_MT_SLOT, slot);
    se(EV_ABS, ABS_MT_TRACKING_ID, -1);
    if (--g_btn_refs <= 0) { g_btn_refs = 0; se(EV_KEY, BTN_TOUCH, 0); }
    se(EV_SYN, SYN_MT_REPORT, 0);
    se(EV_SYN, SYN_REPORT, 0);
}

static void tap_at(double xpct, double ypct) {
    contact_down(SLOT_TAP, xpct, ypct);
    struct timespec tw = { .tv_sec = 0, .tv_nsec = 25 * 1000 * 1000 };
    nanosleep(&tw, NULL);
    contact_up(SLOT_TAP);
}

// ---- map file ----
static unsigned kc_of(const char *name) {
    KeySym ks = XStringToKeysym(name);
    if (ks == NoSymbol) {
        char msg[96];
        snprintf(msg, sizeof msg, "unknown keysym in map: %s", name);
        log_msg(msg);
        return 0;
    }
    return (unsigned)XKeysymToKeycode(g_dpy, ks);
}

static int load_map(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char line[256];
    while (fgets(line, sizeof line, f)) {
        if (line[0] == '#' || line[0] == '\n') continue;
        if (!strncmp(line, "TAP ", 4)) {
            char key[32]; double x, y;
            if (sscanf(line + 4, "%31s %lf %lf", key, &x, &y) == 3 &&
                g_ntaps < MAX_TAPS) {
                if (!strcmp(key, "MouseRButton")) {
                    // handled as button grab, not a key
                    g_scope_x = x; g_scope_y = y; g_have_scope = 1;
                    continue;
                }
                strncpy(g_taps[g_ntaps].key, key, 31);
                g_taps[g_ntaps].x = x; g_taps[g_ntaps].y = y;
                g_ntaps++;
            }
        } else if (!strncmp(line, "DPAD ", 5)) {
            char ku[32], kd[32], kl[32], kr[32];
            double cx, cy, r;
            if (sscanf(line + 5, "%lf %lf %lf %31s %31s %31s %31s",
                       &cx, &cy, &r, ku, kd, kl, kr) == 7) {
                g_dpad.cx = cx; g_dpad.cy = cy; g_dpad.r = r;
                strncpy(g_dk_up, ku, 31); strncpy(g_dk_down, kd, 31);
                strncpy(g_dk_left, kl, 31); strncpy(g_dk_right, kr, 31);
            }
        } else if (!strncmp(line, "FIRE ", 5)) {
            double x, y;
            if (sscanf(line + 5, "%lf %lf", &x, &y) == 2) {
                g_fire_x = x; g_fire_y = y; g_have_fire = 1;
            }
        }
    }
    fclose(f);
    return g_ntaps > 0;
}

// ---- X11 grabs ----
static void resolve_keycodes(void) {
    for (int i = 0; i < g_ntaps; i++)
        g_taps[i].keycode = kc_of(g_taps[i].key);
    g_dpad.kc_up = kc_of(g_dk_up); g_dpad.kc_down = kc_of(g_dk_down);
    g_dpad.kc_left = kc_of(g_dk_left); g_dpad.kc_right = kc_of(g_dk_right);
}

static void grab_all(void) {
    for (int i = 0; i < g_ntaps; i++)
        if (g_taps[i].keycode)
            XGrabKey(g_dpy, g_taps[i].keycode, AnyModifier, g_root,
                     False, GrabModeAsync, GrabModeAsync);
    unsigned dk[4] = {g_dpad.kc_up, g_dpad.kc_down, g_dpad.kc_left, g_dpad.kc_right};
    for (int i = 0; i < 4; i++)
        if (dk[i])
            XGrabKey(g_dpy, dk[i], AnyModifier, g_root,
                     False, GrabModeAsync, GrabModeAsync);
    // Fire = LMB, scope = RMB, only meaningful (and only grabbed) in game.
    XGrabButton(g_dpy, Button1, AnyModifier, g_root, False,
                ButtonPressMask | ButtonReleaseMask, GrabModeAsync, GrabModeAsync,
                None, None);
    if (g_have_scope)
        XGrabButton(g_dpy, Button3, AnyModifier, g_root, False,
                    ButtonPressMask | ButtonReleaseMask, GrabModeAsync, GrabModeAsync,
                    None, None);
}

static void ungrab_all(void) {
    XUngrabKey(g_dpy, AnyKey, AnyModifier, g_root);
    XUngrabButton(g_dpy, AnyButton, AnyModifier, g_root);
}

// focused window's _NET_WM_PID, walking up to the root (children rarely
// carry the property themselves).
static int focus_pid(void) {
    Window focus = 0;
    int revert = 0;
    XGetInputFocus(g_dpy, &focus, &revert);
    Atom pid_atom = XInternAtom(g_dpy, "_NET_WM_PID", False);
    while (focus) {
        Atom actual = None;
        int format = 0;
        unsigned long n = 0, extra = 0;
        unsigned char *data = NULL;
        if (XGetWindowProperty(g_dpy, focus, pid_atom, 0, 1, False,
                               XA_CARDINAL, &actual, &format, &n, &extra,
                               &data) == Success && data && n == 1) {
            int pid = (int)*(unsigned long *)data;
            XFree(data);
            return pid;
        }
        if (data) XFree(data);
        Window r = 0, p = 0, *kids = NULL;
        unsigned nk = 0;
        if (!XQueryTree(g_dpy, focus, &r, &p, &kids, &nk)) break;
        if (kids) XFree(kids);
        if (p == r || p == 0) break;
        focus = p;
    }
    return -1;
}

// lock gate: capture lock file says ON (mouse script owns it).
static int lock_on(void) {
    FILE *f = fopen(g_lock_file, "r");
    if (!f) return 0;
    int v = 0;
    if (fscanf(f, "%d", &v) != 1) v = 0;
    fclose(f);
    return v == 1;
}

// ---- gameplay actions ----
static void dpad_update(void) {
    int dx = (g_dpad.held_right ? 1 : 0) - (g_dpad.held_left ? 1 : 0);
    int dy = (g_dpad.held_down ? 1 : 0) - (g_dpad.held_up ? 1 : 0);
    if (!dx && !dy) {
        if (g_dpad.active) { contact_up(SLOT_DPAD); g_dpad.active = 0; }
        return;
    }
    double defl = g_dpad.r * 0.75; // inside the stick; full = sprint
    double x = g_dpad.cx + dx * defl, y = g_dpad.cy + dy * defl;
    if (!g_dpad.active) { contact_down(SLOT_DPAD, x, y); g_dpad.active = 1; }
    else contact_move(SLOT_DPAD, x, y);
}

static void dpad_release_all(void) {
    g_dpad.held_up = g_dpad.held_down = g_dpad.held_left = g_dpad.held_right = 0;
    if (g_dpad.active) { contact_up(SLOT_DPAD); g_dpad.active = 0; }
}

static void fire_release_all(void) {
    if (g_fire_held) { contact_up(SLOT_FIRE); g_fire_held = 0; }
    if (g_scope_held) { contact_up(SLOT_SCOPE); g_scope_held = 0; }
}

static void handle_key(unsigned keycode, int press, int emu_pid) {
    if (focus_pid() != emu_pid) return; // backstop: emulator only
    if (keycode == g_dpad.kc_up && g_dpad.kc_up) { g_dpad.held_up = press; dpad_update(); return; }
    if (keycode == g_dpad.kc_down && g_dpad.kc_down) { g_dpad.held_down = press; dpad_update(); return; }
    if (keycode == g_dpad.kc_left && g_dpad.kc_left) { g_dpad.held_left = press; dpad_update(); return; }
    if (keycode == g_dpad.kc_right && g_dpad.kc_right) { g_dpad.held_right = press; dpad_update(); return; }
    // taps fire on press only (press+release pairs would double-tap on
    // auto-repeat; Hyprland does not repeat grabbed keys to us anyway).
    if (!press) return;
    for (int i = 0; i < g_ntaps; i++) {
        if (g_taps[i].keycode == keycode) {
            tap_at(g_taps[i].x, g_taps[i].y);
            return;
        }
    }
}

static void handle_button(unsigned button, int press, int emu_pid) {
    if (focus_pid() != emu_pid) return;
    if (button == Button1 && g_have_fire) {
        if (press && !g_fire_held) { contact_down(SLOT_FIRE, g_fire_x, g_fire_y); g_fire_held = 1; }
        else if (!press && g_fire_held) { contact_up(SLOT_FIRE); g_fire_held = 0; }
    } else if (button == Button3 && g_have_scope) {
        if (press && !g_scope_held) { contact_down(SLOT_SCOPE, g_scope_x, g_scope_y); g_scope_held = 1; }
        else if (!press && g_scope_held) { contact_up(SLOT_SCOPE); g_scope_held = 0; }
    }
}

static volatile sig_atomic_t g_term = 0;
static void on_term(int sig) { (void)sig; g_term = 1; }

int main(int argc, char **argv) {    if (argc < 2) { fprintf(stderr, "usage: %s MAPFILE [ADB_SERIAL]\n", argv[0]); return 2; }
    if (argc >= 3) g_adb_serial = argv[2];
    // Touch frame override: MT_NODE/MT_XMAX/MT_YMAX env (Redmi NVT panel =
    // "/dev/input/event2", 1079, 2339; default = emulator virtio, 32767).
    {
        const char *e;
        if ((e = getenv("MT_NODE")) && *e) snprintf(g_mt_node, sizeof g_mt_node, "%s", e);
        if ((e = getenv("MT_XMAX")) && *e) g_mt_xmax = atof(e);
        if ((e = getenv("MT_YMAX")) && *e) g_mt_ymax = atof(e);
    }
    const char *home = getenv("HOME") ? getenv("HOME") : "/root";
    const char *rt = getenv("XDG_RUNTIME_DIR");
    snprintf(g_state_dir, sizeof g_state_dir, "%s/omarchy-emulator-mouse",
             rt ? rt : "/tmp");
    snprintf(g_lock_file, sizeof g_lock_file, "%s/locked", g_state_dir);
    (void)home;

    g_dpy = XOpenDisplay(NULL);
    if (!g_dpy) { fprintf(stderr, "no X display\n"); return 1; }
    g_root = DefaultRootWindow(g_dpy);
    signal(SIGTERM, on_term);
    signal(SIGINT, on_term);

    if (!load_map(argv[1])) { fprintf(stderr, "empty map: %s\n", argv[1]); return 1; }
    resolve_keycodes();

    // emulator host PID for the focus backstop (hyprctl, best effort).
    int emu_pid = -1;
    {
        FILE *p = popen("hyprctl clients -j 2>/dev/null | jq -r '[.[] | select(.class==\"Emulator\") | .pid][0] // empty'", "r");
        if (p) { char buf[32] = {0}; if (fgets(buf, sizeof buf, p)) emu_pid = atoi(buf); pclose(p); }
    }
    {
        char msg[128];
        snprintf(msg, sizeof msg, "keys daemon up (emu pid %d, %d taps)", emu_pid, g_ntaps);
        log_msg(msg);
    }

    int grabbed = 0, ticks = 0;
    while (!g_term) {
        while (XPending(g_dpy)) {
            XEvent ev;
            XNextEvent(g_dpy, &ev);
            if (!grabbed) continue; // stray (shouldn't happen)
            if (ev.type == KeyPress) handle_key(ev.xkey.keycode, 1, emu_pid);
            else if (ev.type == KeyRelease) handle_key(ev.xkey.keycode, 0, emu_pid);
            else if (ev.type == ButtonPress) handle_button(ev.xbutton.button, 1, emu_pid);
            else if (ev.type == ButtonRelease) handle_button(ev.xbutton.button, 0, emu_pid);
        }
        // lock gate at ~10Hz: grab set follows the capture lock.
        if (++ticks % 10 == 0) {
            int want = lock_on();
            if (want && !grabbed) { grab_all(); grabbed = 1; log_msg("grabbed (locked)"); }
            else if (!want && grabbed) {
                dpad_release_all(); fire_release_all();
                ungrab_all(); grabbed = 0; log_msg("ungrabbed (unlocked)");
            }
        }
        struct timespec tw = { .tv_sec = 0, .tv_nsec = 10 * 1000 * 1000 };
        nanosleep(&tw, NULL);
    }
    // Clean shutdown (TERM from the mouse script): lift every finger and
    // ungrab so nothing sticks and normal typing/clicks resume instantly.
    dpad_release_all();
    fire_release_all();
    if (grabbed) ungrab_all();
    if (g_adb) pclose(g_adb);
    XCloseDisplay(g_dpy);
    return 0;
}
