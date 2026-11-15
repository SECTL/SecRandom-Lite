#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "auto_start.h"
#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"
#include "window_placement.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // A logon launch has to be told apart from the user double-clicking the
  // icon: the first parks in the tray, the second opens the window. Windows
  // launches both with the same command line, so the Run value carries a
  // switch of our own. It is consumed here and kept out of the entrypoint
  // arguments, which describe what the user asked for -- not how we got here.
  bool started_at_logon = false;
  for (auto argument = command_line_arguments.begin();
       argument != command_line_arguments.end();) {
    if (auto_start::IsAutoStartSwitch(*argument)) {
      started_at_logon = true;
      argument = command_line_arguments.erase(argument);
    } else {
      ++argument;
    }
  }

  // An install that enabled auto start before the switch existed would keep
  // opening the window at logon until the toggle was flipped twice. Rewriting
  // the value here upgrades it; it only ever touches an entry that is already
  // on and already points at this executable.
  auto_start::RefreshCommandIfEnabled();

  // The logon launch sits in the tray without a window, so a user who clicks
  // the icon afterwards would start a second copy that knows nothing about the
  // first -- and both write the same preference and history files. Hand the
  // click to the copy that is already running instead.
  if (!single_instance::Acquire()) {
    if (!started_at_logon) {
      single_instance::RequestShow();
    }
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  // Come back where the user left it instead of always at (10, 10). The
  // stored origin is physical pixels and is validated against the connected
  // monitors inside Create(), so a position from an unplugged display simply
  // falls back to the default above.
  int saved_x = 0;
  int saved_y = 0;
  if (window_placement::LoadMainWindowPosition(&saved_x, &saved_y)) {
    window.SetRestoredPosition(saved_x, saved_y);
  }

  window.SetStartHidden(started_at_logon);

  if (!window.Create(L"SecRandom Lite", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
