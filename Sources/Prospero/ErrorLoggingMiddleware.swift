import Hummingbird
import Logging

struct ErrorLoggingMiddleware<Context: RequestContext>: RouterMiddleware {
    let logger: Logger

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch {
            logger.error(
                "Request failed",
                metadata: [
                    "path": .string(request.uri.description),
                    "method": .string(request.method.rawValue),
                    "error": .string(String(describing: error)),
                ]
            )
            throw error
        }
    }
}
