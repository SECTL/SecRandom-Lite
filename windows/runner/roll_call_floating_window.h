#ifndef RUNNER_ROLL_CALL_FLOATING_WINDOW_H_
#define RUNNER_ROLL_CALL_FLOATING_WINDOW_H_

#include <windows.h>

#include <functional>

// A small always-on-top square window that acts only as a rollcall shortcut.
// Clicking it brings the main window forward and asks Dart to open the
// rollcall page; the shortcut itself stays visible.
class RollCallFloatingWindow {
 public:
  using Callback = std::function<void()>;

  explicit RollCallFloatingWindow(HWND main_window);
  ~RollCallFloatingWindow();

  RollCallFloatingWindow(const RollCallFloatingWindow&) = delete;
  RollCallFloatingWindow& operator=(const RollCallFloatingWindow&) = delete;

  void SetAppearance(int size, unsigned int color, int radius);
  bool Show();
  void Hide();
  void Destroy();

  void SetOpenedCallback(Callback callback);

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) noexcept;

 private:
  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam,
                        LPARAM lparam) noexcept;
  bool Create();
  void Paint(HWND window, HDC device_context);
  void ActivateMainWindow();

  // Persists the window origin after the user finishes dragging it.
  void SavePosition(HWND window);
  void StartLayerTracking();
  void StopLayerTracking();
  void EnsureTopmost();

  HWINEVENTHOOK foreground_hook_ = nullptr;
  HWINEVENTHOOK reorder_hook_ = nullptr;

  int size_ = 80;
  unsigned int color_ = 0xFFBDEAFF;
  int radius_ = 18;
  HWND main_window_ = nullptr;
  HWND window_ = nullptr;
  Callback opened_callback_;
  POINT drag_offset_{};
  POINT press_origin_{};
  bool dragging_ = false;
  bool moved_ = false;
};

#endif  // RUNNER_ROLL_CALL_FLOATING_WINDOW_H_
