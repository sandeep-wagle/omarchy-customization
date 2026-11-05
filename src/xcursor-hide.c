// omarchy-xcursor: hide/show the pointer on one app's X windows (XWayland).
//
// Why: omarchy's Hyprland build exposes no cursor-hide API to shell scripts,
// but XWayland forwards each X window's cursor to the compositor. Defining a
// blank cursor on the emulator's windows makes the pointer invisible exactly
// there (normal theme everywhere else) -- BlueStacks shooting-mode feel.
// The setting is a window attribute: it persists after we exit and needs no
// daemon. `show` restores inheritance.
//
// Usage: omarchy-xcursor hide|show PID   (PID = app process, e.g. emulator)
// Applies to every top-level window owned by PID (main + dialogs/toolbars).
//
// Build (one-time; deps: gcc, libX11):
//   gcc -O2 -o ~/.local/bin/omarchy-xcursor src/xcursor-hide.c -lX11
//
// Source lives in the omarchy-customization repo as src/xcursor-hide.c;
// the compiled binary is deployed to ~/.local/bin (see build line above).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

static pid_t window_pid(Display *dpy, Window w) {
    Atom pid_atom = XInternAtom(dpy, "_NET_WM_PID", False);
    Atom actual = None;
    int format = 0;
    unsigned long n = 0, extra = 0;
    unsigned char *data = NULL;
    pid_t pid = -1;
    if (XGetWindowProperty(dpy, w, pid_atom, 0, 1, False, XA_CARDINAL,
                           &actual, &format, &n, &extra, &data) == Success &&
        data && n == 1) {
        pid = (pid_t)*(unsigned long *)data;
    }
    if (data) XFree(data);
    return pid;
}

int main(int argc, char **argv) {
    if (argc != 3 || (strcmp(argv[1], "hide") && strcmp(argv[1], "show"))) {
        fprintf(stderr, "usage: %s hide|show PID\n", argv[0]);
        return 2;
    }
    pid_t target = (pid_t)atoi(argv[2]);
    if (target <= 0) return 2;

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { fprintf(stderr, "no X display\n"); return 1; }
    Window root = DefaultRootWindow(dpy);

    Cursor blank = None;
    if (!strcmp(argv[1], "hide")) {
        static char zero[8] = {0};
        Pixmap bm = XCreateBitmapFromData(dpy, root, zero, 8, 8);
        XColor black = {0};
        blank = XCreatePixmapCursor(dpy, bm, bm, &black, &black, 0, 0);
        XFreePixmap(dpy, bm);
    }

    Window rret, pret, *kids = NULL;
    unsigned nkids = 0;
    int applied = 0;
    if (XQueryTree(dpy, root, &rret, &pret, &kids, &nkids)) {
        for (unsigned i = 0; i < nkids; i++) {
            if (window_pid(dpy, kids[i]) == target) {
                // None = inherit (show); blank = invisible (hide).
                XDefineCursor(dpy, kids[i], blank);
                applied++;
            }
        }
        if (kids) XFree(kids);
    }
    if (blank) XFreeCursor(dpy, blank);
    XFlush(dpy);
    XCloseDisplay(dpy);
    printf("%s: %d window(s)\n", argv[1], applied);
    return applied ? 0 : 3;
}
