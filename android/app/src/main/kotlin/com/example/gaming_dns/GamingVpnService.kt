package com.example.gaming_dns

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * DNS-only VPN profile.
 *
 * Android sends resolver traffic through the VPN DNS server declared by
 * Builder.addDnsServer(). This service deliberately does not implement a
 * packet-forwarding engine; it is therefore a DNS configuration VPN, not a
 * general traffic tunnel.
 */
class GamingVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.example.gaming_dns.START_VPN"
        const val ACTION_STOP = "com.example.gaming_dns.STOP_VPN"
        const val EXTRA_DNS_IP = "dns_ip"
        private const val TAG = "GamingVpnService"
    }

    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopVpn()
            ACTION_START -> {
                val dnsIp = intent.getStringExtra(EXTRA_DNS_IP)?.trim()
                if (!dnsIp.isNullOrBlank()) startVpn(dnsIp) else stopVpn()
            }
        }
        return START_NOT_STICKY
    }

    private fun startVpn(dnsIp: String) {
        stopInterfaceOnly()

        try {
            val builder = Builder()
                .setSession("Gaming DNS")
                .setMtu(1500)
                .addAddress("10.10.0.2", 32)
                .addDnsServer(dnsIp)
                .addRoute(dnsIp, 32)

            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                Log.e(TAG, "VpnService.Builder.establish() returned null")
                stopSelf()
                return
            }

            Log.i(TAG, "VPN started with DNS $dnsIp")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN", e)
            stopInterfaceOnly()
            stopSelf()
        }
    }

    private fun stopInterfaceOnly() {
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to close VPN interface", e)
        } finally {
            vpnInterface = null
        }
    }

    private fun stopVpn() {
        stopInterfaceOnly()
        stopSelf()
        Log.i(TAG, "VPN stopped")
    }

    override fun onDestroy() {
        stopInterfaceOnly()
        super.onDestroy()
    }
}
