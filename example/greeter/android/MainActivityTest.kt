package victor.greeter.android

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class MainActivityTest {
    @Test
    fun mainActivityStarts() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()

        assertNotNull(activity)
        assertEquals("victor.greeter.android", activity.packageName)
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun mainActivityContentDisplaysGreeting() {
        runAndroidComposeUiTest<MainActivity> {
            onNodeWithText(MAIN_ACTIVITY_GREETING_TEXT).assertIsDisplayed()
        }
    }
}
