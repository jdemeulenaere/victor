package victor.example.multiplatform

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember

@Composable
fun rememberGreetingMessage(name: String): String {
    return remember(name) { Greeting().message(name) }
}
