package com.leafs825.secrandom_lite

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.TileService

class QuickSettingsTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        // 显式指定单色图标：磁贴图标会被系统按单色蒙版重绘，
        // 启动器图标是不透明彩色位图，会被涂成整块黑色。
        qsTile?.apply {
            icon = Icon.createWithResource(this@QuickSettingsTileService, R.drawable.ic_rollcall_tile)
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()

        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_FROM_QUICK_SETTINGS
            putExtra(MainActivity.EXTRA_ROLLCALL_OPEN, true)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        // Android 14 起禁止用 Intent 直接从 Tile 启动 Activity，必须包成
        // PendingIntent，否则 onClick 会抛 UnsupportedOperationException。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
