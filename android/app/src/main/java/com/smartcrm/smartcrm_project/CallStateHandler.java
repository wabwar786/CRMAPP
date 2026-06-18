package com.smartcrm.smartcrm_project;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.File;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class CallStateHandler {
    private static final String TAG = "CallStateHandler";
    private static final String CALL_CHANNEL = "com.your.app/call_state";
    private static final String RECORDING_CHANNEL = "com.your.app/call_recording";

    private static FlutterEngine flutterEngine;
    private static MethodChannel callChannel;
    private static MethodChannel recordingChannel;

    private static String currentLeadId;

    public static void setCurrentLeadId(String leadId) {
        currentLeadId = leadId;
    }

    public static String getCurrentLeadId() {
        return currentLeadId;
    }

    public static void setFlutterEngine(FlutterEngine engine) {
        if (engine != null) {
            flutterEngine = engine;
            callChannel = new MethodChannel(flutterEngine.getDartExecutor(), CALL_CHANNEL);
            recordingChannel = new MethodChannel(flutterEngine.getDartExecutor(), RECORDING_CHANNEL);
            Log.d(TAG, "FlutterEngine and channels initialized successfully");
        } else {
            Log.e(TAG, "Attempted to set null FlutterEngine");
        }
    }

    public static void notifyOutgoingCall(Context context, String number) {
        if (callChannel != null) {
            callChannel.invokeMethod("onOutgoingCall", number);
            Log.d(TAG, "Outgoing call notified: " + number);
        } else {
            Log.w(TAG, "Call channel not initialized, cannot notify outgoing call");
        }
    }

    public static void notifyIncomingCall(Context context, String number) {
        if (callChannel != null) {
            callChannel.invokeMethod("onIncomingCall", number);
            Log.d(TAG, "Incoming call notified: " + number);
        } else {
            Log.w(TAG, "Call channel not initialized, cannot notify incoming call");
        }
    }

    public static void notifyCallConnected(Context context, String number) {
        if (callChannel != null) {
            callChannel.invokeMethod("onCallConnected", number);
            Log.d(TAG, "Call connected notified: " + number);
        } else {
            Log.w(TAG, "Call channel not initialized, cannot notify call connected");
        }
    }

    public static void notifyCallDisconnected(Context context, String number, boolean wasConnected) {
        if (callChannel != null) {
            Map<String, Object> args = new HashMap<>();
            args.put("number", number);
            args.put("wasConnected", wasConnected);

            callChannel.invokeMethod("onCallDisconnected", args);
            Log.d(TAG, "Call disconnected notified: " + number + ", wasConnected: " + wasConnected);
        } else {
            Log.w(TAG, "Call channel not initialized, cannot notify call disconnected");
        }
    }

    public static void startRecording(Context context, String number) {
        if (recordingChannel != null) {
            recordingChannel.invokeMethod("startRecording", number, new MethodChannel.Result() {
                @Override
                public void success(Object result) {
                    Log.d(TAG, "Recording started successfully: " + result);
                }

                @Override
                public void error(String errorCode, String errorMessage, Object details) {
                    Log.e(TAG, "Failed to start recording: " + errorMessage);
                }

                @Override
                public void notImplemented() {
                    Log.e(TAG, "startRecording not implemented");
                }
            });
        } else {
            Log.w(TAG, "Recording channel not initialized, cannot start recording");
        }
    }

    public static String stopRecording(Context context) {
        if (recordingChannel == null) {
            Log.w(TAG, "Recording channel not initialized, cannot stop recording");
            return null;
        }

        final String[] resultPath = {null};
        final CountDownLatch latch = new CountDownLatch(1);

        Handler mainHandler = new Handler(Looper.getMainLooper());
        mainHandler.post(() -> {
            recordingChannel.invokeMethod("stopRecording", null, new MethodChannel.Result() {
                @Override
                public void success(Object result) {
                    if (result instanceof String) {
                        resultPath[0] = (String) result;
                        Log.d(TAG, "Recording stopped. File path: " + resultPath[0]);
                    } else {
                        Log.e(TAG, "Unexpected result type from stopRecording");
                    }
                    latch.countDown();
                }

                @Override
                public void error(String errorCode, String errorMessage, Object details) {
                    Log.e(TAG, "Error stopping recording: " + errorMessage);
                    latch.countDown();
                }

                @Override
                public void notImplemented() {
                    Log.e(TAG, "stopRecording not implemented");
                    latch.countDown();
                }
            });
        });

        try {
            boolean completed = latch.await(10, TimeUnit.SECONDS);
            if (!completed) {
                Log.e(TAG, "Timeout waiting for stopRecording result");
            }
        } catch (InterruptedException e) {
            Log.e(TAG, "Interrupted while waiting for recording stop", e);
            Thread.currentThread().interrupt();
        }

        return resultPath[0];
    }

    public static void notifyCallRecording(Context context, String number, String filePath, String leadId) {
        if (recordingChannel != null) {
            Map<String, Object> args = new HashMap<>();
            args.put("number", number);
            args.put("filePath", filePath);
            args.put("leadId", leadId);

            recordingChannel.invokeMethod("onCallRecording", args, new MethodChannel.Result() {
                @Override
                public void success(Object result) {
                    Log.d(TAG, "Recording notification sent successfully for: " + number);
                }

                @Override
                public void error(String errorCode, String errorMessage, Object details) {
                    Log.e(TAG, "Failed to notify recording: " + errorMessage);
                    cleanupFailedRecording(filePath);
                }

                @Override
                public void notImplemented() {
                    Log.e(TAG, "onCallRecording not implemented");
                    cleanupFailedRecording(filePath);
                }
            });
        } else {
            Log.w(TAG, "Recording channel not initialized, cannot notify recording");
            cleanupFailedRecording(filePath);
        }
    }

    public static void uploadRecordingToServer(Context context, String number, String filePath, String leadId) {
        try {
            File recordingFile = new File(filePath);
            if (!recordingFile.exists()) {
                Log.e(TAG, "Recording file not found at path: " + filePath);
                return;
            }

            OkHttpClient client = new OkHttpClient.Builder()
                    .connectTimeout(30, TimeUnit.SECONDS)
                    .writeTimeout(30, TimeUnit.SECONDS)
                    .readTimeout(30, TimeUnit.SECONDS)
                    .build();

            RequestBody requestBody = new MultipartBody.Builder()
                    .setType(MultipartBody.FORM)
                    .addFormDataPart("leadId", leadId)
                    .addFormDataPart("userId", getCurrentUserId(context))
                    .addFormDataPart("cCode", getCurrentCompanyCode(context))
                    .addFormDataPart("recording", recordingFile.getName(),
                            RequestBody.create(MediaType.parse("audio/mpeg"), recordingFile))
                    .build();

            Request request = new Request.Builder()
                    .url("http://54.209.25.95:3000/api/upload-recording")
                    .post(requestBody)
                    .build();

            client.newCall(request).enqueue(new Callback() {
                @Override
                public void onFailure(Call call, IOException e) {
                    Log.e(TAG, "Recording upload failed: " + e.getMessage());
                    cleanupFailedRecording(filePath);
                }

                @Override
                public void onResponse(Call call, Response response) throws IOException {
                    if (!response.isSuccessful()) {
                        Log.e(TAG, "Upload failed: " + response.code() + " - " + response.message());
                        cleanupFailedRecording(filePath);
                        return;
                    }

                    try {
                        String responseBody = response.body().string();
                        Log.d(TAG, "Recording upload successful: " + responseBody);
                        if (recordingFile.exists()) {
                            recordingFile.delete();
                            Log.d(TAG, "Recording file deleted after upload");
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Error processing upload response", e);
                    }
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Error uploading recording", e);
            cleanupFailedRecording(filePath);
        }
    }

    private static void cleanupFailedRecording(String filePath) {
        try {
            if (filePath != null) {
                File recordingFile = new File(filePath);
                if (recordingFile.exists()) {
                    recordingFile.delete();
                    Log.d(TAG, "Cleaned up failed recording file");
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error cleaning up recording file", e);
        }
    }

    // 🔧 Stub methods — Replace with actual logic to get userId and company code
    private static String getCurrentUserId(Context context) {
        // TODO: Get this from shared preferences or auth
        return "12345";
    }

    private static String getCurrentCompanyCode(Context context) {
        // TODO: Get this from shared preferences or auth
        return "COMP001";
    }
}
