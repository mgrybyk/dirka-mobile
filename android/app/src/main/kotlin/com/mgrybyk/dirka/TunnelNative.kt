package com.mgrybyk.dirka

internal object TunnelNative {
    init {
        System.loadLibrary("dirka_android")
    }

    external fun start(config: ByteArray): Long
    external fun pollSnapshot(handle: Long): ByteArray?
    external fun stop(handle: Long)
    external fun destroy(handle: Long)
    external fun networkAvailable(handle: Long)
}
