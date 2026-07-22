import UniformTypeIdentifiers

extension UTType {
    static var shakespeareDocument: UTType {
        UTType(exportedAs: "com.shakespeare.document", conformingTo: .package)
    }
}
