package victor.greeter.desktop

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.Button
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import io.grpc.ManagedChannel
import io.grpc.StatusRuntimeException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.launch
import victor.api.v1.GreeterGrpcKt
import victor.api.v1.HelloRequest
import victor.backend.client.BackendEndpoint
import victor.backend.client.buildChannel
import victor.example.multiplatform.rememberGreetingMessage
import victor.greeter.shared.BackendConfig

private const val APP_TITLE = "Victor Greeter Desktop"
private const val DEFAULT_NAME = "world"

interface GreeterClient {
    suspend fun sayHello(name: String): String
}

fun main() = application {
    val client = remember { DesktopGreeterClient(BackendConfig.endpoint) }

    Window(
        onCloseRequest = {
            client.close()
            exitApplication()
        },
        title = APP_TITLE,
    ) {
        DesktopGreeterApp(client = client)
    }
}

@Composable
fun DesktopGreeterApp(client: GreeterClient) {
    var name by remember { mutableStateOf(DEFAULT_NAME) }
    var loading by remember { mutableStateOf(false) }
    var responseMessage by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    MaterialTheme {
        Column(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(text = rememberGreetingMessage("Compose Desktop"))
            Text(text = "Target: ${BackendConfig.endpoint.serviceUrl}")

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(text = "Name") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            Button(
                enabled = !loading,
                onClick = {
                    loading = true
                    responseMessage = ""
                    errorMessage = ""
                    scope.launch {
                        try {
                            responseMessage = client.sayHello(name)
                        } catch (error: StatusRuntimeException) {
                            errorMessage = error.status.description ?: error.status.code.name
                        } catch (error: Exception) {
                            errorMessage = error.message ?: "Unknown error"
                        } finally {
                            loading = false
                        }
                    }
                },
            ) {
                Text(text = if (loading) "Calling..." else "Call SayHello")
            }

            if (responseMessage.isNotBlank()) {
                Text(text = responseMessage)
            }

            if (errorMessage.isNotBlank()) {
                Text(text = errorMessage, color = MaterialTheme.colors.error)
            }
        }
    }
}

private class DesktopGreeterClient(endpoint: BackendEndpoint) : GreeterClient {
    private val channel: ManagedChannel = buildChannel(endpoint)

    private val client: GreeterGrpcKt.GreeterCoroutineStub =
        GreeterGrpcKt.GreeterCoroutineStub(channel)

    override suspend fun sayHello(name: String): String {
        val request = HelloRequest.newBuilder().setName(name.ifBlank { DEFAULT_NAME }).build()
        return client.sayHello(request).message
    }

    fun close() {
        channel.shutdown()
        if (!channel.awaitTermination(1, TimeUnit.SECONDS)) {
            channel.shutdownNow()
        }
    }
}
