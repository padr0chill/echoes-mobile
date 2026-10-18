package com.echoes.echoes_mobile

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// audio_service: экран связан с фоновым сервисом воспроизведения
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // «Назад» на главной вкладке — свернуть, как музыкальные плееры (музыка играет дальше)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "echoes/app").setMethodCallHandler { call, result ->
            if (call.method == "toBack") {
                moveTaskToBack(true)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
