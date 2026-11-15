// Single instance guard for the tray-resident lifetime of the app.
//
// Keep every comment and literal in this file ASCII: the runner is compiled
// with code page 936 and non-ASCII text raises C4819/C2220, which are
// promoted to errors.
#include "single_instance.h"

namespace {

// "Local\" scopes the name to the logon session (and therefore to the user), so
// two accounts on one machine each get their own copy instead of the second
// one being turned away. "Global\" would do exactly that.
constexpr const wchar_t kMutexName[] = L"Local\\SecRandomLite.SingleInstance";

// A registered message is delivered by name, which is how a freshly started
// process reaches the window of the running one without knowing its handle.
constexpr const wchar_t kShowMainWindowMessage[] =
    L"SecRandomLite.ShowMainWindow";

// Never closed on purpose: the handle *is* the presence flag, and it goes away
// with the process. No ownership is taken (CreateMutexW with bInitialOwner
// FALSE), so a crashed or killed instance cannot leave the mutex locked --
// which is the failure mode that would make the app refuse to start at all.
HANDLE g_instance_mutex = nullptr;

}  // namespace

namespace single_instance {

bool Acquire() {
  g_instance_mutex = CreateMutexW(nullptr, FALSE, kMutexName);
  if (g_instance_mutex == nullptr) {
    // Running twice is a far smaller problem than not running at all, so a
    // mutex that cannot be created does not block startup.
    return true;
  }
  return GetLastError() != ERROR_ALREADY_EXISTS;
}

UINT ShowMainWindowMessage() {
  return RegisterWindowMessageW(kShowMainWindowMessage);
}

void RequestShow() {
  const UINT message = ShowMainWindowMessage();
  if (message == 0) {
    return;
  }
  // Two attempts, because the copy that owns the slot may still be creating
  // its window when a second launch lands right after logon.
  for (int attempt = 0; attempt < 2; ++attempt) {
    PostMessageW(HWND_BROADCAST, message, 0, 0);
    Sleep(150);
  }
}

}  // namespace single_instance
