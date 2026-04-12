package victor.example.multiplatform

expect object Platform {
    val name: String
}

class Greeting {
    fun message(name: String): String {
        val normalizedName = name.ifBlank { "world" }
        return "Hello, $normalizedName from ${Platform.name}!"
    }
}
