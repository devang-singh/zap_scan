import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'emv_card.dart';
import 'emv_tlv_parser.dart';

class EmvNfcService {
  static Future<EmvCard?> scanCard() async {
    final availability = await NfcManager.instance.checkAvailability();
    if (availability != NfcAvailability.enabled) {
      throw Exception('NFC is not available on this device.');
    }

    final completer = Completer<EmvCard?>();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        try {
          final card = await _readEmvCard(tag);
          await NfcManager.instance.stopSession();
          if (!completer.isCompleted) completer.complete(card);
        } catch (e) {
          await NfcManager.instance.stopSession();
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
    );

    Future.delayed(const Duration(seconds: 20), () async {
      if (!completer.isCompleted) {
        await NfcManager.instance.stopSession();

        completer.completeError(Exception('NFC Scan Timed out.'));
      }
    });

    return completer.future;
  }

  static Future<EmvCard?> _readEmvCard(NfcTag tag) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    final isoDep = IsoDepAndroid.from(tag);
    if (isoDep == null) return null;

    // 1. SELECT PPSE to discover all AIDs on the card
    final ppseResp = await isoDep.transceive(
      Uint8List.fromList([
        0x00,
        0xA4,
        0x04,
        0x00,
        0x0E,
        0x32,
        0x50,
        0x41,
        0x59,
        0x2E,
        0x53,
        0x59,
        0x53,
        0x2E,
        0x44,
        0x44,
        0x46,
        0x30,
        0x31,
        0x00,
      ]),
    );

    // Collect AIDs from PPSE, then append known fallbacks (deduplicated)
    final aidsToTry = <List<int>>[];
    if (_swOk(ppseResp)) {
      aidsToTry.addAll(
        EmvTlvParser.findAllTlv(ppseResp.sublist(0, ppseResp.length - 2), 0x4F),
      );
    }
    for (final known in _knownAids) {
      if (!aidsToTry
          .any((a) => EmvTlvParser.hex(a) == EmvTlvParser.hex(known))) {
        aidsToTry.add(known);
      }
    }

    // 2. Try each AID until PAN is found
    for (final aidBytes in aidsToTry) {
      final card = await _tryAid(isoDep, aidBytes);
      if (card != null) return card;
    }

    return null;
  }

  static Future<EmvCard?> _tryAid(
      IsoDepAndroid isoDep, List<int> aidBytes) async {
    // SELECT AID
    Uint8List resp;
    try {
      resp = await isoDep.transceive(
        Uint8List.fromList([
          0x00,
          0xA4,
          0x04,
          0x00,
          aidBytes.length,
          ...aidBytes,
          0x00,
        ]),
      );
    } catch (_) {
      return null;
    }
    if (!_swOk(resp)) return null;

    // GET PROCESSING OPTIONS — try TTQ 0x27 first, then 0x36 (AmEx / RuPay)
    final selectAidData = resp.sublist(0, resp.length - 2);
    final gpoData = _buildGpoData(selectAidData);
    final gpoCmd = Uint8List.fromList([
      0x80,
      0xA8,
      0x00,
      0x00,
      gpoData.length,
      ...gpoData,
      0x00,
    ]);

    List<AflEntry>? aflEntries;
    for (final ttq in [null, 0x36]) {
      final cmd = ttq == null ? gpoCmd : _patchTtq(gpoCmd, ttq);
      try {
        final gpoResp = await isoDep.transceive(cmd);
        if (_swOk(gpoResp)) {
          aflEntries = EmvTlvParser.parseAfl(gpoResp);
          if (aflEntries != null) break;
        }
      } catch (_) {}
    }

    // Build record list: AFL-guided or brute-force fallback
    final toRead = <(int, int)>[];
    if (aflEntries != null && aflEntries.isNotEmpty) {
      for (final e in aflEntries) {
        for (int r = e.first; r <= e.last; r++) {
          toRead.add((e.sfi, r));
        }
      }
    } else {
      for (int sfi = 1; sfi <= 10; sfi++) {
        for (int rec = 1; rec <= 10; rec++) {
          toRead.add((sfi, rec));
        }
      }
    }

    // READ RECORDs
    String? pan;
    String? expiry;

    for (final (sfi, rec) in toRead) {
      if (pan != null && expiry != null) break;
      Uint8List recResp;
      try {
        recResp = await isoDep.transceive(
          Uint8List.fromList([0x00, 0xB2, rec, (sfi << 3) | 4, 0x00]),
        );
      } on PlatformException catch (e) {
        if (e.message?.contains('out of date') == true ||
            e.message?.contains('SecurityException') == true) {
          break; // card moved — stop trying this AID
        }
        continue;
      } catch (_) {
        continue;
      }
      if (!_swOk(recResp)) continue;

      final recData = recResp.sublist(0, recResp.length - 2);

      // Tag 5A — PAN
      if (pan == null) {
        final panBytes = EmvTlvParser.findTlv(recData, 0x5A);
        if (panBytes != null) {
          pan = EmvTlvParser.hex(panBytes).replaceAll('F', '');
        }
      }
      // Tag 57 / 9F6B — Track 2 Equivalent Data
      if (pan == null) {
        final t2 = EmvTlvParser.findTlv(recData, 0x57) ??
            EmvTlvParser.findTlv(recData, 0x9F6B);
        if (t2 != null) {
          final t2hex = EmvTlvParser.hex(t2).toLowerCase();
          final sep = t2hex.indexOf('d');
          if (sep > 0) pan = t2hex.substring(0, sep).toUpperCase();
        }
      }
      // Tag 5F24 — Expiry (BCD: YYMMDD) — store as YYMM
      if (expiry == null) {
        final expBytes = EmvTlvParser.findTlv(recData, 0x5F24);
        if (expBytes != null && expBytes.length >= 3) {
          expiry = EmvTlvParser.hex(expBytes).substring(0, 4); // YYMM
        }
      }
    }

    if (pan == null) return null;
    return EmvCard(cardNumber: pan, expiryDate: expiry ?? '');
  }

  /// Builds a GET PROCESSING OPTIONS command payload by parsing PDOL (tag 9F38)
  /// and filling each entry with sensible defaults for Visa / MC / Diners / AmEx / RuPay.
  static Uint8List _buildGpoData(List<int> selectAidResp) {
    final pdol = EmvTlvParser.findTlv(selectAidResp, 0x9F38);
    if (pdol == null || pdol.isEmpty) {
      return Uint8List.fromList([0x83, 0x00]); // empty PDOL
    }

    const tagDefaults = <int, List<int>>{
      0x9F66: [0x27, 0x00, 0x00, 0x00], // TTQ — contactless terminal
      0x9F6E: [0xD8, 0x00, 0x00, 0x00], // Form Factor Indicator (AmEx)
      0x9F02: [0x00, 0x00, 0x00, 0x00, 0x01, 0x00], // Amount: 1.00
      0x9F03: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00], // Other amount
      0x9F1A: [0x03, 0x56], // Terminal country: India (356)
      0x5F2A: [0x03, 0x56], // Currency: INR (356)
      0x9A: [0x25, 0x03, 0x25], // Date: 2025-03-25 (BCD)
      0x9C: [0x00], // Transaction type: purchase
      0x9F37: [0x12, 0x34, 0x56, 0x78], // Unpredictable number
      0x9F35: [0x22], // Terminal type
      0x95: [0x00, 0x00, 0x00, 0x00, 0x00], // TVR
      0x9F34: [0x1F, 0x00, 0x02], // CVM results
      0x9F45: [0x00, 0x00], // Data auth code
      0x9F4C: [
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00
      ], // ICC dyn number
    };

    final data = <int>[];
    int i = 0;
    while (i < pdol.length) {
      int tag = pdol[i] & 0xFF;
      i++;
      if ((tag & 0x1F) == 0x1F && i < pdol.length) {
        tag = (tag << 8) | (pdol[i++] & 0xFF);
      }
      if (i >= pdol.length) break;
      final len = pdol[i++] & 0xFF;

      final defaultVal = tagDefaults[tag];
      if (defaultVal != null && defaultVal.length == len) {
        data.addAll(defaultVal);
      } else {
        data.addAll(List.filled(len, 0x00));
      }
    }

    return Uint8List.fromList([0x83, data.length, ...data]);
  }

  static Uint8List _patchTtq(Uint8List gpoCmd, int newFirstByte) {
    final patched = Uint8List.fromList(gpoCmd);
    for (int i = 0; i < patched.length - 3; i++) {
      if (patched[i] == 0x27 &&
          patched[i + 1] == 0x00 &&
          patched[i + 2] == 0x00 &&
          patched[i + 3] == 0x00) {
        patched[i] = newFirstByte;
        break;
      }
    }
    return patched;
  }

  static bool _swOk(Uint8List r) =>
      r.length >= 2 && r[r.length - 2] == 0x90 && r[r.length - 1] == 0x00;

  static const _knownAids = [
    [0xA0, 0x00, 0x00, 0x00, 0x03, 0x10, 0x10], // Visa payWave
    [0xA0, 0x00, 0x00, 0x00, 0x04, 0x10, 0x10], // Mastercard PayPass
    [0xA0, 0x00, 0x00, 0x05, 0x24, 0x10, 0x10], // RuPay
    [0xA0, 0x00, 0x00, 0x00, 0x25, 0x01, 0x08, 0x01], // AmEx Expresspay
    [0xA0, 0x00, 0x00, 0x01, 0x52, 0x30, 0x10], // Diners / Discover
    [0xA0, 0x00, 0x00, 0x03, 0x33, 0x01, 0x01, 0x01], // UnionPay
  ];
}
