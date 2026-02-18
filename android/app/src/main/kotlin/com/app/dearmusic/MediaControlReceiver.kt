// MediaControlReceiver.kt
package com.app.dearmusic

import android.content.*
import android.widget.Toast

class MediaControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.app.dearmusic.WIDGET_OPEN") {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (launch != null) context.startActivity(launch)
            else Toast.makeText(context, "Unable to open app", Toast.LENGTH_SHORT).show()
        }
        // Tidak ada lagi WIDGET_TOGGLE/NEXT/PREV di sini.
    }
}
