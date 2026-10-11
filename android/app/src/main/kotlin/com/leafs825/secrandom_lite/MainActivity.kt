package com.leafs825.secrandom_lite

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var quickEntryChannel: MethodChannel? = null
    private var dartReady = false
    private var pendingRollCallRequest = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleQuickEntryIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        quickEntryChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            QUICK_ENTRY_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    CONSUME_PENDING_ROLL_CALL -> {
                        val pending = pendingRollCallRequest
                        pendingRollCallRequest = false
                        dartReady = true
                        result.success(pending)
                    }
                    else -> result.notImplemented()
                }
            }
        }

    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleQuickEntryIntent(intent)
    }

    private fun handleQuickEntryIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_ROLLCALL_OPEN, false) == true ||
            intent?.action == ACTION_OPEN_FROM_QUICK_SETTINGS
        ) {
            pendingRollCallRequest = true
            dispatchOpenRollCallIfNeeded()
        }
    }

    private fun dispatchOpenRollCallIfNeeded() {
        if (dartReady && pendingRollCallRequest) {
            pendingRollCallRequest = false
            quickEntryChannel?.invokeMethod(OPEN_ROLL_CALL, null)
        }
    }

    companion object {
        const val ACTION_OPEN_FROM_QUICK_SETTINGS =
            "com.leafs825.secrandom_lite.action.OPEN_FROM_QUICK_SETTINGS"
        const val EXTRA_ROLLCALL_OPEN = "rollcall_open"
        const val OPEN_ROLL_CALL = "openRollCall"
        const val CONSUME_PENDING_ROLL_CALL = "consumePendingRollCall"
        const val QUICK_ENTRY_CHANNEL = "secrandom_lite/quick_entry"
    }
}
