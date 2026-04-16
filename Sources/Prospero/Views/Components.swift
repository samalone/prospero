import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import Plot

/// Make Plot's HTML document type returnable from Hummingbird route handlers.
extension HTML: @retroactive ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        htmlResponse(render())
    }
}

/// Build an HTML response from a pre-rendered string.
func htmlResponse(_ html: String, status: HTTPResponse.Status = .ok) -> Response {
    Response(
        status: status,
        headers: [.contentType: "text/html; charset=utf-8"],
        body: .init(byteBuffer: ByteBuffer(string: html))
    )
}
