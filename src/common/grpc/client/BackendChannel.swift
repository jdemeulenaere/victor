import GRPC
import NIOCore
import NIOPosix
import VictorBackendClient

public func buildChannel(endpoint: BackendEndpoint) throws -> BackendChannel {
    try BackendChannel(endpoint: endpoint)
}

public final class BackendChannel {
    public let channel: GRPCChannel

    private let eventLoopGroup: EventLoopGroup
    private var isClosed = false

    fileprivate init(
        endpoint: BackendEndpoint,
        numberOfThreads: Int = 1
    ) throws {
        precondition(numberOfThreads > 0, "numberOfThreads must be greater than zero")

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
        do {
            channel = try GRPCChannelPool.with(
                target: .host(endpoint.host, port: Int(endpoint.port)),
                transportSecurity: transportSecurity(usePlaintext: endpoint.usePlaintext),
                eventLoopGroup: eventLoopGroup
            )
            self.eventLoopGroup = eventLoopGroup
        } catch {
            eventLoopGroup.shutdownGracefully { _ in }
            throw error
        }
    }

    public func close(onError: @escaping (Error) -> Void = { _ in }) {
        guard !isClosed else {
            return
        }
        isClosed = true

        channel.close().whenComplete { [eventLoopGroup] result in
            if case let .failure(error) = result {
                onError(error)
            }
            eventLoopGroup.shutdownGracefully { error in
                if let error {
                    onError(error)
                }
            }
        }
    }

    deinit {
        close()
    }
}

private func transportSecurity(
    usePlaintext: Bool
) -> GRPCChannelPool.Configuration.TransportSecurity {
    if usePlaintext {
        return .plaintext
    }
    return .tls(.makeClientConfigurationBackedByNIOSSL())
}
