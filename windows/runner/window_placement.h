#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>

// Remembers where the user left the windows so they reopen in place instead
// of always at the default spot.
//
// Storage is the per-user registry rather than Dart's SharedPreferences: the
// main window has to decide where to appear inside Win32Window::Create(),
// which runs before the Flutter engine -- and therefore Dart -- exists. At
// the moment the position is needed there is no Dart state to read, so the
// native side owns this end to end.
namespace window_placement {

// Reads the saved main-window origin (physical pixels). Returns false when
// nothing has been stored yet.
bool LoadMainWindowPosition(int* x, int* y);
void SaveMainWindowPosition(int x, int y);

// Reads the saved floating-window origin (physical pixels).
bool LoadFloatingWindowPosition(int* x, int* y);
void SaveFloatingWindowPosition(int x, int y);

// True when a |width| x |height| window placed at (x, y) still leaves enough
// of itself on a monitor to be grabbed and dragged back. Stored coordinates
// go stale when a monitor is unplugged or the resolution changes, so callers
// must treat false as "ignore the stored position" and fall back to the
// default placement.
bool IsUsablePoint(int x, int y, int width, int height);

// True when |rect| leaves enough of itself on some monitor, as above.
bool IsUsableRect(const RECT& rect);

// Moves |window| back onto the primary work area when it currently sits off
// screen -- the usual cause is the monitor it lived on being unplugged while
// the app is running, which strands a window the mouse can no longer reach.
// Returns true when the window was actually moved; minimized windows are
// left alone because they are meant to be off screen.
bool EnsureWindowOnScreen(HWND window);

}  // namespace window_placement

#endif  // RUNNER_WINDOW_PLACEMENT_H_
