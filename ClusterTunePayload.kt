package com.wuyr.jdwp_injector_test

import android.app.Application
import android.os.Handler
import android.os.Looper
import android.widget.Toast

/**
 * ClusterTune injection payload.
 *
 * This is the code that runs INSIDE GameAssistant (uid=system) after the
 * JDWP injection. It replaces wuyr's demo showDialog() payload.
 *
 * All it does: launch our pre-placed agent script as a detached process.
 * The agent (ct_agent.sh) then polls /sdcard/ClusterTune/ct_profile and
 * applies CPU frequency caps. Because THIS code runs as system, the
 * child process it spawns is also system - which is what lets the agent
 * write scaling_max_freq.
 *
 * IMPORTANT (the bug fix): we do NOT push the whole agent through JDWP.
 * The agent script is pre-placed on /sdcard by ClusterTune (or adb).
 * Here we only run a SHORT command to launch it. This avoids the
 * long-argument truncation that broke the earlier all-in-one approach.
 *
 * ADAPTION NOTE: wuyr's framework injects a dex and invokes an entry
 * point. Match wuyr's expected entry signature. In their demo the
 * injected class exposes a no-arg function (e.g. showDialog) that the
 * injector calls. Mirror that: expose launchAgent() with the same
 * shape/visibility wuyr's injector expects, and point the injector's
 * entry method name at "launchAgent" (see BUILD_AND_TEST.md).
 */
object ClusterTunePayload {

    // wuyr's injected code has access to the target's Application via the
    // same mechanism their demo uses ($application). Keep that hook.
    @JvmStatic
    lateinit var application: Application

    private const val AGENT_PATH = "/sdcard/ClusterTune/ct_agent.sh"

    /**
     * Entry point the injector invokes inside GameAssistant.
     * Launches the agent detached, then (optionally) toasts for a visible
     * confirmation during prototyping.
     */
    @JvmStatic
    fun launchAgent() {
        val result = try {
            // Launch detached so it survives after the debugger disconnects.
            // setsid/nohup keeps it alive; redirect so it doesn't block.
            val cmd = arrayOf(
                "/system/bin/sh", "-c",
                "nohup sh $AGENT_PATH >/dev/null 2>&1 &"
            )
            Runtime.getRuntime().exec(cmd)
            "ClusterTune: agent launch dispatched"
        } catch (t: Throwable) {
            "ClusterTune: launch FAILED: ${t.message}"
        }

        // Optional visible confirmation during prototyping. Remove for prod.
        try {
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(application, result, Toast.LENGTH_LONG).show()
            }
        } catch (_: Throwable) {
            // GameAssistant may have no foreground UI; ignore. The real
            // proof is the ct_status file, not the toast.
        }
    }
}
