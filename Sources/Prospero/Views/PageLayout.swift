import Plot

struct PageLayout {
    var title: String
    var stylesheets: [String] = []
    @ComponentBuilder var content: () -> Component

    var html: HTML {
        HTML(
            .head(
                .meta(.charset(.utf8)),
                .meta(.name("viewport"), .content("width=device-width, initial-scale=1")),
                .title("\(title) — Prospero"),
                .stylesheet("/styles.css"),
                .forEach(stylesheets) { .stylesheet($0) },
                .script(.src("/htmx.min.js"))
            ),
            .body(
                .header(
                    .nav(
                        .a(.href("/"), .text("Prospero")),
                        .div(
                            .class("nav-links"),
                            .a(.href("/patterns"), .text("Patterns")),
                            .a(.href("/patterns/new"), .text("New Pattern"))
                        )
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
}
