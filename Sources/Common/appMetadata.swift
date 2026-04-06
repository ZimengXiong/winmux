public let stableWinMuxAppId: String = "com.zxzimeng.winmux"
#if DEBUG
    public let winMuxAppId: String = "com.zxzimeng.winmux.debug"
    public let winMuxAppName: String = "WinMux-Debug"
#else
    public let winMuxAppId: String = stableWinMuxAppId
    public let winMuxAppName: String = "WinMux"
#endif
