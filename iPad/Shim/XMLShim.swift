import Foundation

// Foundation on iOS has no XML DOM (XMLDocument / XMLElement). This is the small subset the shared SVG and
// project parsers use, built on top of XMLParser.

class XMLNode {
    enum Kind { case text, element, document }
    let kind: Kind
    var stringValue: String?
    weak var parent: XMLNode?
    var children: [XMLNode]?

    init(kind: Kind, stringValue: String? = nil) {
        self.kind = kind
        self.stringValue = stringValue
    }
}

final class XMLElement: XMLNode {
    let name: String?
    private var attributes: [String: String] = [:]

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
        super.init(kind: .element)
        children = []
    }

    var localName: String? {
        guard let name else { return nil }
        if let i = name.lastIndex(of: ":") { return String(name[name.index(after: i)...]) }
        return name
    }

    func attribute(forName name: String) -> XMLNode? {
        attributes[name].map { XMLNode(kind: .text, stringValue: $0) }
    }

    /// An element's string value is all the text inside it.
    override var stringValue: String? {
        get { (children ?? []).compactMap { $0.stringValue }.joined() }
        set { }
    }
}

final class XMLDocument: NSObject, XMLParserDelegate {
    struct Options: OptionSet {
        let rawValue: Int
        static let nodeLoadExternalEntitiesNever = Options(rawValue: 1 << 19)
    }

    private var root: XMLElement?
    private var stack: [XMLElement] = []
    private var failure: Error?

    init(data: Data, options: Options) throws {
        super.init()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse(), failure == nil, root != nil else {
            throw failure ?? parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
    }

    func rootElement() -> XMLElement? { root }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        let e = XMLElement(name: name, attributes: attributes)
        if let top = stack.last {
            e.parent = top
            top.children?.append(e)
        } else if root == nil {
            root = e
        }
        stack.append(e)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        _ = stack.popLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { addText(string) }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { addText(String(decoding: CDATABlock, as: UTF8.self)) }

    private func addText(_ s: String) {
        guard let top = stack.last else { return }
        if let last = top.children?.last, last.kind == .text {
            last.stringValue = (last.stringValue ?? "") + s
        } else {
            let t = XMLNode(kind: .text, stringValue: s)
            t.parent = top
            top.children?.append(t)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { failure = parseError }
}
