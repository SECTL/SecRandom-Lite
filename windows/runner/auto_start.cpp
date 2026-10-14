// Auto start (run at user logon) via the per-user "Run" registry key.
//
// Keep every comment and literal in this file ASCII: the runner is compiled
// with code page 936 and non-ASCII text raises C4819/C2220, which are
// promoted to errors. Chinese UI strings belong on the Dart side.
#include "auto_start.h"

#include <cwctype>

namespace {

// Per-user logon list. Writing HKCU needs no elevation, unlike HKLM, and it
// keeps the setting tied to the account that flipped the toggle on.
constexpr const wchar_t kRunKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kValueName[] = L"SecRandom Lite";

// Case-insensitive substring search; registry paths keep their casing but a
// user may have typed the key by hand with different casing.
bool ContainsIgnoreCase(const std::wstring& haystack,
                        const std::wstring& needle) {
  if (needle.empty() || haystack.size() < needle.size()) {
    return false;
  }
  for (size_t start = 0; start + needle.size() <= haystack.size(); ++start) {
    bool matches = true;
    for (size_t offset = 0; offset < needle.size(); ++offset) {
      if (std::towlower(haystack[start + offset]) !=
          std::towlower(needle[offset])) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}

// The quoted command line stored in the Run value, e.g.
// "C:\path\SecRandomLite.exe". Empty when the executable path is unknown.
std::wstring Command() {
  const std::wstring executable = auto_start::ExecutablePath();
  if (executable.empty()) {
    return std::wstring();
  }
  return L"\"" + executable + L"\"";
}

// Reads the raw Run value; returns false when it is absent or unreadable.
bool ReadValue(std::wstring* value) {
  DWORD size = 0;
  LSTATUS status =
      RegGetValueW(HKEY_CURRENT_USER, kRunKeyPath, kValueName, RRF_RT_REG_SZ,
                   nullptr, nullptr, &size);
  if (status != ERROR_SUCCESS || size < sizeof(wchar_t)) {
    return false;
  }

  // RegGetValue reports the byte count including the terminator.
  std::wstring buffer(size / sizeof(wchar_t), L'\0');
  status = RegGetValueW(HKEY_CURRENT_USER, kRunKeyPath, kValueName,
                        RRF_RT_REG_SZ, nullptr, &buffer[0], &size);
  if (status != ERROR_SUCCESS) {
    return false;
  }

  // Drop the terminator and any padding the reported size may have included.
  while (!buffer.empty() && buffer.back() == L'\0') {
    buffer.pop_back();
  }
  *value = buffer;
  return true;
}

}  // namespace

namespace auto_start {

std::wstring ExecutablePath() {
  // GetModuleFileNameW truncates without failing when the buffer is too
  // small, so grow until the returned length stops filling it.
  DWORD capacity = MAX_PATH;
  for (int attempt = 0; attempt < 8; ++attempt) {
    std::wstring buffer(capacity, L'\0');
    const DWORD length =
        GetModuleFileNameW(nullptr, &buffer[0], capacity);
    if (length == 0) {
      return std::wstring();
    }
    if (length < capacity) {
      buffer.resize(length);
      return buffer;
    }
    capacity *= 2;
  }
  return std::wstring();
}

bool IsEnabled() {
  const std::wstring executable = ExecutablePath();
  if (executable.empty()) {
    return false;
  }

  std::wstring value;
  if (!ReadValue(&value)) {
    return false;
  }

  // The value must still name *this* executable. A stale entry left behind by
  // an install that moved or was uninstalled reads as "off", so the toggle
  // invites the user to repair it instead of claiming auto start works.
  return ContainsIgnoreCase(value, executable);
}

bool SetEnabled(bool enabled) {
  const std::wstring command = Command();
  if (command.empty()) {
    return false;
  }

  HKEY key = nullptr;
  LSTATUS status =
      RegCreateKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0, nullptr, 0,
                      KEY_SET_VALUE | KEY_QUERY_VALUE, nullptr, &key, nullptr);
  if (status != ERROR_SUCCESS) {
    return false;
  }

  if (enabled) {
    status = RegSetValueExW(
        key, kValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    // A missing value already means "off"; deleting it is a no-op, not a
    // failure the user should have to recover from.
    status = RegDeleteValueW(key, kValueName);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }
  RegCloseKey(key);

  if (status != ERROR_SUCCESS) {
    return false;
  }

  // Read back rather than trusting the write: the toggle must reflect what
  // the registry actually holds, not what we asked it to hold.
  return IsEnabled() == enabled;
}

}  // namespace auto_start
