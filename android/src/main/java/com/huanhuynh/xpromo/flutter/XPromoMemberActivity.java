package com.huanhuynh.xpromo.flutter;

import android.app.Activity;
import android.os.Bundle;

/**
 * Activity rỗng, không giao diện, tự đóng ngay. Chỉ để khai báo intent-filter "com.huanhuynh.xpromo.MEMBER":
 * mọi app dùng XPromo có activity này và khai báo <queries> theo action đó → trên Android 11+ các app của
 * nhà phát triển luôn thấy nhau (biết app nào đã cài để hiện nút "Mở"), kể cả app phát hành sau này.
 */
public class XPromoMemberActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        finish();
    }
}
