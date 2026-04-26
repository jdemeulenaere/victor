import GRPC
import NIOCore
import NIOPosix
import SwiftUI
import VictorApiIosSwiftClientProto

private let backendHost = "127.0.0.1"
private let backendPort = 8080
private let defaultName = "world"

protocol GreeterServing: AnyObject {
    func sayHello(name: String, completion: @escaping (Result<String, Error>) -> Void)
}

final class GrpcGreeterClient: GreeterServing {
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let channel: GRPCChannel
    private let client: Victor_Api_V1_GreeterNIOClient

    init(host: String = backendHost, port: Int = backendPort) throws {
        channel =
            try GRPCChannelPool.with(
                target: .host(host, port: port),
                transportSecurity: .plaintext,
                eventLoopGroup: eventLoopGroup
            )
        client = Victor_Api_V1_GreeterNIOClient(channel: channel)
    }

    func sayHello(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        let request = Victor_Api_V1_HelloRequest.with {
            $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if $0.name.isEmpty {
                $0.name = defaultName
            }
        }

        client.sayHello(request).response.whenComplete { result in
            completion(result.map { $0.message })
        }
    }

    deinit {
        channel.close().whenComplete { [eventLoopGroup] _ in
            eventLoopGroup.shutdownGracefully { error in
                if let error {
                    print("Failed to shut down gRPC event loop group: \(error)")
                }
            }
        }
    }
}

final class FailingGreeterClient: GreeterServing {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func sayHello(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.failure(error))
    }
}

@MainActor
final class GreeterViewModel: ObservableObject {
    @Published var name = defaultName
    @Published var loading = false
    @Published var responseMessage = ""
    @Published var errorMessage = ""

    private let client: GreeterServing

    init(client: GreeterServing) {
        self.client = client
    }

    func callSayHello() {
        loading = true
        responseMessage = ""
        errorMessage = ""

        client.sayHello(name: name) { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }
                switch result {
                case let .success(message):
                    self.responseMessage = message
                case let .failure(error):
                    self.errorMessage = error.localizedDescription
                }
                self.loading = false
            }
        }
    }
}

struct GreeterView: View {
    @StateObject private var model: GreeterViewModel

    init(client: GreeterServing) {
        _model = StateObject(wrappedValue: GreeterViewModel(client: client))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hello, SwiftUI from iOS!")
                .font(.headline)
            Text("gRPC Swift + iOS Demo")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Target: \(backendHost):\(backendPort)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Name", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button(model.loading ? "Calling..." : "Call SayHello") {
                model.callSayHello()
            }
            .disabled(model.loading)
            .buttonStyle(.borderedProminent)

            if !model.responseMessage.isEmpty {
                Text(model.responseMessage)
            }

            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(24)
    }
}

@main
struct GreeterApp: App {
    private let client: GreeterServing = {
        do {
            return try GrpcGreeterClient()
        } catch {
            return FailingGreeterClient(error: error)
        }
    }()

    var body: some Scene {
        WindowGroup {
            GreeterView(client: client)
        }
    }
}
