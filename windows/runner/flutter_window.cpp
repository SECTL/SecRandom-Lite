#include "flutter_window.h"

#include <optional>

#include "auto_start.h"
#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayIconId = 1;
}


FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  roll_call_window_ = std::make_unique<RollCallFloatingWindow>(GetHandle());
  quick_entry_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "secrandom_lite/quick_entry",
      &flutter::StandardMethodCodec::GetInstance());
  roll_call_window_->SetOpenedCallback([this]() {
    quick_entry_channel_->InvokeMethod("openRollCall",
                                       std::make_unique<flutter::EncodableValue>());
  });
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  tray_available_ = AddTrayIcon();
  quick_entry_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setFloatingAppearance") {
          const auto* values = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
          if (!values) {
            result->Error("invalid_arguments", "Expected appearance map");
            return;
          }
          auto integer = [&](const char* key) -> int64_t {
            const auto& value = values->at(flutter::EncodableValue(key));
            if (const auto* number = std::get_if<int32_t>(&value)) return *number;
            return std::get<int64_t>(value);
          };
          roll_call_window_->SetAppearance(static_cast<int>(integer("size")),
              static_cast<unsigned int>(integer("color")), static_cast<int>(integer("radius")));
          result->Success();
        } else if (call.method_name() == "showFloatingWindow") {
          if (roll_call_window_->Show()) {
            result->Success();
          } else {
            result->Error("window_creation_failed", "Unable to create floating window");
          }
        } else if (call.method_name() == "hideFloatingWindow") {
          roll_call_window_->Hide();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  auto_start_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "secrandom_lite/auto_start",
      &flutter::StandardMethodCodec::GetInstance());
  // The registry is queried on every read so the toggle reflects edits made
  // outside the app; SetEnabled reads back before reporting success.
  auto_start_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "isEnabled") {
          result->Success(flutter::EncodableValue(auto_start::IsEnabled()));
        } else if (call.method_name() == "setEnabled") {
          const auto* enabled =
              call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
          if (!enabled) {
            result->Error("invalid_arguments", "Expected a bool argument");
            return;
          }
          if (!auto_start::SetEnabled(*enabled)) {
            result->Error("registry_write_failed",
                          "Unable to update the HKCU Run value");
            return;
          }
          result->Success(flutter::EncodableValue(*enabled));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  roll_call_window_.reset();
  quick_entry_channel_.reset();
  auto_start_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (taskbar_created_message_ != 0 &&
      message == taskbar_created_message_) {
    // Explorer restarted: the tray icon is gone. Re-add it, and if that fails
    // drop out of tray mode so closing the window really exits the app.
    tray_available_ = AddTrayIcon();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case kTrayMessage: {
      // After NIM_SETVERSION the event id arrives in LOWORD(lparam); under the
      // legacy semantics lparam is the message itself, whose LOWORD matches.
      const UINT tray_event = LOWORD(lparam);
      if (tray_event == WM_LBUTTONUP || tray_event == NIN_SELECT ||
          tray_event == NIN_KEYSELECT) {
        RestoreMainWindow(false);
      } else if (tray_event == WM_RBUTTONUP ||
                 tray_event == WM_CONTEXTMENU) {
        ShowTrayMenu();
      }
      return 0;
    }
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayOpenRollCall:
          RestoreMainWindow(true);
          return 0;
        case kTrayShowWindow:
          RestoreMainWindow(false);
          return 0;
        case kTrayExit:
          exit_requested_ = true;
          PostMessage(hwnd, WM_CLOSE, 0, 0);
          return 0;
      }
      break;
    case WM_CLOSE:
      if (tray_available_ && !exit_requested_) {
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::AddTrayIcon() {
  tray_icon_ = {};
  tray_icon_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = kTrayIconId;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayMessage;
  tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"SecRandom Lite");
  if (!tray_icon_.hIcon || !Shell_NotifyIcon(NIM_ADD, &tray_icon_)) {
    return false;
  }
  tray_icon_.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIcon(NIM_SETVERSION, &tray_icon_);
  return true;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_available_) return;
  Shell_NotifyIcon(NIM_DELETE, &tray_icon_);
  tray_available_ = false;
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, kTrayOpenRollCall, L"\x6253\x5F00\x70B9\x540D");
  AppendMenuW(menu, MF_STRING, kTrayShowWindow, L"\x663E\x793A\x4E3B\x7A97\x53E3");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExit, L"\x9000\x51FA");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(GetHandle());
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, cursor.x, cursor.y,
                 0, GetHandle(), nullptr);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void FlutterWindow::RestoreMainWindow(bool open_roll_call) {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
  if (open_roll_call && quick_entry_channel_) {
    quick_entry_channel_->InvokeMethod("openRollCall",
                                       std::make_unique<flutter::EncodableValue>());
  }
}
