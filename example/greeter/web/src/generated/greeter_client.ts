// Code generated from example/greeter/proto/greeter.proto. DO NOT EDIT.

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export const GREETER_SERVICE = 'victor.api.v1.Greeter' as const;
export const GREETER_SAY_HELLO_METHOD = 'SayHello' as const;
export const GREETER_SAY_HELLO_PATH = `/${GREETER_SERVICE}/${GREETER_SAY_HELLO_METHOD}` as const;

export interface HelloRequest {
  name: string;
}

export interface HelloResponse {
  message: string;
}

export interface GreeterClientOptions {
  baseUrl: string;
  fetchImpl?: typeof fetch;
}

const encodeHelloRequest = (message: HelloRequest): Uint8Array => {
  const nameBytes = textEncoder.encode(message.name);
  if (nameBytes.length > 127) {
    throw new Error('name is too long for this demo proto encoder');
  }

  // HelloRequest { string name = 1; }
  return Uint8Array.from([0x0a, nameBytes.length, ...nameBytes]);
};

const decodeHelloResponse = (payload: Uint8Array): HelloResponse => {
  if (payload.length < 2 || payload[0] !== 0x0a) {
    throw new Error('invalid HelloResponse payload');
  }

  const messageLength = payload[1];
  const messageEnd = 2 + messageLength;
  if (messageEnd > payload.length) {
    throw new Error('invalid HelloResponse length');
  }

  return {
    message: textDecoder.decode(payload.slice(2, messageEnd)),
  };
};

const createGrpcWebFrame = (messagePayload: Uint8Array): Uint8Array => {
  const framed = new Uint8Array(5 + messagePayload.length);
  framed[0] = 0x00;
  framed[1] = (messagePayload.length >>> 24) & 0xff;
  framed[2] = (messagePayload.length >>> 16) & 0xff;
  framed[3] = (messagePayload.length >>> 8) & 0xff;
  framed[4] = messagePayload.length & 0xff;
  framed.set(messagePayload, 5);
  return framed;
};

const parseGrpcWebUnaryPayload = (payload: Uint8Array): Uint8Array => {
  if (payload.length < 5) {
    throw new Error('invalid gRPC-Web payload');
  }

  const messageLength =
    (((payload[1] << 24) | (payload[2] << 16) | (payload[3] << 8) | payload[4]) >>> 0);
  const messageStart = 5;
  const messageEnd = messageStart + messageLength;
  if (messageEnd > payload.length) {
    throw new Error('invalid gRPC-Web frame length');
  }

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

export class GreeterClient {
  private readonly baseUrl: string;

  private readonly fetchImpl: typeof fetch;

  constructor(options: GreeterClientOptions) {
    this.baseUrl = options.baseUrl;
    this.fetchImpl = options.fetchImpl ?? ((input, init) => globalThis.fetch(input, init));
  }

  async sayHello(request: HelloRequest): Promise<HelloResponse> {
    const requestFrame = createGrpcWebFrame(encodeHelloRequest(request));
    const requestBody = new Uint8Array(Array.from(requestFrame));

    const response = await this.fetchImpl(`${this.baseUrl}${GREETER_SAY_HELLO_PATH}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/grpc-web+proto',
        Accept: 'application/grpc-web+proto',
        'X-Grpc-Web': '1',
        'X-User-Agent': 'victor-web',
      },
      body: requestBody,
    });

    const responsePayload = new Uint8Array(await response.arrayBuffer());
    if (!response.ok && responsePayload.length === 0) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    return decodeHelloResponse(parseGrpcWebUnaryPayload(responsePayload));
  }
}
