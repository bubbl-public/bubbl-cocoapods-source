package tech.bubbl.reactnative

import android.app.Activity
import android.content.Intent
import tech.bubbl.sdk.BubblNotificationTapPresentation
import tech.bubbl.sdk.BubblSdk

object BubblSdkNotificationIntents {
    @JvmStatic
    fun open(activity: Activity, intent: Intent?): Boolean =
        BubblSdk.openNotificationIntent(activity, intent)

    @JvmStatic
    fun openDefaultModal(activity: Activity, intent: Intent?): Boolean =
        BubblSdk.openNotificationIntent(activity, intent, BubblNotificationTapPresentation.DefaultModal)

    @JvmStatic
    fun openHostModal(activity: Activity, intent: Intent?): Boolean =
        BubblSdk.openNotificationIntent(activity, intent, BubblNotificationTapPresentation.HostModal)

    @JvmStatic
    fun open(activity: Activity, intent: Intent?, useDefaultModal: Boolean): Boolean =
        BubblSdk.openNotificationIntent(
            activity,
            intent,
            if (useDefaultModal) {
                BubblNotificationTapPresentation.DefaultModal
            } else {
                BubblNotificationTapPresentation.HostModal
            }
        )
}
