import Plot
import PlotHTMX

struct ProfilePage {
    var displayName: String
    var email: String
    var savedMessage: String?
    var pageContext: PageContext

    var html: HTML {
        PageLayout(title: "Profile", pageContext: pageContext) {
            H1("Profile")

            if let msg = savedMessage {
                Div { Paragraph(msg) }.class("flash-message flash-success")
            }

            Element(name: "form") {
                FormField(label: "Display Name", name: "display_name", type: "text",
                          value: displayName, required: true)
                FormField(label: "Email", name: "email", type: "email",
                          value: email, required: true)
                Div {
                    Element(name: "button") { Text("Save") }
                        .type("submit")
                        .class("button primary")
                }
                .class("form-actions")
            }
            .attribute(named: "method", value: "POST")
            .attribute(named: "action", value: "/profile")
        }.html
    }
}
