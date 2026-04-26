@testable import VictorGreeterIOS
import XCTest

final class GreeterAppTest: XCTestCase {
    @MainActor
    func testCallSayHelloShowsResponse() async {
        let model = GreeterViewModel(client: StubGreeterClient())

        model.name = "iOS test"
        model.callSayHello()
        await Task.yield()

        XCTAssertEqual(model.responseMessage, "Hello, iOS test! (from iOS test)")
        XCTAssertFalse(model.loading)
    }
}

private final class StubGreeterClient: GreeterServing {
    func sayHello(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("Hello, \(name)! (from iOS test)"))
    }
}
