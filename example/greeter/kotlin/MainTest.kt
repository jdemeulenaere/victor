package victor.backend

import org.junit.Assert.assertEquals
import org.junit.Test

class MainTest {
    @Test
    fun formatGreetingUsesProvidedName() {
        assertEquals("Hello, Ada! (from Kotlin backend)", formatGreeting("Ada"))
    }

    @Test
    fun formatGreetingFallsBackToWorldForBlankName() {
        assertEquals("Hello, world! (from Kotlin backend)", formatGreeting("   "))
    }
}
