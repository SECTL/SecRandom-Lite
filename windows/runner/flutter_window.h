#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <shellapi.h>

#include "roll_call_floating_window.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static constexpr UINT kTrayMessage = WM_APP + 1;
  static constexpr UINT kTrayOpenRollCall = 1001;
  static constexpr UINT kTrayShowWindow = 1002;
  static constexpr UINT kTrayExit = 1003;

  bool AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void RestoreMainWindow(bool open_roll_call);


  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      quick_entry_channel_;
  // Reads and writes the HKCU Run value behind the auto start toggle.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      auto_start_channel_;
  std::unique_ptr<RollCallFloatingWindow> roll_call_window_;
  NOTIFYICONDATA tray_icon_{};
  UINT taskbar_created_message_ = 0;
  bool tray_available_ = false;
  bool exit_requested_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
