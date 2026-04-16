/// Plot extensions for HTMX, SSE, and commonly used HTML attributes.
///
/// Plot's type-safe DSL covers standard HTML attributes, but HTMX, SSE, ARIA,
/// and `data-*` attributes require the generic `.attribute(named:value:)` escape
/// hatch. These extensions provide concise, discoverable modifiers that follow
/// Plot's existing `Component` modifier pattern.
///
/// Usage:
/// ```swift
/// Element(name: "form") { ... }
///     .hxPost("/action")
///     .hxTarget("#results")
///     .hxSwap(.beforeEnd)
///     .hxOnAfterRequest("this.reset()")
/// ```

import Plot

// MARK: - HTMX swap strategies

/// Type-safe values for the `hx-swap` attribute.
///
/// See https://htmx.org/attributes/hx-swap/
enum HTMXSwap: String {
    /// Replace the inner HTML of the target element (default).
    case innerHTML
    /// Replace the entire target element.
    case outerHTML
    /// Insert before the target element.
    case beforeBegin = "beforebegin"
    /// Insert as the first child of the target element.
    case afterBegin = "afterbegin"
    /// Insert as the last child of the target element.
    case beforeEnd = "beforeend"
    /// Insert after the target element.
    case afterEnd = "afterend"
    /// Remove the target element.
    case delete
    /// Do not swap (useful for side-effect-only requests).
    case none
}

// MARK: - HTMX attributes

extension Component {

    // MARK: Request triggers

    /// Issue an HTMX GET request to the given URL.
    func hxGet(_ url: String) -> Component {
        attribute(named: "hx-get", value: url)
    }

    /// Issue an HTMX POST request to the given URL.
    func hxPost(_ url: String) -> Component {
        attribute(named: "hx-post", value: url)
    }

    /// Issue an HTMX PUT request to the given URL.
    func hxPut(_ url: String) -> Component {
        attribute(named: "hx-put", value: url)
    }

    /// Issue an HTMX PATCH request to the given URL.
    func hxPatch(_ url: String) -> Component {
        attribute(named: "hx-patch", value: url)
    }

    /// Issue an HTMX DELETE request to the given URL.
    func hxDelete(_ url: String) -> Component {
        attribute(named: "hx-delete", value: url)
    }

    // MARK: Targeting and swapping

    /// Specify the target element for HTMX content swapping.
    func hxTarget(_ selector: String) -> Component {
        attribute(named: "hx-target", value: selector)
    }

    /// Specify how the response content is swapped into the DOM.
    func hxSwap(_ strategy: HTMXSwap) -> Component {
        attribute(named: "hx-swap", value: strategy.rawValue)
    }

    /// Specify how the response content is swapped into the DOM (string variant).
    ///
    /// Use this for compound swap values like `"innerHTML swap:1s"`.
    func hxSwap(_ value: String) -> Component {
        attribute(named: "hx-swap", value: value)
    }

    // MARK: Triggers and parameters

    /// Specify the event that triggers the HTMX request.
    func hxTrigger(_ event: String) -> Component {
        attribute(named: "hx-trigger", value: event)
    }

    /// Include additional values in the HTMX request.
    func hxVals(_ values: String) -> Component {
        attribute(named: "hx-vals", value: values)
    }

    /// Include additional element values in the HTMX request.
    func hxInclude(_ selector: String) -> Component {
        attribute(named: "hx-include", value: selector)
    }

    /// Select a subset of the server response to swap.
    func hxSelect(_ selector: String) -> Component {
        attribute(named: "hx-select", value: selector)
    }

    // MARK: Confirmation and indicators

    /// Show a confirmation dialog before issuing the request.
    func hxConfirm(_ message: String) -> Component {
        attribute(named: "hx-confirm", value: message)
    }

    /// Specify an indicator element to show during the request.
    func hxIndicator(_ selector: String) -> Component {
        attribute(named: "hx-indicator", value: selector)
    }

    // MARK: HTMX extensions

    /// Enable HTMX extensions on this element.
    func hxExt(_ extensions: String) -> Component {
        attribute(named: "hx-ext", value: extensions)
    }

    // MARK: Event handlers

    /// Run JavaScript after an HTMX request completes.
    func hxOnAfterRequest(_ script: String) -> Component {
        attribute(named: "hx-on::after-request", value: script)
    }

    /// Run JavaScript before an HTMX request is sent.
    func hxOnBeforeRequest(_ script: String) -> Component {
        attribute(named: "hx-on::before-request", value: script)
    }

    /// Run JavaScript after HTMX swaps content into the DOM.
    func hxOnAfterSwap(_ script: String) -> Component {
        attribute(named: "hx-on::after-swap", value: script)
    }
}

// MARK: - SSE attributes

extension Component {

    /// Connect this element to an SSE event source.
    func sseConnect(_ url: String) -> Component {
        attribute(named: "sse-connect", value: url)
    }

    /// Swap this element's content when an SSE event is received.
    func sseSwap(_ event: String) -> Component {
        attribute(named: "sse-swap", value: event)
    }
}

// MARK: - HTML attributes not on Component in Plot

extension Component {

    /// Set the `title` tooltip attribute.
    func title(_ text: String) -> Component {
        attribute(named: "title", value: text)
    }

    /// Set the `hidden` attribute.
    func hidden(_ isHidden: Bool = true) -> Component {
        isHidden
            ? attribute(named: "hidden", value: "hidden")
            : self
    }

    /// Set the `hidden` attribute to a specific value (e.g., `"until-found"`).
    func hidden(_ value: String) -> Component {
        attribute(named: "hidden", value: value)
    }

    /// Set the `draggable` attribute.
    func draggable(_ isDraggable: Bool = true) -> Component {
        attribute(named: "draggable", value: isDraggable ? "true" : "false")
    }

    /// Set the `autocomplete` attribute.
    func autocomplete(_ value: String) -> Component {
        attribute(named: "autocomplete", value: value)
    }

    /// Set an inline event handler.
    func on(_ event: String, _ script: String) -> Component {
        attribute(named: "on\(event)", value: script)
    }

    /// Set the `type` attribute on a button or input element.
    func type(_ value: String) -> Component {
        attribute(named: "type", value: value)
    }

    /// Set the `checked` attribute on a checkbox or radio input.
    func checked(_ isChecked: Bool = true) -> Component {
        isChecked
            ? attribute(named: "checked", value: "checked")
            : self
    }
}

// MARK: - Conditional attributes

extension Component {
    /// Add an attribute only when a condition is true.
    func conditionalAttribute(
        _ condition: Bool,
        named name: String,
        value: String
    ) -> Component {
        condition ? attribute(named: name, value: value) : self
    }
}

// MARK: - Node-level HTMX and SSE attributes

/// Node-level extensions for use inside Plot's element-based DSL (e.g.,
/// `.div(...)`, `.form(...)`, `.main(...)`).
extension Node where Context: HTML.BodyContext {
    static func hxExt(_ extensions: String) -> Node {
        .attribute(named: "hx-ext", value: extensions)
    }

    static func sseConnect(_ url: String) -> Node {
        .attribute(named: "sse-connect", value: url)
    }

    static func sseSwap(_ event: String) -> Node {
        .attribute(named: "sse-swap", value: event)
    }

    static func hxGet(_ url: String) -> Node {
        .attribute(named: "hx-get", value: url)
    }

    static func hxPost(_ url: String) -> Node {
        .attribute(named: "hx-post", value: url)
    }

    static func hxDelete(_ url: String) -> Node {
        .attribute(named: "hx-delete", value: url)
    }

    static func hxTarget(_ selector: String) -> Node {
        .attribute(named: "hx-target", value: selector)
    }

    static func hxSwap(_ strategy: HTMXSwap) -> Node {
        .attribute(named: "hx-swap", value: strategy.rawValue)
    }

    static func hxTrigger(_ event: String) -> Node {
        .attribute(named: "hx-trigger", value: event)
    }

    static func hxConfirm(_ message: String) -> Node {
        .attribute(named: "hx-confirm", value: message)
    }
}

/// Node-level HTMX attributes for form elements.
extension Node where Context == HTML.FormContext {
    static func hxPost(_ url: String) -> Node {
        .attribute(named: "hx-post", value: url)
    }

    static func hxTarget(_ selector: String) -> Node {
        .attribute(named: "hx-target", value: selector)
    }

    static func hxSwap(_ strategy: HTMXSwap) -> Node {
        .attribute(named: "hx-swap", value: strategy.rawValue)
    }
}
