library ansi_pixels.base64_zip;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';

final zipEncoder = new ZLibEncoder();
final zipDecoder = new ZLibDecoder();

List<int> _zipString(String v) => zipEncoder.encode(UTF8.encode(v));
String _unzipString(List<int> v) =>
    UTF8.decode(zipDecoder.decodeBytes(v), allowMalformed: true);

String zip(String s, {bool urlSafe: false}) => (s == null)
    ? null
    : CryptoUtils.bytesToBase64(_zipString(s), urlSafe: urlSafe);
String unzip(String s) =>
    (s == null) ? null : _unzipString(CryptoUtils.base64StringToBytes(s));
