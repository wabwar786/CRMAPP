package com.smartcrm.smartcrm_project;

import android.app.Application;
import android.content.Intent;
import android.content.IntentFilter;
import android.telephony.TelephonyManager;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;

public class MainApplication extends Application {
    private static final String TAG = "MainApplication";
    private static final String FLUTTER_ENGINE_ID = "smartcrm_engine";

    @Override
    public void onCreate() {
        super.onCreate();
        
        // Initialize FlutterEngine
        FlutterEngine flutterEngine = new FlutterEngine(this);
        flutterEngine.getDartExecutor().executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        );
        
        // Cache the FlutterEngine
        FlutterEngineCache.getInstance().put(FLUTTER_ENGINE_ID, flutterEngine);
        
        // Initialize CallStateHandler with the FlutterEngine
        CallStateHandler.setFlutterEngine(flutterEngine);
        
        // Register CallReceiver
        IntentFilter filter = new IntentFilter();
        filter.addAction(TelephonyManager.ACTION_PHONE_STATE_CHANGED);
        filter.addAction(Intent.ACTION_NEW_OUTGOING_CALL);
        registerReceiver(new CallReceiver(), filter);
    }
}