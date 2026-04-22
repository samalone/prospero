import Hummingbird
import HummingbirdAuth
import HummingbirdAuthViews
import Plot
import PlotHTMX

struct PageLayout: ResponseGenerator {
    var title: String
    var pageContext: PageContext = PageContext()
    var includeAuthScript: Bool = false
    /// Opt in to the Leaflet assets + pattern-map.js (pattern editor only).
    var includeMapScript: Bool = false
    /// Opt in to the range-slider.js custom component (pattern editor).
    var includeRangeSliderScript: Bool = false
    /// Opt in to calendar.js (tap-to-select behavior on the calendar view).
    var includeCalendarScript: Bool = false
    @ComponentBuilder var content: () -> Component

    private func url(_ path: String) -> String { mountURL(path) }

    /// Append a cache-busting query string to a static asset path.
    /// Bumped at release time with `prosperoVersion`, so new releases
    /// force browsers to refetch even when the asset URL is otherwise
    /// unchanged and cached for a long time. Dev builds share a single
    /// "0.0.0-dev" version so Cmd+Shift+R still works there.
    private func asset(_ path: String) -> String {
        "\(mountURL(path))?v=\(prosperoVersion)"
    }

    var html: HTML {
        HTML(
            .head(
                .meta(.charset(.utf8)),
                .meta(.name("viewport"), .content("width=device-width, initial-scale=1")),
                .title("\(title) — Prospero"),
                .stylesheet(asset("/styles.css")),
                .if(includeMapScript, .stylesheet(asset("/leaflet.css"))),
                .script(.src(asset("/htmx.min.js"))),
                .if(includeAuthScript, .raw(WebAuthnScript.scriptTag)),
                .if(includeMapScript, .script(.src(asset("/leaflet.js")))),
                .if(includeMapScript, .script(.src(asset("/pattern-map.js")), .attribute(named: "defer"))),
                .if(includeRangeSliderScript, .script(.src(asset("/range-slider.js")), .attribute(named: "defer"))),
                .if(includeCalendarScript, .script(.src(asset("/calendar.js")), .attribute(named: "defer")))
            ),
            .body(
                .header(
                    .nav(
                        .class("top-nav"),
                        .a(.href(url("/")), .text("Prospero")),
                        .if(pageContext.isLoggedIn,
                            .div(
                                .class("nav-links"),
                                .a(.href(url("/patterns")), .text("Patterns")),
                                .a(.href(url("/calendar")), .text("Calendar")),
                                .a(.href(url("/patterns/new")), .text("New Pattern"))
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
                                                    .action(url("/admin/masquerade/end")),
                                                    .input(.type(.hidden), .name("csrf_token"),
                                                           .value(pageContext.csrfToken ?? "")),
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
                                                .a(.href(url("/profile")), .text("Profile")),
                                                .if(pageContext.isAdmin,
                                                    .group(
                                                        .element(named: "hr", nodes: []),
                                                        .a(.href(url("/admin/users")), .text("Users")),
                                                        .a(.href(url("/admin/invitations")), .text("Invitations"))
                                                    )
                                                ),
                                                .element(named: "hr", nodes: []),
                                                .form(
                                                    .method(.post),
                                                    .action(url("/auth/logout")),
                                                    .component(CSRFField(pageContext.csrfToken)),
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
                    .p(.text("Prospero \(prosperoVersion) — Reverse Weather Forecaster"))
                )
            )
        )
    }

    func response(from request: Request, context: some RequestContext) throws -> Response {
        htmlResponse(html.render())
    }
}
