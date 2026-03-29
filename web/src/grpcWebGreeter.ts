const grpcBaseUrl = import.meta.env.VITE_BACKEND_GRPC_BASE_URL ?? '/grpc';
const grpcPath = '/victor.api.v1.Greeter/SayHello';
const grpcContentType = 'application/grpc-web+proto';

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const encodeHelloRequest = (name: string): Uint8Array => {
  const nameBytes = textEncoder.encode(name);
  if (nameBytes.length > 127) {
    throw new Error('Name is too long for this minimal demo');
  }

  // HelloRequest { string name = 1; }
  return Uint8Array.from([0x0a, nameBytes.length, ...nameBytes]);
};

const decodeHelloResponse = (messagePayload: Uint8Array): string => {
  if (messagePayload.length < 2 || messagePayload[0] !== 0x0a) {
    throw new Error('Unexpected protobuf payload');
  }

  const messageLength = messagePayload[1];
  const messageEnd = 2 + messageLength;
  if (messageEnd > messagePayload.length) {
    throw new Error('Invalid protobuf payload length');
  }

  return textDecoder.decode(messagePayload.slice(2, messageEnd));
};

const parseGrpcWebUnary = (payload: Uint8Array): Uint8Array => {
  if (payload.length < 5) {
    throw new Error('Invalid gRPC-Web payload');
  }

  const messageLength = (((payload[1] << 24) | (payload[2] << 16) | (payload[3] << 8) | payload[4]) >>> 0);
  const messageStart = 5;
  const messageEnd = messageStart + messageLength;
  if (messageEnd > payload.length) {
    throw new Error('Invalid gRPC-Web message frame length');
  }

  // Optional trailer frame with grpc-status.
  if (messageEnd + 5 <= payload.length && payload[messageEnd] === 0x80) {
    const trailerLength =
      (((payload[messageEnd + 1] << 24) |
        (payload[messageEnd + 2] << 16) |
        (payload[messageEnd + 3] << 8) |
        payload[messageEnd + 4]) >>> 0);

    const trailerStart = messageEnd + 5;
    const trailerEnd = trailerStart + trailerLength;
    if (trailerEnd <= payload.length) {
      const trailerText = textDecoder.decode(payload.slice(trailerStart, trailerEnd));
      const statusMatch = trailerText.match(/grpc-status:\s*(\d+)/i);
      const grpcStatus = statusMatch ? Number(statusMatch[1]) : 0;
      if (grpcStatus !== 0) {
        throw new Error(`gRPC error ${grpcStatus}`);
      }
    }
  }

  return payload.slice(messageStart, messageEnd);
};

export const sayHello = async (name: string): Promise<string> => {
  const requestMessage = encodeHelloRequest(name);
  const frame = new Uint8Array(5 + requestMessage.length);
  frame[0] = 0x00;
  frame[1] = (requestMessage.length >>> 24) & 0xff;
  frame[2] = (requestMessage.length >>> 16) & 0xff;
  frame[3] = (requestMessage.length >>> 8) & 0xff;
  frame[4] = requestMessage.length & 0xff;
  frame.set(requestMessage, 5);

  const response = await fetch(`${grpcBaseUrl}${grpcPath}`, {
    method: 'POST',
    headers: {
      'Content-Type': grpcContentType,
      Accept: grpcContentType,
      'X-Grpc-Web': '1',
      'X-User-Agent': 'victor-web',
    },
    body: frame,
  });

  const payload = new Uint8Array(await response.arrayBuffer());
  if (!response.ok && payload.length === 0) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }

  return decodeHelloResponse(parseGrpcWebUnary(payload));
};

export const grpcInfo = {
  baseUrl: grpcBaseUrl,
  service: 'victor.api.v1.Greeter',
  method: 'SayHello',
} as const;
