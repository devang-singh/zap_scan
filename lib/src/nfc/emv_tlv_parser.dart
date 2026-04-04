import 'dart:typed_data';
import 'emv_card.dart';

class AflEntry {
  const AflEntry({required this.sfi, required this.first, required this.last});
  final int sfi;
  final int first;
  final int last;
}

class EmvTlvParser {
  /// Extracts the EmvCard using Regex on the raw hex response to find Track 2 or PAN.
  /// This bypasses the need for a recursive BER-TLV hex byte parser.
  static EmvCard? parseCardData(String hexResponse) {
    if (hexResponse.isEmpty) return null;
    final hexStr = hexResponse.replaceAll(' ', '').toUpperCase();

    // Look for Tag 57 (Track 2 Equivalent Data)
    // Format: 57 <Length HEX> <PAN> D <YYMM> <Service Code> <Discretionary>
    // 'D' or '=' is the standard separator in Track 2 hex.
    final track2Regex =
        RegExp(r'57([0-9A-F]{2})([0-9A-F]{13,19})[D=]([0-9]{4})');
    final match = track2Regex.firstMatch(hexStr);

    if (match != null) {
      final pan = match.group(2);
      final expiryYYMM = match.group(3);

      if (pan != null && expiryYYMM != null) {
        return EmvCard(cardNumber: pan, expiryDate: expiryYYMM);
      }
    }

    // Look for Tag 5A (PAN) if 57 isn't found
    final panRegex = RegExp(r'5A([0-9A-F]{2})([0-9A-F]{12,19})');
    final panMatch = panRegex.firstMatch(hexStr);

    // Look for Tag 5F24 (Expiry Date) - Format YYMMDD
    final expiryRegex = RegExp(r'5F2403([0-9]{4})');
    final expMatch = expiryRegex.firstMatch(hexStr);

    if (panMatch != null) {
      String pan = panMatch.group(2)!;
      // EMV pads PANs with 'F' at the end if odd length (e.g. 15-digit Amex)
      if (pan.endsWith('F') || pan.endsWith('f')) {
        pan = pan.substring(0, pan.length - 1);
      }
      String expiry = expMatch != null ? expMatch.group(1)! : '';
      return EmvCard(cardNumber: pan, expiryDate: expiry);
    }

    return null;
  }

  static List<List<int>> findAllTlv(List<int> data, int targetTag) {
    final results = <List<int>>[];
    _collectTlv(data, targetTag, results);
    return results;
  }

  static void _collectTlv(List<int> data, int targetTag, List<List<int>> out) {
    int i = 0;
    while (i < data.length) {
      final firstByte = data[i] & 0xFF;
      int tag = firstByte;
      i++;
      if ((firstByte & 0x1F) == 0x1F && i < data.length) {
        tag = (tag << 8) | (data[i++] & 0xFF);
      }
      if (i >= data.length) break;
      final int lenByte = data[i++] & 0xFF;
      int length;
      if (lenByte == 0x81) {
        if (i >= data.length) break;
        length = data[i++] & 0xFF;
      } else if (lenByte == 0x82) {
        if (i + 1 >= data.length) break;
        length = ((data[i++] & 0xFF) << 8) | (data[i++] & 0xFF);
      } else {
        length = lenByte;
      }
      if (i + length > data.length) break;
      final value = data.sublist(i, i + length);
      if (tag == targetTag) out.add(value);
      if ((firstByte & 0x20) != 0) _collectTlv(value, targetTag, out);
      i += length;
    }
  }

  static List<int>? findTlv(List<int> data, int targetTag) {
    int i = 0;
    while (i < data.length) {
      if (i >= data.length) break;

      final int firstByte = data[i] & 0xFF;
      int tag = firstByte;
      i++;
      if ((firstByte & 0x1F) == 0x1F) {
        tag = (tag << 8) | (data[i] & 0xFF);
        i++;
      }

      if (i >= data.length) break;

      int length;
      final int lenByte = data[i++] & 0xFF;
      if (lenByte == 0x81) {
        if (i >= data.length) break;
        length = data[i++] & 0xFF;
      } else if (lenByte == 0x82) {
        if (i + 1 >= data.length) break;
        length = ((data[i++] & 0xFF) << 8) | (data[i++] & 0xFF);
      } else {
        length = lenByte;
      }

      if (i + length > data.length) break;
      final value = data.sublist(i, i + length);

      if (tag == targetTag) return value;

      if ((firstByte & 0x20) != 0) {
        final found = findTlv(value, targetTag);
        if (found != null) return found;
      }

      i += length;
    }
    return null;
  }

  static String hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();

  /// Parses the Application File Locator from a GPO response.
  /// Format 1 (tag 0x80) and Format 2 (TLV tag 0x77) supported.
  static List<AflEntry>? parseAfl(Uint8List gpoResp) {
    final data = gpoResp.sublist(0, gpoResp.length - 2); // strip SW1 SW2
    List<int>? aflBytes;

    if (data.isNotEmpty && data[0] == 0x80) {
      // Format 1: 80 <len> <AIP 2 bytes> <AFL bytes...>
      final len = data[1];
      if (len > 2) aflBytes = data.sublist(4, 2 + len);
    } else {
      // Format 2: TLV, tag 0x94 inside tag 0x77
      aflBytes = findTlv(data, 0x94);
    }

    if (aflBytes == null || aflBytes.isEmpty || aflBytes.length % 4 != 0) {
      return null;
    }

    final entries = <AflEntry>[];
    for (int i = 0; i < aflBytes.length; i += 4) {
      final sfi = (aflBytes[i] >> 3) & 0x1F;
      final first = aflBytes[i + 1];
      final last = aflBytes[i + 2];
      if (sfi > 0 && first > 0 && last >= first) {
        entries.add(AflEntry(sfi: sfi, first: first, last: last));
      }
    }
    return entries.isEmpty ? null : entries;
  }
}
