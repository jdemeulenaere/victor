package victor.backend

import com.linecorp.armeria.common.grpc.GrpcSerializationFormats
import com.linecorp.armeria.server.Server
import com.linecorp.armeria.server.grpc.GrpcService
import victor.api.v1.GreeterGrpcKt
import victor.api.v1.HelloRequest
import victor.api.v1.HelloResponse

private const val SERVICE_PATH = "/victor.api.v1.Greeter"

fun formatGreeting(name: String): String {
    val safeName = name.ifBlank { "world" }
    return "Hello, $safeName! (from Kotlin backend)"
}

class GreeterService : GreeterGrpcKt.GreeterCoroutineImplBase() {
    override suspend fun sayHello(request: HelloRequest): HelloResponse {
        return HelloResponse.newBuilder().setMessage(formatGreeting(request.name)).build()
    }
}

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 8080

    val grpcService =
        GrpcService.builder()
            .addService(GreeterService())
            .supportedSerializationFormats(
                GrpcSerializationFormats.PROTO,
                GrpcSerializationFormats.PROTO_WEB,
                GrpcSerializationFormats.PROTO_WEB_TEXT,
            )
            .build()

    val server =
        Server.builder().http(port).service(grpcService).serviceUnder("/grpc", grpcService).build()

    Runtime.getRuntime().addShutdownHook(Thread { server.stop().join() })

    server.start().join()
    println("Backend running on http://localhost:$port")
    println("gRPC/gRPC-Web endpoint: POST $SERVICE_PATH/SayHello")

    server.whenClosed().join()
}
