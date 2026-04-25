package victor.greeter.android

import io.grpc.ManagedChannel
import io.grpc.okhttp.OkHttpChannelBuilder

fun buildChannel(endpoint: BackendEndpoint): ManagedChannel {
    return OkHttpChannelBuilder.forAddress(endpoint.host, endpoint.port)
        .apply {
            if (endpoint.usePlaintext) {
                usePlaintext()
            }
        }
        .build()
}
