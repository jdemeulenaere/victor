package victor.greeter.android

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
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

private const val LOG_TAG = "GreeterAndroid"

class MainActivity : ComponentActivity() {
    private val channel: ManagedChannel by lazy { buildChannel(BackendConfig.endpoint) }

    private val greeterClient: GreeterGrpcKt.GreeterCoroutineStub by lazy {
        GreeterGrpcKt.GreeterCoroutineStub(channel)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MainActivityContent(client = greeterClient, endpoint = BackendConfig.endpoint)
        }
    }

    override fun onDestroy() {
        channel.shutdown()
        if (!channel.awaitTermination(1, TimeUnit.SECONDS)) {
            channel.shutdownNow()
        }
        super.onDestroy()
    }
}

@Composable
fun MainActivityContent(client: GreeterGrpcKt.GreeterCoroutineStub, endpoint: BackendEndpoint) {
    var name by remember { mutableStateOf("world") }
    var loading by remember { mutableStateOf(false) }
    var responseMessage by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    MaterialTheme {
        Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
            Column(
                modifier =
                    Modifier.fillMaxSize()
                        .padding(24.dp)
                        .padding(innerPadding)
                        .consumeWindowInsets(innerPadding),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(text = rememberGreetingMessage("Compose"))
                Text(
                    text = "gRPC Kotlin + Android Demo",
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    text = "Target: ${endpoint.serviceUrl}",
                    style = MaterialTheme.typography.bodySmall,
                )

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
                                val response =
                                    client.sayHello(HelloRequest.newBuilder().setName(name).build())
                                responseMessage = response.message
                            } catch (error: LinkageError) {
                                Log.e(LOG_TAG, "Linkage error while calling SayHello", error)
                                errorMessage = error.message ?: "Runtime linkage error"
                            } catch (error: StatusRuntimeException) {
                                Log.e(LOG_TAG, "gRPC status error while calling SayHello", error)
                                errorMessage = error.status.description ?: error.status.code.name
                            } catch (error: Exception) {
                                Log.e(LOG_TAG, "Unexpected error while calling SayHello", error)
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
                    Text(text = errorMessage, color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}
