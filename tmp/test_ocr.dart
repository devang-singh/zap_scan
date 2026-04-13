import 'dart:io';

void main() {
  final rawText = """
Search SeAPIA
Federal Bank
ssued by
by Scopia
DesI
4029
8L00
0354
|8548
10/30
107
VISA
o00045
Signature
FŽ
%
7
#
5
3
""";

  final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  final chars = StringBuffer('0-9');
  const _definiteDigits = <String, String>{
    'b': '6', 'l': '1', 'I': '1', 'i': '1', 'O': '0', 'o': '0', 'D': '0',
    'S': '5', 'Y': '4', 'y': '4', 'G': '6', 'K': '6', 'Z': '2', 'a': '8',
  };
  const _ambiguous = <String, List<String>>{
    'L': ['6'], 'B': ['8', '6'],
  };
  chars.write(_definiteDigits.keys.join());
  chars.write(_ambiguous.keys.join());
  final d = '[$chars]';
  final blockRegex = RegExp('($d{4,})');

  for (final line in lines) {
    final matches = blockRegex.allMatches(line);
    for (final match in matches) {
      print('Group match: ${match.group(0)} from line "$line"');
    }
  }
}
