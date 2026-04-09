import { FormEvent, useState } from 'react';
import {
  GreeterClient,
  GREETER_SAY_HELLO_METHOD,
  GREETER_SERVICE,
} from './generated/greeter_client';

const grpcBaseUrl = import.meta.env.VITE_BACKEND_GRPC_BASE_URL ?? '/grpc';
const greeterClient = new GreeterClient({ baseUrl: grpcBaseUrl });

const App = () => {
  const [name, setName] = useState('world');
  const [responseMessage, setResponseMessage] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [loading, setLoading] = useState(false);

  const onSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setErrorMessage('');

    try {
      const response = await greeterClient.sayHello({ name });
      setResponseMessage(response.message);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Unknown error');
      setResponseMessage('');
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="app">
      <h1>gRPC Kotlin + React Demo</h1>
      <p>This React app calls the Kotlin gRPC service using generated TypeScript client code.</p>
      <p className="meta">
        Service: <code>{GREETER_SERVICE}</code>
      </p>
      <p className="meta">
        RPC: <code>{GREETER_SAY_HELLO_METHOD}</code>
      </p>
      <p className="meta">
        gRPC base URL: <code>{grpcBaseUrl}</code>
      </p>

      <form onSubmit={onSubmit} className="form">
        <input
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="name"
          aria-label="name"
        />
        <button type="submit" disabled={loading}>
          {loading ? 'Calling...' : 'Call SayHello'}
        </button>
      </form>

      {responseMessage ? <pre>{responseMessage}</pre> : null}
      {errorMessage ? <pre className="error">{errorMessage}</pre> : null}
    </main>
  );
};

export default App;
