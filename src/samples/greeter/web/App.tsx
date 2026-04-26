import { FormEvent, useEffect, useState } from "react";
import { createClient } from "@connectrpc/connect";
import { createGrpcWebTransport } from "@connectrpc/connect-web";
import { Greeter } from "../proto/greeter_pb.js";
import { greetingMessage } from "../shared/library_wasm_files/library.mjs";

const grpcBaseUrl = "/grpc";
const transport = createGrpcWebTransport({ baseUrl: grpcBaseUrl });
const greeterClient = createClient(Greeter, transport) as unknown as {
  sayHello(request: { name: string }): Promise<{ message: string }>;
};

const useCurrentPage = () => {
  const [page, setPage] = useState(() =>
    window.location.hash === "#/shared" ? "shared" : "grpc",
  );

  useEffect(() => {
    const onHashChange = () => {
      setPage(window.location.hash === "#/shared" ? "shared" : "grpc");
    };

    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  return page;
};

const GrpcPage = () => {
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
    <>
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
    </>
  );
};

const SharedWasmPage = () => {
  const [name, setName] = useState("world");
  const message = greetingMessage(name);

  return (
    <>
      <h1>Shared Kotlin/WASM Demo</h1>
      <p>
        This page imports the WASM output generated from the same Kotlin shared
        library used by the Android and desktop apps.
      </p>

      <form>
        <input
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="name"
          aria-label="name"
        />
      </form>

      <pre>{message}</pre>
    </>
  );
};

const App = () => {
  const page = useCurrentPage();

  return (
    <main>
      <nav>
        <a aria-current={page === "grpc" ? "page" : undefined} href="#/">
          gRPC service
        </a>
        <a
          aria-current={page === "shared" ? "page" : undefined}
          href="#/shared"
        >
          Shared WASM
        </a>
      </nav>
      {page === "shared" ? <SharedWasmPage /> : <GrpcPage />}
    </main>
  );
};

export default App;
