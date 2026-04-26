@file:OptIn(ExperimentalJsExport::class)

package victor.example.multiplatform

import kotlin.js.ExperimentalJsExport
import kotlin.js.JsExport
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

expect object Platform {
    val name: String
}

@Serializable private data class GreetingConfig(val salutation: String)

private val greetingConfig = Json.decodeFromString<GreetingConfig>("""{"salutation":"Hello"}""")

class Greeting {
    fun message(name: String): String {
        val normalizedName = name.ifBlank { "world" }
        val salutation = greetingConfig.salutation
        return "$salutation, $normalizedName from ${Platform.name}!"
    }
}

@JsExport
fun greetingMessage(name: String): String {
    return Greeting().message(name)
}
