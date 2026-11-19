package com.follow.flashco.models

import com.follow.flashco.common.AccessControlMode
import com.google.gson.Gson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `SharedState` is written by Flutter into `FlutterSharedPreferences` and read back here, so the
 * JSON spelling of every field is a cross-language contract rather than an implementation detail.
 */
class SharedStateTest {
    private val gson = Gson()

    @Test
    fun `setup params preserve nested and future fields`() {
        val json = """{"setupParams":{"selected-map":{"GLOBAL":"auto"},"options":{"test-url":"https://example.test","skip-cert-verify":true},"future":{"value":3}}}"""
        val state = gson.fromJson(json, SharedState::class.java)
        val roundTrip = gson.fromJson(gson.toJson(state), SharedState::class.java)
        assertEquals(state.setupParams, roundTrip.setupParams)
        assertEquals(3, roundTrip.setupParams?.getAsJsonObject("future")?.get("value")?.asInt)
    }

    @Test
    fun `a full payload round-trips including nested vpn options`() {
        val json = """
            {
              "startTip": "Starting",
              "stopTip": "Stopping",
              "crashlytics": true,
              "currentProfileName": "Work",
              "stopText": "Halt",
              "onlyStatisticsProxy": true,
              "showStopAction": false,
              "vpnOptions": {
                "enable": true,
                "port": 7890,
                "ipv6": false,
                "dnsHijacking": true,
                "accessControlProps": {
                  "enable": true,
                  "mode": "rejectSelected",
                  "acceptList": ["a.b"],
                  "rejectList": ["c.d"]
                },
                "allowBypass": false,
                "systemProxy": true,
                "bypassDomain": ["example.test"],
                "stack": "gvisor",
                "routeAddress": ["0.0.0.0/0"]
              },
              "setupParams": {
                "test-url": "https://example.test/204",
                "selected-map": {"GLOBAL": "auto"}
              }
            }
        """.trimIndent()

        val state = gson.fromJson(json, SharedState::class.java)

        assertEquals("Starting", state.startTip)
        assertFalse(gson.toJson(state).contains("crashlytics"))
        assertEquals("Work", state.currentProfileName)
        assertEquals(true, state.onlyStatisticsProxy)
        assertEquals(false, state.showStopAction)
        assertEquals(7890, state.vpnOptions?.port)
        assertEquals("gvisor", state.vpnOptions?.stack)
        assertEquals(
            AccessControlMode.REJECT_SELECTED,
            state.vpnOptions?.accessControlProps?.mode,
        )
        assertEquals(listOf("0.0.0.0/0"), state.vpnOptions?.routeAddress)
        assertEquals("https://example.test/204", state.setupParams?.get("test-url")?.asString)
    }

    @Test
    fun `the constructed default keeps every fallback Flutter relies on`() {
        val defaults = SharedState()

        assertEquals("Flashco", defaults.currentProfileName)
        assertEquals("Stop", defaults.stopText)
        assertEquals(false, defaults.onlyStatisticsProxy)
        assertEquals(true, defaults.showStopAction)
        assertNull(defaults.vpnOptions)
        assertNull(defaults.setupParams)
    }

    @Test
    fun `an empty document still yields the declared defaults`() {
        // Every SharedState parameter has a default, so Kotlin emits a no-arg constructor
        // that Gson uses instead of its Unsafe fallback. Losing a default on any one
        // parameter would silently turn the absent fields below into nulls.
        val state = gson.fromJson("{}", SharedState::class.java)

        assertNotNull(state)
        assertEquals("Starting VPN...", state.startTip)
        assertEquals("Flashco", state.currentProfileName)
        assertNull(state.vpnOptions)
        assertNull(state.setupParams)
    }

    @Test
    fun `a partial document keeps defaults for the fields it omits`() {
        val state = gson.fromJson("""{"currentProfileName":"Work"}""", SharedState::class.java)

        assertEquals("Work", state.currentProfileName)
        assertEquals("Stop", state.stopText)
        assertEquals("Stopping VPN...", state.stopTip)
    }

    @Test
    fun `a null json document decodes to null so the caller can fall back`() {
        assertNull(gson.fromJson("null", SharedState::class.java))
        assertNull(gson.fromJson(null as String?, SharedState::class.java))
    }

    @Test
    fun `an access control payload without a matching mode decodes to null`() {
        val json = """
            {"vpnOptions":{"accessControlProps":{"mode":"unknownMode"}}}
        """.trimIndent()

        val state = gson.fromJson(json, SharedState::class.java)

        assertNull(state.vpnOptions?.accessControlProps?.mode)
    }
}
