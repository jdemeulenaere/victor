package victor.backend.client

data class BackendEndpoint(
    val serviceUrl: String,
    val host: String,
    val port: Int,
    val usePlaintext: Boolean,
)
