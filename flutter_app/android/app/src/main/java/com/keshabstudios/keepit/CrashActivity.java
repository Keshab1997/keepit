package com.keshabstudios.keepit;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Readable crash report screen, shown by CrashApp after an uncaught crash.
 * Runs in the separate ":crash" process so it outlives the crashing one.
 * No AndroidX, no resources, no Flutter — pure android.widget.
 */
public class CrashActivity extends Activity {
    public static final String EXTRA_STACK = "stack";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String stack = null;
        if (getIntent() != null) {
            stack = getIntent().getStringExtra(EXTRA_STACK);
        }
        if (stack == null || stack.length() == 0) {
            stack = "(no crash details were captured)";
        }
        final String report = "KeepIt crashed.\n\n" + stack;

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(36, 56, 36, 36);

        TextView title = new TextView(this);
        title.setText("KeepIt crashed");
        title.setTextSize(20);
        title.setTypeface(Typeface.DEFAULT_BOLD);

        TextView hint = new TextView(this);
        hint.setText("Copy or share this text to the developer:");
        hint.setPadding(0, 8, 0, 16);

        TextView body = new TextView(this);
        body.setText(report);
        body.setTextSize(11);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(body, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setPadding(0, 16, 0, 0);

        Button copy = new Button(this);
        copy.setText("Copy");
        copy.setOnClickListener(v -> {
            ClipboardManager cm =
                    (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            if (cm != null) {
                cm.setPrimaryClip(ClipData.newPlainText("KeepIt crash", report));
                Toast.makeText(CrashActivity.this, "Copied", Toast.LENGTH_SHORT)
                        .show();
            }
        });

        Button share = new Button(this);
        share.setText("Share");
        share.setOnClickListener(v -> {
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_TEXT, report);
            startActivity(Intent.createChooser(send, "Share crash report"));
        });

        Button close = new Button(this);
        close.setText("Close");
        close.setOnClickListener(v -> finish());

        LinearLayout.LayoutParams buttonLp = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        buttons.addView(copy, buttonLp);
        buttons.addView(share, buttonLp);
        buttons.addView(close, buttonLp);

        LinearLayout.LayoutParams wrapLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        LinearLayout.LayoutParams scrollLp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);

        root.addView(title, wrapLp);
        root.addView(hint, wrapLp);
        root.addView(scroll, scrollLp);
        root.addView(buttons, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        setContentView(root);
    }
}
