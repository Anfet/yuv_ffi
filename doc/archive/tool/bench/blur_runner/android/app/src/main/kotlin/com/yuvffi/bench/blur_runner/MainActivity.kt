package com.yuvffi.bench.blur_runner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "blur_runner/files")
            .setMethodCallHandler { call, result ->
                if (call.method == "externalFilesDir") result.success(getExternalFilesDir(null)?.absolutePath)
                else result.notImplemented()
            }
    }
}
