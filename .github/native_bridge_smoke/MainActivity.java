package com.smlc666.nativebridgesmoke;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;

public final class MainActivity extends Activity {
    private static final String TAG = "NativeBridgeSmoke";

    static {
        Log.i(TAG, "before System.loadLibrary");
        System.loadLibrary("bridge_smoke");
        Log.i(TAG, "after System.loadLibrary");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.i(TAG, "MainActivity.onCreate");
    }
}
