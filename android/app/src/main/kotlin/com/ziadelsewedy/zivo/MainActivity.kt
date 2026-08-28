package com.ziadelsewedy.zivo

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var audioRoute: AudioRoute? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioRoute = AudioRoute(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audioRoute?.dispose()
        audioRoute = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/**
 * Reports the current OS audio output route (Bluetooth / wired / speaker) to
 * Flutter over `zivo/audio_route` (one-shot `current`) and
 * `zivo/audio_route/events` (live changes), backed by [AudioManager].
 *
 * There is no public API for the "currently active" output on Android, so
 * [pickActive] applies a preference order (BT > wired/USB > builtin speaker).
 * Android exposes no stable public accessory-battery API here, so `battery` is
 * always omitted.
 */
private class AudioRoute(
    context: Context,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: AudioDeviceCallback? = null

    init {
        MethodChannel(messenger, "zivo/audio_route").setMethodCallHandler { call, result ->
            if (call.method == "current") result.success(currentRoute()) else result.notImplemented()
        }
        EventChannel(messenger, "zivo/audio_route/events").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = emit()
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) = emit()
        }
        callback = cb
        audioManager.registerAudioDeviceCallback(cb, handler)
        emit() // seed the stream with the current route
    }

    override fun onCancel(arguments: Any?) = dispose()

    fun dispose() {
        callback?.let { audioManager.unregisterAudioDeviceCallback(it) }
        callback = null
        sink = null
    }

    private fun emit() {
        sink?.success(currentRoute())
    }

    private fun currentRoute(): Map<String, Any?>? {
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val device = pickActive(devices) ?: return null
        return mapOf(
            "name" to friendlyName(device),
            "kind" to kindFor(device.type),
        )
    }

    /** No public "active output" query pre-API-31; prefer external over builtin. */
    private fun pickActive(devices: Array<AudioDeviceInfo>): AudioDeviceInfo? {
        devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }?.let { return it }
        devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET)
        }?.let { return it }
        devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }?.let { return it }
        return devices.firstOrNull()
    }

    private fun kindFor(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "headphones"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "phone"
        else ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                type == AudioDeviceInfo.TYPE_USB_HEADSET
            ) {
                "headphones"
            } else {
                "speaker"
            }
    }

    private fun friendlyName(device: AudioDeviceInfo): String {
        val product = device.productName?.toString()?.trim()
        return when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone speaker"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
            else -> if (!product.isNullOrEmpty()) product else "Audio output"
        }
    }
}
