package victor.backend.client

import org.junit.Assert.assertEquals
import org.junit.Test

class BackendChannelTest {
    @Test
    fun buildChannelUsesEndpointAddress() {
        val endpoint =
            BackendEndpoint(
                serviceUrl = "http://127.0.0.1:50051",
                host = "127.0.0.1",
                port = 50051,
                usePlaintext = true,
            )

        val channel = buildChannel(endpoint)
        try {
            assertEquals("127.0.0.1:50051", channel.authority())
        } finally {
            channel.shutdownNow()
        }
    }
}
