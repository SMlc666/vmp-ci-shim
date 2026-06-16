package com.smlc666.nativebridgesmoke;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;

public final class MainActivity extends Activity {
    private static final String TAG = "NativeBridgeSmoke";

    private static native String runCppBusinessBattery(String tempDirBase);

    static {
        Log.i(TAG, "before System.loadLibrary");
        System.loadLibrary("cpp_business_jni");
        Log.i(TAG, "after System.loadLibrary");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.i(TAG, "MainActivity.onCreate");
        String result = runCppBusinessBattery(getFilesDir().getAbsolutePath());
        Log.i(TAG, "cpp_business battery begin");
        for (String line : result.split("\\n")) {
            if (!line.isEmpty()) {
                Log.i(TAG, line);
            }
        }
        Log.i(TAG, "cpp_business battery end");
    }
}
