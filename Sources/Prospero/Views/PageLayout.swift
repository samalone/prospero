import Hummingbird
import HummingbirdAuth
import HummingbirdAuthViews
import Plot
import PlotHTMX

struct PageLayout: ResponseGenerator {
    var title: String
    var pageContext: PageContext = PageContext()
    var includeAuthScript: Bool = false
    @ComponentBuilder var content: () -> Component

    var html: HTML {
        HTML(
            .head(
                .meta(.charset(.utf8)),
                .meta(.name("viewport"), .content("width=device-width, initial-scale=1")),
                .title("\(title) — Prospero"),
                .stylesheet("/styles.css"),
                .script(.src("/htmx.min.js")),
                .if(includeAuthScript, .raw(WebAuthnScript.scriptTag))
            ),
            .body(
                .header(
                    .nav(
                        .class("top-nav"),
                        .a(.href("/"), .text("Prospero")),
                        .if(pageContext.isLoggedIn,
                            .div(
                                .class("nav-links"),
                                .a(.href("/patterns"), .text("Patterns")),
                                .a(.href("/patterns/new"), .text("New Pattern"))
                            )
                        ),
                        .div(
                            .class("nav-right"),
                            .if(pageContext.isLoggedIn,
                                .group(
                                    .element(named: "button",
                                        nodes: [
                                            .attribute(named: "popovertarget", value: "user-menu"),
                                            .class("user-menu-button"),
                                            .text(pageContext.userName ?? "Account"),
                                        ]
                                    ),
                                    .div(
                                        .id("user-menu"),
                                        .attribute(named: "popover", value: "auto"),
                                        .class("popover-menu"),
                                        .if(pageContext.masqueradingAs != nil,
                                            .group(
                                                .div(.class("menu-info"),
                                                     .text("Viewing as \(pageContext.masqueradingAs ?? "")")),
                                                .form(
                                                    .method(.post),
                                                    .action("/admin/masquerade/end"),
                                                    .element(named: "button",
                                                        nodes: [
                                                            .attribute(named: "type", value: "submit"),
                                                            .class("menu-link"),
                                                            .text("Switch back"),
                                                        ]
                                                    )
                                                )
                                            ),
                                            else: .group(
                                                .a(.href("/profile"), .text("Profile")),
                                                .if(pageContext.isAdmin,
                                                    .group(
                                                        .element(named: "hr", nodes: []),
                                                        .a(.href("/admin/users"), .text("Users")),
                                                        .a(.href("/admin/invitations"), .text("Invitations"))
                                                    )
                                                ),
                                                .element(named: "hr", nodes: []),
                                                .form(
                                                    .method(.post),
                                                    .action("/auth/logout"),
                                                    .element(named: "button",
                                                        nodes: [
                                                            .attribute(named: "type", value: "submit"),
                                                            .class("menu-link"),
                                                            .text("Sign out"),
                                                        ]
                                                    )
                                                )
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )
                ),
                .if(!pageContext.flashMessages.isEmpty,
                    .div(
                        .id("flash-messages"),
                        .forEach(pageContext.flashMessages) { flash in
                            .div(
                                .class("flash-message flash-\(flash.level.rawValue)"),
                                .text(flash.text)
                            )
                        }
                    )
                ),
                .main(
                    .component(content())
                ),
                .footer(
                    .p(.text("Prospero — Reverse Weather Forecaster"))
                )
            )
        )
    }

    func response(from request: Request, context: some RequestContext) throws -> Response {
        htmlResponse(html.render())
    }
}
