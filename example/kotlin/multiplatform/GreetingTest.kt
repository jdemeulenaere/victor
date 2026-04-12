package victor.example.multiplatform

import org.junit.Assert.assertEquals
import org.junit.Test

class GreetingTest {
    @Test
    fun messageUsesJvmPlatformActual() {
        assertEquals("Hello, world from JVM!", Greeting().message(""))
    }
}
