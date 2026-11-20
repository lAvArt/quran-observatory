import QtQuick

// Every string this plugin draws comes from downloaded data or a catalog, so
// none of it is ever read as rich text: markup-shaped input stays literal.
Text {
  textFormat: Text.PlainText
}
