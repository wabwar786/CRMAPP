package com.smartcrm.smartcrm_project

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

class CallRecordingService : Service() {
    private val tag = "CallRecordingService"
    private val channelId = "CallRecordingUploadChannel"
    private val notificationId = 101
    private val uploadUrl = "https://smartcrmbackend-production-56c0.up.railway.app/api/upload-recording"

    private var recordingFilePath: String? = null
    private var phoneNumber: String? = null
    private var leadId: String? = null
    private var userId: String? = null
    private var cCode: String? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        recordingFilePath = intent?.getStringExtra("filePath")
        leadId = intent?.getStringExtra("leadId")
        phoneNumber = intent?.getStringExtra("phoneNumber")
        userId = intent?.getStringExtra("userId")
        cCode = intent?.getStringExtra("cCode")

        startForeground(notificationId, createNotification())

        val path = recordingFilePath
        if (path.isNullOrBlank()) {
            Log.e(tag, "No recording file path received")
            stopSelf()
            return START_NOT_STICKY
        }

        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            Log.e(tag, "Recording file missing or empty: $path")
            stopSelf()
            return START_NOT_STICKY
        }

        uploadRecording(file)
        return START_NOT_STICKY
    }

    private fun uploadRecording(file: File) {
        Log.d(tag, "Uploading recording: ${file.absolutePath} (${file.length()} bytes)")

        val requestBody = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("recording", file.name, file.asRequestBody("audio/3gpp".toMediaTypeOrNull()))
            .addFormDataPart("leadId", leadId ?: "")
            .addFormDataPart("userId", userId ?: "")
            .addFormDataPart("cCode", cCode ?: "")
            .addFormDataPart("phoneNumber", phoneNumber ?: "")
            .build()

        val request = Request.Builder()
            .url(uploadUrl)
            .post(requestBody)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(tag, "Upload failed: ${e.message}", e)
                notifyUploadResult(false, e.message ?: "Upload failed")
                cleanupFile(file)
                stopSelf()
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val responseBody = it.body?.string().orEmpty()
                    if (it.isSuccessful) {
                        Log.d(tag, "Upload successful: $responseBody")
                        notifyUploadResult(true, responseBody.ifBlank { "Success" })
                    } else {
                        Log.e(tag, "Upload failed: ${it.code} - $responseBody")
                        notifyUploadResult(false, "HTTP ${it.code}")
                    }
                    cleanupFile(file)
                    stopSelf()
                }
            }
        })
    }

    private fun notifyUploadResult(success: Boolean, message: String) {
        val intent = Intent("com.smartcrm.UPLOAD_RESULT")
        intent.putExtra("success", success)
        intent.putExtra("message", message)
        intent.putExtra("filePath", recordingFilePath ?: "")
        intent.putExtra("leadId", leadId ?: "")
        sendBroadcast(intent)
    }

    private fun cleanupFile(file: File) {
        try {
            if (file.exists()) file.delete()
        } catch (e: Exception) {
            Log.e(tag, "Could not delete recording file", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "SmartCRM Recording Upload",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Uploads completed CRM call recordings" }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("SmartCRM")
            .setContentText("Uploading call recording")
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(false)
            .build()
    }
}
