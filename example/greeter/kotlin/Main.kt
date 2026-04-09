package victor.backend

import com.linecorp.armeria.common.grpc.GrpcSerializationFormats
import com.linecorp.armeria.server.Server
import com.linecorp.armeria.server.grpc.GrpcService
import io.grpc.stub.StreamObserver
import victor.api.v1.GreeterGrpc
import victor.api.v1.HelloRequest
import victor.api.v1.HelloResponse

private const val SERVICE_PATH = "/victor.api.v1.Greeter"

class GreeterService : GreeterGrpc.GreeterImplBase() {
    override fun sayHello(
        request: HelloRequest,
        responseObserver: StreamObserver<HelloResponse>,
    ) {
        val name = request.name.ifBlank { "world" }
        val response =
            HelloResponse.newBuilder()
                .setMessage("Hello, $name! (from Kotlin backend)")
                .build()

        responseObserver.onNext(response)
        responseObserver.onCompleted()
    }
}

fun main() {
    val port = System.getenv("VICTOR_BACKEND_PORT")?.toIntOrNull() ?: 8080

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
        Server.builder()
            .http(port)
            .service(grpcService)
            .build()

    Runtime.getRuntime().addShutdownHook(Thread { server.stop().join() })

    server.start().join()
    println("Backend running on http://localhost:$port")
    println("gRPC/gRPC-Web endpoint: POST $SERVICE_PATH/SayHello")

    server.whenClosed().join()
}
