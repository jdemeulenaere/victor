package victor.example.multiplatform

import kotlinx.coroutines.CoroutineName

expect object GreetingDecorator {
    val suffix: String
}

class DecoratedGreeting {
    fun message(name: String): String =
        Greeting().message(name) + " [${CoroutineName("kmp-3p").name}]" + GreetingDecorator.suffix
}
