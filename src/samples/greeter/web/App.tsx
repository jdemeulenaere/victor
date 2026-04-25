import { FormEvent, useState } from "react";
import { createClient } from "@connectrpc/connect";
import { createGrpcWebTransport } from "@connectrpc/connect-web";
import { Greeter } from "../proto/greeter_pb.js";

const grpcBaseUrl = "/grpc";
const transport = createGrpcWebTransport({ baseUrl: grpcBaseUrl });
const greeterClient = createClient(Greeter, transport) as unknown as {
  sayHello(request: { name: string }): Promise<{ message: string }>;
};

const App = () => {
  const [name, setName] = useState("world");
  const [responseMessage, setResponseMessage] = useState("");
  const [errorMessage, setErrorMessage] = useState("");
  const [loading, setLoading] = useState(false);

  const onSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setErrorMessage("");
    setResponseMessage("");

    try {
      const response = await greeterClient.sayHello({ name });
      setResponseMessage(response.message);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Unknown error");
    } finally {
      setLoading(false);
    }
  };

  return (
    <main>
      <h1>gRPC Kotlin + React Demo</h1>
      <p>
        This app calls the Kotlin gRPC service using generated TypeScript client
        code.
      </p>
      <p>
        Service: <code>{Greeter.typeName}</code>
      </p>
      <p>
        RPC: <code>{Greeter.method.sayHello.name}</code>
      </p>
      <p>
        gRPC base URL: <code>{grpcBaseUrl}</code>
      </p>

      <form onSubmit={onSubmit}>
        <input
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="name"
          aria-label="name"
        />
        <button type="submit" disabled={loading}>
          {loading ? "Calling..." : "Call SayHello"}
        </button>
      </form>

      {responseMessage ? <pre>{responseMessage}</pre> : null}
      {errorMessage ? <pre className="error">{errorMessage}</pre> : null}
    </main>
  );
};

export default App;
