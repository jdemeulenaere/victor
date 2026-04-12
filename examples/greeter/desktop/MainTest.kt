package victor.greeter.desktop

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import org.junit.Test

class MainTest {
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun callSayHelloShowsResponse() = runComposeUiTest {
        val expectedResponse = "Hello, world! (from desktop test)"

        setContent {
            DesktopGreeterApp(
                client =
                    object : GreeterClient {
                        override suspend fun sayHello(name: String): String =
                            "Hello, ${name.ifBlank { "world" }}! (from desktop test)"
                    }
            )
        }

        onNodeWithText("Call SayHello").performClick()
        waitUntil(timeoutMillis = 5_000) {
            onAllNodesWithText(expectedResponse).fetchSemanticsNodes().isNotEmpty()
        }
        onNodeWithText(expectedResponse).assertIsDisplayed()
    }
}
