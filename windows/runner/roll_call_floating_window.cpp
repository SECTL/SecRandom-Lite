#include "roll_call_floating_window.h"

#include <windowsx.h>

#include <cstdlib>
#include <cmath>
#include <utility>

#include "window_placement.h"

namespace {
constexpr wchar_t kWindowClassName[] = L"SECRANDOM_ROLL_CALL_FLOATING_WINDOW";
constexpr UINT kEnsureTopmost = WM_APP + 20;
HWND tracked_window = nullptr;
bool layer_check_pending = false;

void CALLBACK LayerChanged(HWINEVENTHOOK, DWORD event, HWND window,
                           LONG object_id, LONG, DWORD, DWORD) {
  if (!tracked_window || window == tracked_window || layer_check_pending) return;
  if (event == EVENT_OBJECT_REORDER && object_id != OBJID_WINDOW) return;
  layer_check_pending = PostMessage(tracked_window, kEnsureTopmost, 0, 0) != FALSE;
}

}  // namespace

namespace {

bool RegisterWindowClass() {
  static bool registered = false;
  if (registered) {
    return true;
  }

  WNDCLASS window_class{};
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpfnWndProc = RollCallFloatingWindow::WindowProc;
  window_class.lpszClassName = kWindowClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_HAND);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  if (!RegisterClass(&window_class) &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }
  registered = true;
  return true;
}

}  // namespace

RollCallFloatingWindow::RollCallFloatingWindow(HWND main_window)
    : main_window_(main_window) {}

RollCallFloatingWindow::~RollCallFloatingWindow() { Destroy(); }

void RollCallFloatingWindow::SetAppearance(int size, unsigned int color, int radius) {
  size_ = size;
  color_ = color;
  radius_ = radius;
  if (window_) {
    SetWindowPos(window_, nullptr, 0, 0, size_, size_, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    HRGN region = CreateRoundRectRgn(0, 0, size_ + 1, size_ + 1, radius_ * 2, radius_ * 2);
    if (!SetWindowRgn(window_, region, TRUE)) DeleteObject(region);
    InvalidateRect(window_, nullptr, TRUE);
  }
}

void RollCallFloatingWindow::StartLayerTracking() {
  tracked_window = window_;
  if (!foreground_hook_) {
    foreground_hook_ = SetWinEventHook(EVENT_SYSTEM_FOREGROUND,
        EVENT_SYSTEM_FOREGROUND, nullptr, LayerChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
  }
  if (!reorder_hook_) {
    reorder_hook_ = SetWinEventHook(EVENT_OBJECT_REORDER,
        EVENT_OBJECT_REORDER, nullptr, LayerChanged, 0, 0, WINEVENT_OUTOFCONTEXT);
  }
}

void RollCallFloatingWindow::StopLayerTracking() {
  tracked_window = nullptr;
  layer_check_pending = false;
  if (foreground_hook_) UnhookWinEvent(foreground_hook_);
  if (reorder_hook_) UnhookWinEvent(reorder_hook_);
  foreground_hook_ = nullptr;
  reorder_hook_ = nullptr;
}

void RollCallFloatingWindow::EnsureTopmost() {
  if (!window_ || !IsWindowVisible(window_)) return;
  bool needs_raise = !(GetWindowLongPtr(window_, GWL_EXSTYLE) & WS_EX_TOPMOST);
  for (HWND above = GetWindow(window_, GW_HWNDPREV); above;
       above = GetWindow(above, GW_HWNDPREV)) {
    if (IsWindowVisible(above) &&
        (GetWindowLongPtr(above, GWL_EXSTYLE) & WS_EX_TOPMOST)) {
      needs_raise = true;
      break;
    }
  }
  // Only change Z-order when needed, otherwise the resulting reorder event
  // would cause a self-sustaining chain of notifications.
  if (needs_raise) {
    SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

bool RollCallFloatingWindow::Show() {
  if (!window_ && !Create()) {
    return false;
  }

  SetAppearance(size_, color_, radius_);
  ShowWindow(window_, SW_SHOWNOACTIVATE);
  SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  StartLayerTracking();
  return true;
}

void RollCallFloatingWindow::Hide() {
  StopLayerTracking();
  if (window_) {
    ShowWindow(window_, SW_HIDE);
  }
}

void RollCallFloatingWindow::Destroy() {
  StopLayerTracking();
  if (window_) {
    HWND window = window_;
    DestroyWindow(window);
    window_ = nullptr;
  }
}

void RollCallFloatingWindow::SetOpenedCallback(Callback callback) {
  opened_callback_ = std::move(callback);
}

bool RollCallFloatingWindow::Create() {
  if (!RegisterWindowClass()) {
    return false;
  }

  // Restore first: the user put it somewhere on purpose, and that beats
  // anchoring it to wherever the main window happens to be now. The stored
  // origin is validated because a saved spot can outlive the monitor it was
  // placed on.
  int x = 0;
  int y = 0;
  bool placed = false;

  int saved_x = 0;
  int saved_y = 0;
  if (window_placement::LoadFloatingWindowPosition(&saved_x, &saved_y) &&
      window_placement::IsUsablePoint(saved_x, saved_y, size_, size_)) {
    x = saved_x;
    y = saved_y;
    placed = true;
  } else {
    RECT main_rect{};
    if (main_window_ && GetWindowRect(main_window_, &main_rect)) {
      x = main_rect.right - size_ - 24;
      y = main_rect.top + 24;
      placed = true;
    }
  }

  // The label is written as escapes because this file is compiled under a
  // non-Unicode code page where raw CJK literals fail the build.
  window_ = CreateWindowEx(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kWindowClassName, L"\x70B9\x540D",
      WS_POPUP, placed ? x : CW_USEDEFAULT, placed ? y : CW_USEDEFAULT, size_,
      size_, nullptr, nullptr, GetModuleHandle(nullptr), this);

  return window_ != nullptr;
}

void RollCallFloatingWindow::SavePosition(HWND window) {
  RECT rect{};
  if (window && GetWindowRect(window, &rect)) {
    window_placement::SaveFloatingWindowPosition(rect.left, rect.top);
  }
}

void RollCallFloatingWindow::Paint(HWND window, HDC device_context) {
  RECT client_rect{};
  GetClientRect(window, &client_rect);

  const int red = (color_ >> 16) & 255;
  const int green = (color_ >> 8) & 255;
  const int blue = color_ & 255;
  HBRUSH background = CreateSolidBrush(RGB(red, green, blue));
  FillRect(device_context, &client_rect, background);
  DeleteObject(background);

  SetBkMode(device_context, TRANSPARENT);
  auto linear = [](int value) {
    const double component = value / 255.0;
    return component <= 0.03928 ? component / 12.92 : std::pow((component + 0.055) / 1.055, 2.4);
  };
  const double luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue);
  SetTextColor(device_context, luminance > 0.4 ? RGB(35, 35, 35) : RGB(255, 255, 255));
  HFONT font =
      CreateFont(size_ / 4, 0, 0, 0, FW_MEDIUM, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                 DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei");
  HGDIOBJ old_font = SelectObject(device_context, font);
  DrawText(device_context, L"\x70B9\x540D", -1, &client_rect,
           DT_SINGLELINE | DT_CENTER | DT_VCENTER);
  SelectObject(device_context, old_font);
  DeleteObject(font);
}

void RollCallFloatingWindow::ActivateMainWindow() {
  if (!main_window_ || !IsWindow(main_window_)) {
    return;
  }
  if (IsIconic(main_window_)) {
    ShowWindow(main_window_, SW_RESTORE);
  } else if (!IsWindowVisible(main_window_)) {
    // The close button hides the window to the tray; a hidden window is not
    // iconic, so it needs an explicit show before it can be brought forward.
    ShowWindow(main_window_, SW_SHOWNORMAL);
  }
  SetForegroundWindow(main_window_);
  SetActiveWindow(main_window_);
}

LRESULT CALLBACK RollCallFloatingWindow::WindowProc(HWND window, UINT message,
                                                    WPARAM wparam,
                                                    LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
  }

  auto* instance = reinterpret_cast<RollCallFloatingWindow*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  return instance ? instance->HandleMessage(window, message, wparam, lparam)
                  : DefWindowProc(window, message, wparam, lparam);
}

LRESULT RollCallFloatingWindow::HandleMessage(HWND window, UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam) noexcept {
  switch (message) {
    case kEnsureTopmost:
      layer_check_pending = false;
      EnsureTopmost();
      return 0;
    case WM_WINDOWPOSCHANGED:
      if (tracked_window == window && !layer_check_pending) {
        layer_check_pending = PostMessage(window, kEnsureTopmost, 0, 0) != FALSE;
      }
      break;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC device_context = BeginPaint(window, &paint);
      Paint(window, device_context);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_LBUTTONDOWN: {
      POINT cursor{};
      GetCursorPos(&cursor);
      RECT window_rect{};
      GetWindowRect(window, &window_rect);
      drag_offset_.x = cursor.x - window_rect.left;
      drag_offset_.y = cursor.y - window_rect.top;
      press_origin_ = cursor;
      dragging_ = true;
      moved_ = false;
      SetCapture(window);
      return 0;
    }
    case WM_MOUSEMOVE:
      if (dragging_ && (wparam & MK_LBUTTON)) {
        POINT cursor{};
        GetCursorPos(&cursor);
        if (!moved_) {
          // Ignore sub-threshold jitter so a normal click is not swallowed
          // and treated as a drag.
          const int dx = std::abs(cursor.x - press_origin_.x);
          const int dy = std::abs(cursor.y - press_origin_.y);
          if (dx <= GetSystemMetrics(SM_CXDRAG) &&
              dy <= GetSystemMetrics(SM_CYDRAG)) {
            return 0;
          }
          moved_ = true;
        }
        SetWindowPos(window, HWND_TOPMOST, cursor.x - drag_offset_.x,
                     cursor.y - drag_offset_.y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      }
      return 0;
    case WM_LBUTTONUP:
      if (dragging_) {
        dragging_ = false;
        ReleaseCapture();
        if (!moved_) {
          // Stay visible: the shortcut remains available for the next click.
          ActivateMainWindow();
          if (opened_callback_) {
            opened_callback_();
          }
        } else {
          // The drag finished with the window somewhere new; remember it so
          // the next show lands there instead of next to the main window.
          SavePosition(window);
        }
      }
      return 0;
    case WM_CAPTURECHANGED:
      dragging_ = false;
      return 0;
  }
  // Must use the valid HWND passed in: during CreateWindowEx the messages
  // (WM_NCCREATE/WM_CREATE) arrive before window_ is assigned, and passing a
  // null handle here makes creation abort with ERROR_INVALID_WINDOW_HANDLE.
  return DefWindowProc(window, message, wparam, lparam);
}
