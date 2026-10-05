package com.wachecker.wa_number_checker.auth

import android.app.Service
import android.content.Intent
import android.os.IBinder

class WaTempAuthenticatorService : Service() {
    private val authenticator by lazy { WaTempAuthenticator(this) }

    override fun onBind(intent: Intent?): IBinder? = authenticator.iBinder
}
