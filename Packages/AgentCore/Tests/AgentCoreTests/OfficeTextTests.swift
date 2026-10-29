import Foundation
import Testing
@testable import AgentCore

private func data(_ text: String) -> Data { Data(text.utf8) }

@Test func extractsWordParagraphs() {
    let xml = """
    <w:document xmlns:w="w"><w:body>
    <w:p><w:r><w:t>Merhaba</w:t></w:r><w:r><w:t xml:space="preserve"> dünya</w:t></w:r></w:p>
    <w:p><w:r><w:t>İkinci</w:t><w:tab/><w:t>satır</w:t></w:r></w:p>
    </w:body></w:document>
    """

    let text = OfficeText.extract(kind: .word, entries: ["word/document.xml"]) { $0 == "word/document.xml" ? data(xml) : nil }

    #expect(text == "Merhaba dünya\nİkinci\tsatır")
}

@Test func extractsSlidesInOrder() {
    let slide = { (title: String) in "<p:sld xmlns:a=\"a\"><a:p><a:r><a:t>\(title)</a:t></a:r></a:p></p:sld>" }
    let files = [
        "ppt/slides/slide10.xml": slide("Son"),
        "ppt/slides/slide2.xml": slide("İki"),
        "ppt/slides/slide1.xml": slide("Bir"),
    ]

    let text = OfficeText.extract(kind: .presentation, entries: Array(files.keys) + ["ppt/slides/_rels/slide1.xml.rels"]) { files[$0].map(data) }

    #expect(text == "## Slide 1\nBir\n\n## Slide 2\nİki\n\n## Slide 3\nSon")
}

@Test func extractsSpreadsheetWithSharedStrings() {
    let files = [
        "xl/workbook.xml": #"<workbook xmlns:r="r"><sheets><sheet name="Satışlar" sheetId="1" r:id="rId1"/></sheets></workbook>"#,
        "xl/_rels/workbook.xml.rels": #"<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>"#,
        "xl/sharedStrings.xml": #"<sst><si><t>Ürün</t></si><si><r><t>Ad</t></r><r><t>et</t></r></si><si><t>Çay</t><rPh><t>x</t></rPh></si></sst>"#,
        "xl/worksheets/sheet1.xml": """
        <worksheet><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
        <row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><v>42</v></c><c r="D2" t="b"><v>1</v></c></row>
        <row r="3"><c r="A3" t="inlineStr"><is><t>Not</t></is></c></row>
        </sheetData></worksheet>
        """,
    ]

    let text = OfficeText.extract(kind: .spreadsheet, entries: Array(files.keys)) { files[$0].map(data) }

    #expect(text == "## Satışlar\nÜrün\tAdet\nÇay\t\t42\tTRUE\nNot")
}

@Test(arguments: [("A1", 0), ("C12", 2), ("Z9", 25), ("AA1", 26), ("ab3", 27)])
func columnIndexes(_ reference: String, _ expected: Int) {
    #expect(OfficeText.columnIndex(reference) == expected)
}

@Test func missingPartsReturnNil() {
    #expect(OfficeText.extract(kind: .word, entries: []) { _ in nil } == nil)
    #expect(OfficeText.extract(kind: .presentation, entries: []) { _ in nil } == nil)
}
