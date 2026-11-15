package com.ryanheise.just_audio;

import android.content.Context;
import android.net.DhcpInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InterfaceAddress;
import java.net.NetworkInterface;
import java.util.Enumeration;

public class SyncPlatformBridge implements MethodCallHandler {
    private static final String CHANNEL_NAME = "com.tamilgaming.paatupadava/sync";
    private static SyncPlatformBridge instance;
    private MethodChannel channel;
    private final Context context;

    private WifiManager.MulticastLock multicastLock;
    private WifiManager.WifiLock wifiLock;

    private SyncPlatformBridge(Context context, BinaryMessenger messenger) {
        this.context = context.getApplicationContext();
        this.channel = new MethodChannel(messenger, CHANNEL_NAME);
        this.channel.setMethodCallHandler(this);
    }

    public static synchronized void register(Context context, BinaryMessenger messenger) {
        if (instance == null) {
            instance = new SyncPlatformBridge(context, messenger);
        } else {
            instance.updateMessenger(messenger);
        }
    }

    public static synchronized void unregister() {
        if (instance != null && instance.channel != null) {
            instance.channel.setMethodCallHandler(null);
            instance.channel = null;
        }
    }

    private void updateMessenger(BinaryMessenger messenger) {
        if (this.channel != null) {
            this.channel.setMethodCallHandler(null);
        }
        this.channel = new MethodChannel(messenger, CHANNEL_NAME);
        this.channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "acquireWifiLocks": {
                try {
                    WifiManager wifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
                    if (wifiManager != null) {
                        if (multicastLock == null) {
                            multicastLock = wifiManager.createMulticastLock("paatupadava_multicast");
                            multicastLock.setReferenceCounted(true);
                            multicastLock.acquire();
                        }
                        if (wifiLock == null) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_LOW_LATENCY, "paatupadava_wifi");
                            } else {
                                @SuppressWarnings("deprecation")
                                WifiManager.WifiLock legacyLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "paatupadava_wifi");
                                wifiLock = legacyLock;
                            }
                            wifiLock.setReferenceCounted(true);
                            wifiLock.acquire();
                        }
                    }
                    result.success(true);
                } catch (Exception e) {
                    result.error("WIFI_LOCK_ERROR", e.getMessage(), null);
                }
                break;
            }
            case "releaseWifiLocks": {
                try {
                    if (multicastLock != null && multicastLock.isHeld()) {
                        multicastLock.release();
                    }
                    multicastLock = null;
                    if (wifiLock != null && wifiLock.isHeld()) {
                        wifiLock.release();
                    }
                    wifiLock = null;
                    result.success(true);
                } catch (Exception e) {
                    result.error("WIFI_LOCK_ERROR", e.getMessage(), null);
                }
                break;
            }
            case "getWifiBroadcastAddress": {
                try {
                    String broadcastAddress = null;
                    Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
                    while (interfaces != null && interfaces.hasMoreElements()) {
                        NetworkInterface iface = interfaces.nextElement();
                        if (iface.isLoopback() || !iface.isUp()) continue;
                        for (InterfaceAddress addr : iface.getInterfaceAddresses()) {
                            InetAddress bcast = addr.getBroadcast();
                            if (bcast != null && bcast instanceof Inet4Address && !bcast.isLoopbackAddress()) {
                                broadcastAddress = bcast.getHostAddress();
                                break;
                            }
                        }
                        if (broadcastAddress != null) break;
                    }

                    if (broadcastAddress == null) {
                        @SuppressWarnings("deprecation")
                        WifiManager wifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
                        if (wifiManager != null) {
                            @SuppressWarnings("deprecation")
                            DhcpInfo dhcp = wifiManager.getDhcpInfo();
                            if (dhcp != null && dhcp.ipAddress != 0) {
                                int broadcast = (dhcp.ipAddress & dhcp.netmask) | ~dhcp.netmask;
                                byte[] bytes = new byte[4];
                                for (int i = 0; i < 4; i++) {
                                    bytes[i] = (byte) ((broadcast >> (i * 8)) & 0xFF);
                                }
                                broadcastAddress = InetAddress.getByAddress(bytes).getHostAddress();
                            }
                        }
                    }

                    result.success(broadcastAddress);
                } catch (Exception e) {
                    result.success(null);
                }
                break;
            }
            default:
                result.notImplemented();
                break;
        }
    }
}
