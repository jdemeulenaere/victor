import { FormEvent, useState } from 'react';
import { grpcInfo, sayHello } from './grpcWebGreeter';

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
      setResponseMessage(await sayHello(name));
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : 'Unknown error');
      setResponseMessage('');
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="app">
      <h1>Simple Bazel Monorepo</h1>
      <p>Kotlin backend + TypeScript web + Python script, all in one Bazel workspace.</p>
      <p className="meta">
        Service: <code>{grpcInfo.service}</code>
      </p>
      <p className="meta">
        RPC: <code>{grpcInfo.method}</code>
      </p>
      <p className="meta">
        gRPC base URL: <code>{grpcInfo.baseUrl}</code>
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
