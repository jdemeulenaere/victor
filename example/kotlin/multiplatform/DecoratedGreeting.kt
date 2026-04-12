package victor.example.multiplatform

expect object GreetingDecorator {
    val suffix: String
}

class DecoratedGreeting {
    fun message(name: String): String = Greeting().message(name) + GreetingDecorator.suffix
}
