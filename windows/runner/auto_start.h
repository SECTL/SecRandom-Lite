#ifndef RUNNER_AUTO_START_H_
#define RUNNER_AUTO_START_H_

#include <windows.h>

#include <string>

// Auto start (run at user logon) backed by the per-user "Run" registry key.
//
// The registry is the source of truth: the Dart side only mirrors whatever
// these two functions report, so a value edited by hand in regedit is picked
// up on the next read instead of showing a stale toggle.
namespace auto_start {

// Returns true when the HKCU Run value for this app exists and still points
// at the executable that is currently running.
bool IsEnabled();

// Creates or removes the HKCU Run value. Returns false when the registry
// write fails, or when the read-back afterwards does not match what was
// requested, so callers can surface the failure instead of pretending.
bool SetEnabled(bool enabled);

// Full path of the running executable, or an empty string on failure.
std::wstring ExecutablePath();

}  // namespace auto_start

#endif  // RUNNER_AUTO_START_H_
