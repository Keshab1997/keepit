package com.keshabstudios.keepit;

import android.app.Application;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.PrintWriter;
import java.io.StringWriter;

/**
 * Catches uncaught Java/native crashes that no Dart try/catch can ever see
 * (plugin init errors, class-loading errors, crashy ContentProviders) and
 * hands the stack trace to CrashActivity, which runs in its own process so it
 * survives while this one dies.
 *
 * Deliberately depends on nothing but android.app — the moment it runs is the
 * moment everything else may already be broken.
 */
public class CrashApp extends Application {
    private static final String TAG = "KeepItCrash";

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        final Thread.UncaughtExceptionHandler previous =
                Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            try {
                Log.e(TAG, "Uncaught exception", throwable);
                StringWriter sw = new StringWriter();
                throwable.printStackTrace(new PrintWriter(sw));
                Intent intent = new Intent(base, CrashActivity.class);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_CLEAR_TASK);
                intent.putExtra(CrashActivity.EXTRA_STACK, sw.toString());
                base.startActivity(intent);
            } catch (Throwable ignored) {
                // The crash reporter must never crash.
            }
            if (previous != null) {
                previous.uncaughtException(thread, throwable);
            } else {
                System.exit(1);
            }
        });
    }
}
