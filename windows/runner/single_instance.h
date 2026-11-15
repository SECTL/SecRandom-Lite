#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// One running copy per signed-in user.
//
// A logon launch now starts parked in the tray instead of opening a window, so
// "I clicked the icon and nothing happened" would otherwise be the normal
// reaction -- and clicking again would spawn a second copy writing the same
// preferences and history files. The guard turns that second click into
// "bring the copy that is already running back".
namespace single_instance {

// Claims the instance slot. True means this process is the only copy and may
// start normally; false means another copy already holds it.
bool Acquire();

// Asks the running copy to show its main window. Best effort: the other
// process may be busy starting up, so the request is repeated a couple of
// times before the caller gives up and exits.
void RequestShow();

// The registered message RequestShow posts. Registering the same name twice in
// one process yields the same id, which is what lets the receiving window
// match it. Returns 0 when registration fails.
UINT ShowMainWindowMessage();

}  // namespace single_instance

#endif  // RUNNER_SINGLE_INSTANCE_H_
