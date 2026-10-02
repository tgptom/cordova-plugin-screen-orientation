/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
 */

package cordova.plugins.screenorientation;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.util.Log;

public class CDVOrientation extends CordovaPlugin {
    
    private static final String TAG = "YoikScreenOrientation"; 
    
    /**
     * Screen Orientation Constants
     */
    
    private static final String ANY = "any";
    private static final String PORTRAIT_PRIMARY = "portrait-primary";
    private static final String PORTRAIT_SECONDARY = "portrait-secondary";
    private static final String LANDSCAPE_PRIMARY = "landscape-primary";
    private static final String LANDSCAPE_SECONDARY = "landscape-secondary";
    private static final String PORTRAIT = "portrait";
    private static final String LANDSCAPE = "landscape";

    private static final String NOT_SUPPORTED_ERROR = "NotSupportedError";
    private static final String INVALID_STATE_ERROR = "InvalidStateError";
    private static final String GENERIC_ERROR = "Error";

    private static final int UNKNOWN_ORIENTATION = Integer.MIN_VALUE;
    
    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) {
        
        Log.d(TAG, "execute action: " + action);
        
        // Route the Action
        if (action.equals("screenOrientation")) {
            routeScreenOrientation(args, callbackContext);
            return true;
        }
        
        // Action not found: returning false makes Cordova report INVALID_ACTION exactly once
        return false;
    }
    
    private void routeScreenOrientation(JSONArray args, final CallbackContext callbackContext) {
        
        final String orientation = args.optString(0, "");
        
        Log.d(TAG, "Requested ScreenOrientation: " + orientation);
        
        final int requestedOrientation = toActivityOrientation(orientation);
        if (requestedOrientation == UNKNOWN_ORIENTATION) {
            sendError(callbackContext, NOT_SUPPORTED_ERROR, "Unsupported orientation value: " + orientation);
            return;
        }

        final Activity activity = cordova.getActivity();
        if (activity == null) {
            sendError(callbackContext, INVALID_STATE_ERROR, "No Activity is available to change the orientation");
            return;
        }

        activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                try {
                    activity.setRequestedOrientation(requestedOrientation);
                } catch (RuntimeException e) {
                    Log.e(TAG, "Unable to set requested orientation", e);
                    sendError(callbackContext, GENERIC_ERROR, "Unable to set orientation: " + e.getMessage());
                    return;
                }
                callbackContext.success();
            }
        });
    }

    private static int toActivityOrientation(String orientation) {
        switch (orientation) {
            case ANY:
                return ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
            case LANDSCAPE_PRIMARY:
                return ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE;
            case PORTRAIT_PRIMARY:
                return ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;
            case LANDSCAPE:
                return ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;
            case PORTRAIT:
                return ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT;
            case LANDSCAPE_SECONDARY:
                return ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE;
            case PORTRAIT_SECONDARY:
                return ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT;
            default:
                return UNKNOWN_ORIENTATION;
        }
    }

    private static void sendError(CallbackContext callbackContext, String name, String message) {
        JSONObject error = new JSONObject();
        try {
            error.put("name", name);
            error.put("message", message);
        } catch (JSONException e) {
            callbackContext.error(message);
            return;
        }
        callbackContext.error(error);
    }
}
