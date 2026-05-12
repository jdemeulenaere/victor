import GreeterBackendConfig
import GreeterSharedLibrary
import GRPC
import NIOCore
import NIOPosix
import SwiftUI
import UIKit
import VictorApiIosSwiftClientProto

private let backendEndpoint = BackendConfig.shared.endpoint
private let defaultName = "world"

protocol GreeterServing: AnyObject {
    func sayHello(name: String, completion: @escaping (Result<String, Error>) -> Void)
}

final class GrpcGreeterClient: GreeterServing {
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let channel: GRPCChannel
    private let client: Victor_Api_V1_GreeterNIOClient

    init(endpoint: BackendEndpoint = backendEndpoint) throws {
        channel =
            try GRPCChannelPool.with(
                target: .host(endpoint.host, port: Int(endpoint.port)),
                transportSecurity: Self.transportSecurity(for: endpoint),
                eventLoopGroup: eventLoopGroup
            )
        client = Victor_Api_V1_GreeterNIOClient(channel: channel)
    }

    private static func transportSecurity(
        for endpoint: BackendEndpoint
    ) -> GRPCChannelPool.Configuration.TransportSecurity {
        if endpoint.usePlaintext {
            return .plaintext
        }
        return .tls(.makeClientConfigurationBackedByNIOSSL())
    }

    func sayHello(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        let request = Victor_Api_V1_HelloRequest.with {
            $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if $0.name.isEmpty {
                $0.name = defaultName
            }
        }

        client.sayHello(request).response.whenComplete { result in
            completion(result.map(\.message))
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

    func sayHello(name _: String, completion: @escaping (Result<String, Error>) -> Void) {
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
        let effectiveName = normalizedName(name)
        loading = true
        responseMessage = ""
        errorMessage = ""

        client.sayHello(name: effectiveName) { [weak self] result in
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

    private func normalizedName(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? defaultName : trimmedName
    }
}

struct SharedGreetingComposeView: UIViewControllerRepresentable {
    let name: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.controller.makeViewController(name: name)
    }

    func updateUIViewController(_: UIViewController, context: Context) {
        context.coordinator.controller.setName(name: name)
    }

    final class Coordinator {
        let controller = SharedGreetingComposeController()
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
            Text("Target: \(backendEndpoint.serviceUrl)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            SharedGreetingComposeView(name: model.name)
                .frame(height: 28)

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
