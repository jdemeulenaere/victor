package victor.example.multiplatform

import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.window.ComposeUIViewController
import platform.UIKit.UIViewController

class SharedGreetingComposeController {
    private var name by mutableStateOf("world")

    fun makeViewController(name: String): UIViewController {
        setName(name)
        return ComposeUIViewController {
            BasicText(text = rememberGreetingMessage(this@SharedGreetingComposeController.name))
        }
    }

    fun setName(name: String) {
        this.name = name
    }
}
