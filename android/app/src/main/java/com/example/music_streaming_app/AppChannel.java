package com.example.music_streaming_app;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * The few host answers the Dart side cannot get for itself: the installed
 * version, the ABIs, "may this app install APKs", the install hand-off, and
 * moving the task to the background instead of finishing it.
 *
 * Every method is defensive; nothing here is allowed to throw into Dart.
 */
final class AppChannel implements MethodChannel.MethodCallHandler {
    static final String NAME = "mine_music/app";

    /** The only folder an APK may be installed from (matches update_file_paths.xml). */
    private static final String UPDATES_DIR = "updates";

    private final Activity activity;

    private AppChannel(Activity activity) {
        this.activity = activity;
    }

    static void register(Activity activity, BinaryMessenger messenger) {
        new MethodChannel(messenger, NAME).setMethodCallHandler(new AppChannel(activity));
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "moveToBack":
                    result.success(activity.moveTaskToBack(true));
                    break;
                case "appInfo":
                    result.success(appInfo());
                    break;
                case "canInstall":
                    result.success(canInstall());
                    break;
                case "openInstallSettings":
                    openInstallSettings();
                    result.success(null);
                    break;
                case "install":
                    result.success(install(call.<String>argument("path")));
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Throwable t) {
            result.error("APP", String.valueOf(t), null);
        }
    }

    private Map<String, Object> appInfo() throws PackageManager.NameNotFoundException {
        PackageManager pm = activity.getPackageManager();
        PackageInfo info = pm.getPackageInfo(activity.getPackageName(), 0);
        Map<String, Object> m = new HashMap<>();
        m.put("versionName", info.versionName == null ? "0.0.0" : info.versionName);
        long code = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? info.getLongVersionCode()
                : info.versionCode;
        m.put("versionCode", code);
        m.put("packageName", activity.getPackageName());
        m.put("sdkInt", Build.VERSION.SDK_INT);
        m.put("lastUpdateTime", info.lastUpdateTime);
        List<String> abis = new ArrayList<>();
        for (String abi : Build.SUPPORTED_ABIS) {
            abis.add(abi);
        }
        m.put("abis", abis);
        return m;
    }

    private boolean canInstall() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                || activity.getPackageManager().canRequestPackageInstalls();
    }

    private void openInstallSettings() {
        Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + activity.getPackageName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity.startActivity(intent);
    }

    /** "started" | "needs_permission" | "unavailable". */
    private String install(String path) throws IOException {
        if (path == null) return "unavailable";
        File file = new File(path).getCanonicalFile();
        File allowed = new File(activity.getCacheDir(), UPDATES_DIR).getCanonicalFile();
        // Never hand the installer anything outside the update folder.
        if (!file.getPath().startsWith(allowed.getPath() + File.separator) || !file.isFile()) {
            return "unavailable";
        }
        if (!canInstall()) {
            openInstallSettings();
            return "needs_permission";
        }
        Uri uri = FileProvider.getUriForFile(
                activity, activity.getPackageName() + ".updates", file);
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        activity.startActivity(intent);
        return "started";
    }
}
