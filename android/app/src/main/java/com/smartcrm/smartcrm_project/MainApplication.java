package com.smartcrm.smartcrm_project;

import android.app.Application;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;

public class MainApplication extends Application {
    private static final String FLUTTER_ENGINE_ID = "smartcrm_engine";

    @Override
    public void onCreate() {
        super.onCreate();

        FlutterEngine flutterEngine = new FlutterEngine(this);
        flutterEngine.getDartExecutor().executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
        );
        FlutterEngineCache.getInstance().put(FLUTTER_ENGINE_ID, flutterEngine);
        CallStateHandler.setFlutterEngine(flutterEngine);

        // CallReceiver is declared in AndroidManifest.xml.
        // Do not dynamically register it here, otherwise call events can fire twice.
    }
}
