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
import io.grpc.okhttp.OkHttpChannelBuilder
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.launch
import victor.api.v1.GreeterGrpcKt
import victor.api.v1.HelloRequest

private const val BACKEND_HOST = "127.0.0.1"
private const val BACKEND_PORT = 8080
private const val LOG_TAG = "GreeterAndroid"

const val MAIN_ACTIVITY_GREETING_TEXT = "Hello from Bazel + Kotlin + Compose!"

class MainActivity : ComponentActivity() {
    private val channel: ManagedChannel by lazy {
        OkHttpChannelBuilder.forAddress(BACKEND_HOST, BACKEND_PORT).usePlaintext().build()
    }

    private val greeterClient: GreeterGrpcKt.GreeterCoroutineStub by lazy {
        GreeterGrpcKt.GreeterCoroutineStub(channel)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { MainActivityContent(client = greeterClient) }
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
fun MainActivityContent(client: GreeterGrpcKt.GreeterCoroutineStub) {
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
                Text(text = MAIN_ACTIVITY_GREETING_TEXT)
                Text(
                    text = "gRPC Kotlin + Android Demo",
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    text = "Target: $BACKEND_HOST:$BACKEND_PORT",
                    style = MaterialTheme.typography.bodySmall,
                )
                Text(
                    text = "Use adb reverse: adb reverse tcp:$BACKEND_PORT tcp:$BACKEND_PORT",
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
