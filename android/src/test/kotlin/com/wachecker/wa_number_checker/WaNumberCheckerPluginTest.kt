package com.wachecker.wa_number_checker

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals

/** Unit tests for the pure-logic surface (no Android framework needed). */
internal class WaNumberCheckerPluginTest {
    @Test
    fun companion_tempAccount_constants() {
        assertEquals("com.wa_checker.temp", WaNumberCheckerPlugin.TEMP_ACCOUNT_TYPE)
        assertEquals("wa_temp", WaNumberCheckerPlugin.TEMP_ACCOUNT_NAME)
        assertEquals(
            setOf("com.whatsapp", "com.whatsapp.w4b"),
            WaNumberCheckerPlugin.WA_ACCOUNT_TYPES,
        )
    }

    @Test
    fun onMethodCall_unknown_returnsNotImplemented() {
        val plugin = WaNumberCheckerPlugin()
        val call = MethodCall("noSuchMethod", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)
        Mockito.verify(mockResult).notImplemented()
    }
}
