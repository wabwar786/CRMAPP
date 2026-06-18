package com.smartcrm.smartcrm_project;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.os.Build;
import android.provider.CallLog;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;

public class BackgroundCallLogger {
    private static final String TAG = "BackgroundCallLogger";
    private static final String BASE_URL = "https://smartcrmbackend-production-56c0.up.railway.app";
    private static final String CALL_LOG_URL = BASE_URL + "/api/call-log";
    private static final String FLUTTER_PREFS = "FlutterSharedPreferences";
    private static final String CHANNEL_ID = "smartcrm_call_logger";
    private static final int NOTIFICATION_ID = 9091;
    private static final long LOOKBACK_MS = TimeUnit.MINUTES.toMillis(5);

    private static final OkHttpClient client = new OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build();

    public static void logLatestCrmCall(Context context, String preferredNumber) {
        try {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "READ_CALL_LOG not granted. Cannot background log call.");
                return;
            }

            SharedPreferences prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE);
            JSONArray leads = readLeadsCache(prefs);
            if (leads.length() == 0) {
                Log.w(TAG, "No cached CRM leads found. Open app once after login to cache leads.");
                return;
            }

            JSONObject callLog = getLatestCallLog(context, preferredNumber);
            if (callLog == null) return;

            JSONObject matchedLead = findLeadByNumber(leads, callLog.optString("number"));
            if (matchedLead == null) {
                Log.d(TAG, "Unknown/personal number ignored: " + callLog.optString("number"));
                return;
            }

            String callUniqueId = callLog.optLong("date") + "_" + callLog.optLong("raw_duration_seconds") + "_" + callLog.optInt("type");
            String lastSaved = prefs.getString("flutter.native_last_call_unique_id", "");
            if (callUniqueId.equals(lastSaved)) {
                Log.d(TAG, "Duplicate call ignored: " + callUniqueId);
                return;
            }
            prefs.edit().putString("flutter.native_last_call_unique_id", callUniqueId).apply();

            JSONObject pendingInfo = buildPendingInfo(matchedLead, callLog, callUniqueId);
            appendPendingRemark(prefs, pendingInfo);
            postCallLog(context, prefs, matchedLead, callLog, callUniqueId);
            showPendingNotification(context, matchedLead.optString("c_name", "Customer"), callLog.optString("subStatus", "Call"));
        } catch (Exception e) {
            Log.e(TAG, "Failed to background log call", e);
        }
    }

    private static JSONArray readLeadsCache(SharedPreferences prefs) {
        try {
            String raw = prefs.getString("flutter.crm_leads_cache", "[]");
            if (raw == null || raw.trim().isEmpty()) raw = "[]";
            return new JSONArray(raw);
        } catch (Exception e) {
            Log.e(TAG, "Invalid leads cache", e);
            return new JSONArray();
        }
    }

    private static JSONObject getLatestCallLog(Context context, String preferredNumber) {
        Cursor cursor = null;
        try {
            long since = System.currentTimeMillis() - LOOKBACK_MS;
            String selection = CallLog.Calls.DATE + " >= ?";
            String[] args = new String[]{String.valueOf(since)};

            cursor = context.getContentResolver().query(
                    CallLog.Calls.CONTENT_URI,
                    new String[]{CallLog.Calls._ID, CallLog.Calls.NUMBER, CallLog.Calls.DATE, CallLog.Calls.DURATION, CallLog.Calls.TYPE, CallLog.Calls.CACHED_NAME},
                    selection,
                    args,
                    CallLog.Calls.DATE + " DESC"
            );

            if (cursor == null) return null;

            String preferredKey = phoneKey(preferredNumber == null ? "" : preferredNumber);
            JSONObject first = null;

            while (cursor.moveToNext()) {
                JSONObject item = mapCursor(cursor);
                if (first == null) first = item;
                if (!preferredKey.isEmpty() && phoneMatches(preferredKey, phoneKey(item.optString("number")))) {
                    return item;
                }
            }
            return first;
        } catch (Exception e) {
            Log.e(TAG, "CallLog query failed", e);
            return null;
        } finally {
            if (cursor != null) cursor.close();
        }
    }

    private static JSONObject mapCursor(Cursor c) throws Exception {
        long duration = c.getLong(c.getColumnIndexOrThrow(CallLog.Calls.DURATION));
        int type = c.getInt(c.getColumnIndexOrThrow(CallLog.Calls.TYPE));
        boolean missed = type == CallLog.Calls.MISSED_TYPE;
        JSONObject o = new JSONObject();
        o.put("id", c.getLong(c.getColumnIndexOrThrow(CallLog.Calls._ID)));
        o.put("number", safe(c.getString(c.getColumnIndexOrThrow(CallLog.Calls.NUMBER))));
        o.put("date", c.getLong(c.getColumnIndexOrThrow(CallLog.Calls.DATE)));
        o.put("duration", missed ? "00:00:00" : formatDuration(duration));
        o.put("raw_duration_seconds", missed ? 0 : duration);
        o.put("type", type);
        o.put("subStatus", subStatus(type));
        o.put("name", safe(c.getString(c.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME))));
        return o;
    }

    private static JSONObject findLeadByNumber(JSONArray leads, String number) {
        String key = phoneKey(number);
        if (key.isEmpty()) return null;
        for (int i = 0; i < leads.length(); i++) {
            JSONObject lead = leads.optJSONObject(i);
            if (lead == null) continue;
            String leadKey = phoneKey(lead.optString("c_phone"));
            if (!leadKey.isEmpty() && phoneMatches(key, leadKey)) return lead;
        }
        return null;
    }

    private static boolean phoneMatches(String a, String b) {
        return a.equals(b) || a.endsWith(b) || b.endsWith(a);
    }

    private static String phoneKey(String phone) {
        if (phone == null) return "";
        String cleaned = phone.replaceAll("[^0-9+]", "");
        String digits = cleaned.replace("+", "");
        if (digits.length() <= 10) return digits;
        return digits.substring(digits.length() - 10);
    }

    private static JSONObject buildPendingInfo(JSONObject lead, JSONObject callLog, String callUniqueId) throws Exception {
        JSONObject pending = new JSONObject();
        pending.put("leadId", lead.optString("leadid"));
        pending.put("leadName", lead.optString("c_name", "Customer"));
        pending.put("phone", callLog.optString("number"));
        pending.put("duration", callLog.optString("duration", "00:00:00"));
        pending.put("durationSeconds", callLog.optLong("raw_duration_seconds", 0));
        pending.put("subStatus", callLog.optString("subStatus", "Call"));
        pending.put("callDate", isoDate(callLog.optLong("date")));
        pending.put("callUniqueId", callUniqueId);
        pending.put("pendingKey", lead.optString("leadid") + "_" + callLog.optLong("date") + "_" + callLog.optString("subStatus"));
        return pending;
    }

    private static void appendPendingRemark(SharedPreferences prefs, JSONObject item) {
        try {
            String raw = prefs.getString("flutter.pending_call_remarks", "[]");
            JSONArray arr = new JSONArray(raw == null || raw.isEmpty() ? "[]" : raw);
            String newKey = item.optString("pendingKey");
            JSONArray filtered = new JSONArray();
            for (int i = 0; i < arr.length(); i++) {
                JSONObject old = arr.optJSONObject(i);
                if (old == null || !newKey.equals(old.optString("pendingKey"))) filtered.put(arr.get(i));
            }
            filtered.put(item);
            prefs.edit().putString("flutter.pending_call_remarks", filtered.toString()).apply();
        } catch (Exception e) {
            Log.e(TAG, "Failed to append pending remark", e);
        }
    }

    private static void postCallLog(Context context, SharedPreferences prefs, JSONObject lead, JSONObject callLog, String callUniqueId) throws Exception {
        String userId = prefs.getString("flutter.userId", "");
        String cCode = prefs.getString("flutter.cCode", "");
        String username = prefs.getString("flutter.username", "");
        if (userId.isEmpty() || cCode.isEmpty()) {
            Log.w(TAG, "Missing userId/cCode. Cannot upload background call log.");
            return;
        }

        JSONObject log = new JSONObject();
        log.put("callDuration", callLog.optString("duration", "00:00:00"));
        log.put("callStatus", determineCallStatus(callLog.optLong("raw_duration_seconds", 0)));
        log.put("callType", "Phone");
        log.put("subStatus", callLog.optString("subStatus", "Call"));
        log.put("callLogDate", isoDate(callLog.optLong("date")));
        log.put("callUniqueId", callUniqueId);
        log.put("remarksPending", true);

        JSONArray logs = new JSONArray();
        logs.put(log);

        JSONObject body = new JSONObject();
        body.put("leadId", lead.optString("leadid"));
        body.put("userId", userId);
        body.put("cCode", cCode);
        body.put("username", username);
        body.put("callLogs", logs);

        RequestBody requestBody = RequestBody.create(body.toString(), MediaType.parse("application/json; charset=utf-8"));
        Request request = new Request.Builder().url(CALL_LOG_URL).post(requestBody).build();
        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                Log.e(TAG, "Background call log upload failed: " + e.getMessage());
            }

            @Override
            public void onResponse(Call call, Response response) throws IOException {
                try {
                    if (response.isSuccessful()) {
                        Log.d(TAG, "Background call log uploaded: " + callUniqueId);
                    } else {
                        Log.e(TAG, "Background call log upload failed HTTP " + response.code());
                    }
                } finally {
                    response.close();
                }
            }
        });
    }

    private static void showPendingNotification(Context context, String customerName, String subStatus) {
        try {
            createNotificationChannel(context);
            Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
            PendingIntent pi = null;
            if (launchIntent != null) {
                launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE : PendingIntent.FLAG_UPDATE_CURRENT;
                pi = PendingIntent.getActivity(context, 0, launchIntent, flags);
            }
            NotificationCompat.Builder b = new NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(context.getApplicationInfo().icon)
                    .setContentTitle("CRM call logged")
                    .setContentText(subStatus + " - " + customerName + ". Tap to add remarks.")
                    .setAutoCancel(true)
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT);
            if (pi != null) b.setContentIntent(pi);
            NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (manager != null) manager.notify(NOTIFICATION_ID, b.build());
        } catch (Exception e) {
            Log.e(TAG, "Notification failed", e);
        }
    }

    private static void createNotificationChannel(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "SmartCRM Call Logger", NotificationManager.IMPORTANCE_DEFAULT);
            channel.setDescription("Notifications for CRM calls pending remarks");
            NotificationManager manager = context.getSystemService(NotificationManager.class);
            if (manager != null) manager.createNotificationChannel(channel);
        }
    }

    private static String subStatus(int type) {
        if (type == CallLog.Calls.INCOMING_TYPE) return "Incoming";
        if (type == CallLog.Calls.OUTGOING_TYPE) return "Outgoing";
        if (type == CallLog.Calls.MISSED_TYPE) return "Missed";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && type == CallLog.Calls.REJECTED_TYPE) return "Rejected";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && type == CallLog.Calls.BLOCKED_TYPE) return "Blocked";
        return "Unknown";
    }

    private static String determineCallStatus(long seconds) {
        if (seconds <= 0) return "Not Picked";
        if (seconds <= 60) return "Connected";
        if (seconds <= 120) return "Verified";
        return "Quality";
    }

    private static String formatDuration(long totalSeconds) {
        long h = totalSeconds / 3600;
        long m = (totalSeconds % 3600) / 60;
        long s = totalSeconds % 60;
        return String.format(Locale.US, "%02d:%02d:%02d", h, m, s);
    }

    private static String isoDate(long millis) {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        sdf.setTimeZone(TimeZone.getTimeZone("UTC"));
        return sdf.format(new Date(millis));
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
