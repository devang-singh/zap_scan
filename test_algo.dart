import 'dart:core';

void main() {
  var tests = [
    """
Federal Bank
40251
Issued by
8L001 D354by
 scopia
 8548
 Designed
 10/30
 DATE
""",
    """
00000
JAIN
Valid
YASH RAKESH
upto
Cyy
b529 b000
D000 079
DISCeVER
Issued by Federal Bank
0/30
Designed
by Scapia
320
Diners Chub INTERNATIONAL
pulse
MPi N KA• P300476 1224
""",
    """
Issued by
Federal Bank
40291
8L001
Designed
by Scopia
0541 8548
10/30
DATE
107
BECURTY
CODL
""",
    """
4712|
27001
315 6|
|4669
598
03/31
MANAGED BY
Une
"""
  ];

  for (var rawText in tests) {
    print("--- test ---");
    var res = extract(rawText);
    print("Result: \$res");
  }
}

String? extract(String rawText) {
  // We need to implement the extraction logic here to test it.
  return null;
}
