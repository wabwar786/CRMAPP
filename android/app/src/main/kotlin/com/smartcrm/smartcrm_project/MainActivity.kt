// ... [keep all your existing imports]
package com.smartcrm.smartcrm_project

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.provider.CallLog
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"

    private val CALL_LOG_CHANNEL = "com.your.app/call_tracker"
    private val RECORDING_CHANNEL = "com.your.app/call_recording"
    private val CALL_STATE_CHANNEL = "com.your.app/call_state"

    private val PERMISSION_REQUEST_CODE = 123
    private val MAX_CALL_LOG_QUERY_TIME_MS = TimeUnit.DAYS.toMillis(1)

    private val RECORDINGS_DIR = "SmartCRMRecordings"
    private var mediaRecorder: MediaRecorder? = null
    private var recordingFilePath: String? = null
    private var isRecording = false

    private var _currentCallPhoneNumber: String = ""
    private var _currentLeadId: String = ""
    private var _currentUserId: String = ""
    private var _currentCCode: String = ""

    private val RECORDING_PERMISSIONS = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        arrayOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.FOREGROUND_SERVICE
        )
    } else {
        arrayOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
            Manifest.permission.READ_EXTERNAL_STORAGE,
            Manifest.permission.FOREGROUND_SERVICE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        CallStateHandler.setFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_LOG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCallLogs" -> handleGetCallLogs(call, result)
                "getLatestCallLog" -> handleGetLatestCallLog(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> handleStartRecording(call, result)
                "stopRecording" -> handleStopRecording(result)
                "checkRecordingPermissions" -> handleCheckRecordingPermissions(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleStartRecording(call: MethodCall, result: MethodChannel.Result) {
        val phoneNumber = call.argument<String>("phoneNumber") ?: ""
        val leadId = call.argument<String>("leadId") ?: ""
        val userId = call.argument<String>("userId") ?: ""
        val cCode = call.argument<String>("cCode") ?: ""

        _currentCallPhoneNumber = phoneNumber
        _currentLeadId = leadId
        _currentUserId = userId
        _currentCCode = cCode

        if (phoneNumber.isNotEmpty()) {
            if (checkRecordingPermissions()) {
                try {
                    val filePath = startRecording(this, phoneNumber, leadId)
                    if (filePath != null) {
                        result.success(filePath)
                    } else {
                        result.error("RECORDING_FAILED", "Failed to start recording", null)
                    }
                } catch (e: Exception) {
                    result.error("RECORDING_ERROR", "Recording error: ${e.message}", null)
                }
            } else {
                requestRecordingPermissions()
                result.error("PERMISSION_DENIED", "Recording permissions not granted", null)
            }
        } else {
            result.error("INVALID_ARGUMENTS", "Phone number required", null)
        }
    }

    private fun handleStopRecording(result: MethodChannel.Result) {
        try {
            val filePath = stopRecording()
            handleCallRecording(_currentLeadId, filePath)
            result.success(filePath)
        } catch (e: Exception) {
            result.error("STOP_RECORDING_ERROR", "Error stopping recording: ${e.message}", null)
        }
    }

    private fun handleCheckRecordingPermissions(result: MethodChannel.Result) {
        if (checkRecordingPermissions()) {
            result.success(true)
        } else {
            result.success(false)
        }
    }

    private fun handleCallRecording(leadId: String, filePath: String?) {
        if (!isRecording || filePath.isNullOrEmpty()) return

        Log.d(TAG, "Preparing to upload recording for lead: $leadId")

        val intent = Intent(this, CallRecordingService::class.java).apply {
            putExtra("filePath", filePath)
            putExtra("leadId", leadId)
            putExtra("phoneNumber", _currentCallPhoneNumber)
            putExtra("userId", _currentUserId)
            putExtra("cCode", _currentCCode)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun startRecording(context: Context, phoneNumber: String, leadId: String? = null): String? {
        val recordingsDir = File(context.getExternalFilesDir(null), RECORDINGS_DIR)
        if (!recordingsDir.exists()) recordingsDir.mkdirs()

        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        val fileName = "REC_${phoneNumber}_${leadId ?: "NA"}_$timestamp.3gp"
        val outputFile = File(recordingsDir, fileName)

        mediaRecorder = MediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
            setAudioEncoder(MediaRecorder.AudioEncoder.AMR_NB)
            setOutputFile(outputFile.absolutePath)
            prepare()
            start()
        }

        isRecording = true
        recordingFilePath = outputFile.absolutePath
        return recordingFilePath
    }

    private fun stopRecording(): String? {
        if (isRecording) {
            mediaRecorder?.apply {
                stop()
                release()
            }
            isRecording = false
        }
        return recordingFilePath
    }

    private fun checkCallLogPermissions(): Boolean {
        val permissions = mutableListOf(Manifest.permission.READ_CALL_LOG)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            permissions.add(Manifest.permission.READ_PHONE_STATE)
        }
        return permissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun checkRecordingPermissions(): Boolean {
        return RECORDING_PERMISSIONS.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestCallLogPermissions() {
        val permissions = mutableListOf(Manifest.permission.READ_CALL_LOG)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            permissions.add(Manifest.permission.READ_PHONE_STATE)
        }
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    private fun requestRecordingPermissions() {
        ActivityCompat.requestPermissions(this, RECORDING_PERMISSIONS, PERMISSION_REQUEST_CODE)
    }

    private fun handleGetCallLogs(call: MethodCall, result: MethodChannel.Result) {
        val phoneNumber = call.argument<String>("phoneNumber")
        val since = call.argument<Long>("since")
        val silent = call.argument<Boolean>("silent") ?: false

        if (phoneNumber.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "Phone number not provided", null)
            return
        }

        if (checkCallLogPermissions()) {
            try {
                val logs = getCallLogs(
                    phoneNumber,
                    since ?: System.currentTimeMillis() - MAX_CALL_LOG_QUERY_TIME_MS
                )
                result.success(logs)
            } catch (e: Exception) {
                result.error("QUERY_FAILED", "Failed to query call log: ${e.message}", null)
            }
        } else {
            if (!silent) requestCallLogPermissions()
            result.error("PERMISSION_DENIED", "Call log permissions not granted", null)
        }
    }

    private fun handleGetLatestCallLog(call: MethodCall, result: MethodChannel.Result) {
        val phoneNumber = call.argument<String>("phoneNumber")
        val since = call.argument<Long>("since")
        val silent = call.argument<Boolean>("silent") ?: false

        if (phoneNumber.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "Phone number not provided", null)
            return
        }

        if (checkCallLogPermissions()) {
            try {
                val log = getLatestCallLog(
                    phoneNumber,
                    since ?: System.currentTimeMillis() - MAX_CALL_LOG_QUERY_TIME_MS
                )
                result.success(log)
            } catch (e: Exception) {
                result.error("QUERY_FAILED", "Failed to query call log: ${e.message}", null)
            }
        } else {
            if (!silent) requestCallLogPermissions()
            result.error("PERMISSION_DENIED", "Call log permissions not granted", null)
        }
    }

    private fun getCallLogs(phoneNumber: String, since: Long): List<Map<String, Any?>> {
        val callLogs = mutableListOf<Map<String, Any?>>()
        var cursor: Cursor? = null

        try {
            val normalizedNumber = normalizePhoneNumber(phoneNumber)
            val projection = arrayOf(
                CallLog.Calls._ID,
                CallLog.Calls.NUMBER,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION,
                CallLog.Calls.TYPE,
                CallLog.Calls.CACHED_NAME
            )

            val selection = "${CallLog.Calls.DATE} >= ? AND (" +
                    "${CallLog.Calls.NUMBER} = ? OR " +
                    "${CallLog.Calls.NUMBER} LIKE ? OR " +
                    "${CallLog.Calls.NUMBER} LIKE ? OR " +
                    "${CallLog.Calls.NUMBER} LIKE ?)"

            val selectionArgs = arrayOf(
                since.toString(),
                normalizedNumber,
                "%${normalizedNumber.takeLast(10)}",
                "%${normalizedNumber.takeLast(7)}",
                normalizedNumber.replace("+", "")
            )

            val sortOrder = "${CallLog.Calls.DATE} DESC"

            cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )

            cursor?.use {
                while (it.moveToNext()) {
                    callLogs.add(createCallLogMap(it))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting call logs", e)
        } finally {
            cursor?.close()
        }

        return callLogs
    }

    private fun getLatestCallLog(phoneNumber: String, since: Long): Map<String, Any?>? {
        var cursor: Cursor? = null

        try {
            val normalizedNumber = normalizePhoneNumber(phoneNumber)
            val projection = arrayOf(
                CallLog.Calls._ID,
                CallLog.Calls.NUMBER,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION,
                CallLog.Calls.TYPE,
                CallLog.Calls.CACHED_NAME
            )

            val selection = "${CallLog.Calls.DATE} >= ? AND (" +
                    "${CallLog.Calls.NUMBER} = ? OR " +
                    "${CallLog.Calls.NUMBER} LIKE ? OR " +
                    "${CallLog.Calls.NUMBER} LIKE ? OR " +
                    "${CallLog.Calls.NUMBER} LIKE ?)"

            val selectionArgs = arrayOf(
                since.toString(),
                normalizedNumber,
                "%${normalizedNumber.takeLast(10)}",
                "%${normalizedNumber.takeLast(7)}",
                normalizedNumber.replace("+", "")
            )

            val sortOrder = "${CallLog.Calls.DATE} DESC"

            cursor = contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )

            cursor?.use {
                if (it.moveToFirst()) {
                    return createCallLogMap(it)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting latest call log", e)
        } finally {
            cursor?.close()
        }

        return null
    }

    private fun createCallLogMap(cursor: Cursor): Map<String, Any?> {
        val durationSeconds = cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls.DURATION))
        val callType = cursor.getInt(cursor.getColumnIndexOrThrow(CallLog.Calls.TYPE))
        val isMissedCall = callType == CallLog.Calls.MISSED_TYPE

        return mapOf(
            "id" to cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls._ID)),
            "number" to (cursor.getString(cursor.getColumnIndexOrThrow(CallLog.Calls.NUMBER)) ?: ""),
            "date" to cursor.getLong(cursor.getColumnIndexOrThrow(CallLog.Calls.DATE)),
            "duration" to if (isMissedCall) "00:00:00" else formatDuration(durationSeconds),
            "raw_duration_seconds" to if (isMissedCall) 0 else durationSeconds,
            "type" to callType,
            "subStatus" to when (callType) {
                CallLog.Calls.INCOMING_TYPE -> "Incoming"
                CallLog.Calls.OUTGOING_TYPE -> "Outgoing"
                CallLog.Calls.MISSED_TYPE -> "Missed"
                CallLog.Calls.REJECTED_TYPE -> "Rejected"
                CallLog.Calls.BLOCKED_TYPE -> "Blocked"
                else -> "Unknown"
            },
            "name" to (cursor.getString(cursor.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)) ?: "")
        )
    }

    private fun formatDuration(totalSeconds: Long): String {
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return String.format("%02d:%02d:%02d", hours, minutes, seconds)
    }

    private fun normalizePhoneNumber(phoneNumber: String): String {
        return phoneNumber.replace(Regex("[^0-9+]"), "")
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                Log.d(TAG, "Permissions granted")
            } else {
                Log.d(TAG, "Permissions denied")
            }
        }
    }

    override fun onDestroy() {
        if (isRecording) {
            stopRecording()
        }
        super.onDestroy()
    }
}
