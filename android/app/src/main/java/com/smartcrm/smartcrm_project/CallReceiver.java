package com.smartcrm.smartcrm_project;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.telephony.TelephonyManager;
import android.util.Log;

public class CallReceiver extends BroadcastReceiver {
    private static final String TAG = "CallReceiver";
    private static String lastState = TelephonyManager.EXTRA_STATE_IDLE;
    private static boolean isIncoming = false;
    private static String savedNumber;

    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            String action = intent.getAction();

            if (action == null) return;

            if (Intent.ACTION_NEW_OUTGOING_CALL.equals(action)) {
                handleOutgoingCall(context, intent);
            } else {
                handleIncomingCall(context, intent);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error in onReceive: " + e.getMessage(), e);
        }
    }

    private void handleOutgoingCall(Context context, Intent intent) {
        savedNumber = intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER);
        Log.d(TAG, "Outgoing call to: " + savedNumber);
        CallStateHandler.notifyOutgoingCall(context, savedNumber);

        // Recording is started only when the CRM app initiates a CRM lead call.
        // Do not auto-record personal/unknown outgoing calls here.
    }

  private void handleIncomingCall(Context context, Intent intent) {
    String state = intent.getStringExtra(TelephonyManager.EXTRA_STATE);
    String number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER);

    if (state == null || state.equals(lastState)) {
        return;
    }

    if (state.equals(TelephonyManager.EXTRA_STATE_RINGING)) {
        isIncoming = true;
        savedNumber = number;
        Log.d(TAG, "Incoming call from: " + savedNumber);
        CallStateHandler.notifyIncomingCall(context, savedNumber);

    } else if (state.equals(TelephonyManager.EXTRA_STATE_OFFHOOK)) {
        if (lastState.equals(TelephonyManager.EXTRA_STATE_RINGING)) {
            Log.d(TAG, "Answered incoming call from: " + savedNumber);
            CallStateHandler.notifyCallConnected(context, savedNumber);

            // Do not auto-record incoming calls here. Flutter will match the number
            // against CRM leads and only CRM numbers will be logged.
        } else {
            Log.d(TAG, "Outgoing call started");
            CallStateHandler.notifyCallConnected(context, savedNumber);
        }

    } else if (state.equals(TelephonyManager.EXTRA_STATE_IDLE)) {
        handleCallEnded(context);
    }

    lastState = state;
}


  // In CallReceiver.java
private void handleCallEnded(Context context) {
    // Stop recording first
    String recordingPath = CallStateHandler.stopRecording(context);
    String number = savedNumber;
    String leadId = CallStateHandler.getCurrentLeadId();

    if (number != null) {
        if (recordingPath != null && leadId != null) {
            // Notify recording completion with all required data
            CallStateHandler.notifyCallRecording(
                context, 
                number, 
                recordingPath,
                leadId
            );
        }

        if (TelephonyManager.EXTRA_STATE_RINGING.equals(lastState)) {
            Log.d(TAG, "Missed call from: " + number);
            CallStateHandler.notifyCallDisconnected(context, number, false);
        } else {
            Log.d(TAG, "Call ended");
            CallStateHandler.notifyCallDisconnected(context, number, true);
        }
    }

    savedNumber = null;
}
}
