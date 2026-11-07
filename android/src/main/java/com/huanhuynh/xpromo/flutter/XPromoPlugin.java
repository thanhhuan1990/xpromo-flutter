package com.huanhuynh.xpromo.flutter;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;


import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Phần native của XPromo: kiểm tra app đã cài, mở Google Play, lưu trạng thái (SharedPreferences "xpromo").
 * Viết bằng Java để plugin không kéo theo Kotlin Gradle Plugin.
 */
public class XPromoPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "com.huanhuynh.xpromo";
    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        context = null;
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "packageName":
                result.success(context.getPackageName());
                break;
            case "installed":
                result.success(installed(call.<List<String>>argument("ids")));
                break;
            case "open":
                result.success(open(call.<String>argument("market"), call.<String>argument("web")));
                break;
            case "prefs":
                result.success(new HashMap<String, Object>(prefs().getAll()));
                break;
            case "prefsPut":
                prefsPut(call.<String>argument("key"), call.argument("value"));
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private SharedPreferences prefs() {
        return context.getSharedPreferences("xpromo", Context.MODE_PRIVATE);
    }

    private void prefsPut(String key, Object value) {
        if (key == null) return;
        SharedPreferences.Editor editor = prefs().edit();
        if (value == null) {
            editor.remove(key);
        } else if (value instanceof Number) {
            editor.putLong(key, ((Number) value).longValue());
        } else if (value instanceof Boolean) {
            editor.putBoolean(key, (Boolean) value);
        } else {
            editor.putString(key, value.toString());
        }
        editor.apply();
    }

    private List<String> installed(List<String> ids) {
        List<String> out = new ArrayList<>();
        if (ids == null) return out;
        PackageManager pm = context.getPackageManager();
        for (String id : ids) {
            try {
                pm.getPackageInfo(id, 0);
                out.add(id);
            } catch (PackageManager.NameNotFoundException ignored) {
                // chưa cài
            }
        }
        return out;
    }

    private boolean open(String market, String web) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(market))
                    .setPackage("com.android.vending")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            return true;
        } catch (ActivityNotFoundException e) {
            try {
                context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(web)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                return true;
            } catch (Exception ignored) {
                return false;
            }
        }
    }
}
