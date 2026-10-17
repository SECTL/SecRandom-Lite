// Window position memory backed by the per-user registry.
//
// Keep every comment and literal in this file ASCII: the runner is compiled
// with code page 936 and non-ASCII text raises C4819/C2220, which are
// promoted to errors. Chinese UI strings belong on the Dart side.
//
// Only origins are stored, never sizes. Sizes are re-derived from the default
// value and scaled for whatever monitor hosts the window, which keeps a
// window remembered on a 100% display from coming back half-sized on a 200%
// one. Origins are stored exactly because they are already physical pixels
// under PerMonitorV2 and must be restored verbatim.
#include "window_placement.h"

namespace {

constexpr const wchar_t kKeyPath[] =
    L"Software\\SecRandom Lite\\WindowPlacement";
constexpr const wchar_t kMainX[] = L"MainX";
constexpr const wchar_t kMainY[] = L"MainY";
constexpr const wchar_t kFloatX[] = L"FloatX";
constexpr const wchar_t kFloatY[] = L"FloatY";

// An origin left of or above the primary monitor is negative, so the signed
// value goes into the registry as its DWORD bit pattern and comes back out
// through the inverse cast.
int FromStorage(DWORD value) { return static_cast<int>(value); }

DWORD ToStorage(int value) { return static_cast<DWORD>(value); }

bool ReadPoint(const wchar_t* x_name, const wchar_t* y_name, int* x, int* y) {
  DWORD stored_x = 0;
  DWORD size = sizeof(stored_x);
  if (RegGetValueW(HKEY_CURRENT_USER, kKeyPath, x_name, RRF_RT_REG_DWORD,
                   nullptr, &stored_x, &size) != ERROR_SUCCESS) {
    return false;
  }

  DWORD stored_y = 0;
  size = sizeof(stored_y);
  if (RegGetValueW(HKEY_CURRENT_USER, kKeyPath, y_name, RRF_RT_REG_DWORD,
                   nullptr, &stored_y, &size) != ERROR_SUCCESS) {
    return false;
  }

  *x = FromStorage(stored_x);
  *y = FromStorage(stored_y);
  return true;
}

void WritePoint(const wchar_t* x_name, const wchar_t* y_name, int x, int y) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kKeyPath, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }

  const DWORD stored_x = ToStorage(x);
  const DWORD stored_y = ToStorage(y);
  RegSetValueExW(key, x_name, 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&stored_x), sizeof(stored_x));
  RegSetValueExW(key, y_name, 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&stored_y), sizeof(stored_y));
  RegCloseKey(key);
}

}  // namespace

namespace window_placement {

bool IsUsablePoint(int x, int y, int width, int height) {
  if (width <= 0 || height <= 0) {
    return false;
  }

  RECT rect{x, y, x + width, y + height};
  // DEFAULTTONULL rather than NEAREST: a point that lands on no monitor at
  // all is exactly the stale case we want to reject, not quietly snap back.
  HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONULL);
  if (!monitor) {
    return false;
  }

  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(monitor, &info)) {
    return false;
  }

  RECT overlap{};
  if (!IntersectRect(&overlap, &rect, &info.rcWork)) {
    return false;
  }

  // A window with only a few pixels poking onto the screen is technically
  // visible but practically ungrabbable; keep a usable slice on the work
  // area so it can still be dragged back.
  constexpr int kMinVisible = 64;
  return (overlap.right - overlap.left) >= kMinVisible &&
         (overlap.bottom - overlap.top) >= kMinVisible;
}

bool LoadMainWindowPosition(int* x, int* y) {
  return ReadPoint(kMainX, kMainY, x, y);
}

void SaveMainWindowPosition(int x, int y) { WritePoint(kMainX, kMainY, x, y); }

bool LoadFloatingWindowPosition(int* x, int* y) {
  return ReadPoint(kFloatX, kFloatY, x, y);
}

void SaveFloatingWindowPosition(int x, int y) {
  WritePoint(kFloatX, kFloatY, x, y);
}

}  // namespace window_placement
