import argparse

import grpc
from src.samples.greeter.proto import greeter_pb2
from src.samples.greeter.proto import greeter_pb2_grpc


def main():
    parser = argparse.ArgumentParser(description="Simple gRPC Python client.")
    parser.add_argument("name", nargs="?", default="from Python")
    parser.add_argument(
        "--target",
        default="localhost:8080",
        help="Kotlin gRPC server host:port",
    )
    args = parser.parse_args()

    with grpc.insecure_channel(args.target) as channel:
        stub = greeter_pb2_grpc.GreeterStub(channel)
        response = stub.SayHello(greeter_pb2.HelloRequest(name=args.name))
        print(response.message)


if __name__ == "__main__":
    main()
