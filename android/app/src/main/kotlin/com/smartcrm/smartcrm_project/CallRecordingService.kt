package com.smartcrm.smartcrm_project

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

class CallRecordingService : Service() {
    private val TAG = "CallRecordingService"
    private val CHANNEL_ID = "CallRecordingChannel"
    private val NOTIFICATION_ID = 101
    private val UPLOAD_URL = "http://54.209.25.95:3000/api/upload-recording"

    private var mediaRecorder: MediaRecorder? = null
    private var recordingFilePath: String? = null
    private var phoneNumber: String? = null
    private var leadId: String? = null
    private var userId: String? = null
    private var cCode: String? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        phoneNumber = intent?.getStringExtra("phoneNumber")
        leadId = intent?.getStringExtra("leadId")
        recordingFilePath = intent?.getStringExtra("filePath")
        userId = intent?.getStringExtra("userId")
        cCode = intent?.getStringExtra("cCode")

        if (phoneNumber == null || recordingFilePath == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, createNotification())

        try {
            startRecording()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting recording", e)
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun startRecording() {
        try {
            mediaRecorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(recordingFilePath)

                prepare()
                start()
                Log.d(TAG, "Recording started: $recordingFilePath")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Recording failed", e)
            stopSelf()
        }
    }

    override fun onDestroy() {
        stopRecordingAndUpload()
        super.onDestroy()
    }

    private fun stopRecordingAndUpload() {
        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
            Log.d(TAG, "Recording stopped successfully")

            recordingFilePath?.let { path ->
                val file = File(path)
                if (file.exists()) {
                    uploadRecording(file)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recording", e)
        } finally {
            mediaRecorder = null
        }
    }

    private fun uploadRecording(file: File) {
        if (!file.exists()) {
            Log.e(TAG, "Recording file not found at path: ${file.absolutePath}")
            return
        }

        Log.d(TAG, "Starting upload for file: ${file.name} (${file.length()} bytes)")

        val requestBody = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("recording", file.name, file.asRequestBody("audio/mpeg".toMediaTypeOrNull()))
            .addFormDataPart("leadId", leadId ?: "")
            .addFormDataPart("userId", userId ?: "")
            .addFormDataPart("cCode", cCode ?: "")
            .addFormDataPart("phoneNumber", phoneNumber ?: "")
            .build()

        val request = Request.Builder()
            .url(UPLOAD_URL)
            .post(requestBody)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "Upload failed: ${e.message}")
                notifyUploadResult(success = false, message = e.message ?: "Unknown error")
                cleanupFile(file)
            }

            override fun onResponse(call: Call, response: Response) {
                try {
                    val responseBody = response.body?.string()
                    if (response.isSuccessful) {
                        Log.d(TAG, "Upload successful: $responseBody")
                        notifyUploadResult(success = true, message = responseBody ?: "Success")
                    } else {
                        Log.e(TAG, "Upload failed: ${response.code} - ${response.message}")
                        notifyUploadResult(success = false, message = "HTTP ${response.code}")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing response", e)
                    notifyUploadResult(success = false, message = "Exception: ${e.message}")
                } finally {
                    cleanupFile(file)
                }
            }
        })
    }

    private fun notifyUploadResult(success: Boolean, message: String) {
        // If needed, broadcast result to Flutter side instead of MethodChannel
        val intent = Intent("com.smartcrm.UPLOAD_RESULT")
        intent.putExtra("success", success)
        intent.putExtra("message", message)
        intent.putExtra("filePath", recordingFilePath ?: "")
        intent.putExtra("leadId", leadId ?: "")
        sendBroadcast(intent)
    }

    private fun cleanupFile(file: File) {
        try {
            if (file.exists()) {
                val deleted = file.delete()
                Log.d(TAG, "File cleanup: ${if (deleted) "success" else "failed"}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up file", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Call Recording Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Recording call audio"
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Call Recording")
            .setContentText("Recording call with $phoneNumber")
            .setSmallIcon(R.drawable.ic_notification) // ensure this exists in res/drawable
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
