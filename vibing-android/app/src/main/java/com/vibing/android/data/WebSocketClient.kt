package com.vibing.android.data

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.serialization.json.*
import okhttp3.*

class VibingWebSocket(private val url: String) {

    private var ws: WebSocket? = null
    private val client = OkHttpClient()

    private val _textMessages = MutableSharedFlow<String>(extraBufferCapacity = 64)
    val textMessages: SharedFlow<String> = _textMessages

    private val _connected = MutableSharedFlow<Boolean>(extraBufferCapacity = 8)
    val connected: SharedFlow<Boolean> = _connected

    fun connect() {
        val request = Request.Builder().url(url).build()
        ws = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                _connected.tryEmit(true)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                _textMessages.tryEmit(text)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _connected.tryEmit(false)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _connected.tryEmit(false)
            }
        })
    }

    fun sendJson(map: Map<String, Any>) {
        val jsonObj = buildJsonObject {
            map.forEach { (k, v) ->
                when (v) {
                    is String -> put(k, v)
                    is List<*> -> putJsonArray(k) { v.forEach { add(it.toString()) } }
                }
            }
        }
        ws?.send(jsonObj.toString())
    }

    fun sendInput(sessionId: String, text: String) {
        sendJson(mapOf("type" to "input", "session_id" to sessionId, "data" to text))
    }

    fun requestSessionList() {
        sendJson(mapOf("type" to "list_sessions"))
    }

    fun subscribe(sessionIds: List<String>) {
        sendJson(mapOf("type" to "subscribe", "session_ids" to sessionIds))
    }

    fun disconnect() {
        ws?.close(1000, "bye")
        ws = null
    }
}
