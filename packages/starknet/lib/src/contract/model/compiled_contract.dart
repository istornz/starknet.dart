import 'dart:convert';
import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:starknet/starknet.dart';

part 'compiled_contract.freezed.dart';
part 'compiled_contract.g.dart';

@freezed
class CompiledContract with _$CompiledContract {
  const CompiledContract._(); // To be able to define custome compress() method

  const factory CompiledContract({
    required Map<String, Object?> program,
    required EntryPointsByType entryPointsByType,
    List<ContractAbiEntry>? abi,
  }) = _CompiledContract;

  factory CompiledContract.fromJson(Map<String, Object?> json) =>
      _$CompiledContractFromJson(json);

  ContractClass compress() {
    final new_program = Map.of(program);
    final program_json = CompiledContractJsonEncoder().convert(new_program);
    return ContractClass(
      program: base64.encode(gzip.encode(utf8.encode(program_json))),
      entryPointsByType: entryPointsByType,
      abi: abi,
    );
  }

  /// Return program encoded as Python json.dumps
  String encode() {
    final new_program = Map.of(program);
    new_program.remove("attributes");
    final encoded =
        CompiledContractJsonEncoder(filterRuntimeType: false).convert({
      "abi": abi,
      "program": new_program,
    });
    return encoded;
  }

  /// Compute hashes for externals, l1 handlers and constructors
  /// https://docs.starknet.io/documentation/architecture_and_concepts/Contracts/contract-hash/
  EntryPointsHashes entrypointsHashes() {
    List<BigInt> buffer = [];
    for (var entrypoint in entryPointsByType.external) {
      buffer.add(entrypoint.selector.toBigInt());
      buffer.add(BigInt.parse(entrypoint.offset));
    }
    final externals = computeHashOnElements(buffer);

    buffer.clear();
    for (var entrypoint in entryPointsByType.l1Handler) {
      buffer.add(entrypoint.selector.toBigInt());
      buffer.add(BigInt.parse(entrypoint.offset));
    }
    final l1handlers = computeHashOnElements(buffer);
    buffer.clear();

    for (var entrypoint in entryPointsByType.constructor) {
      buffer.add(entrypoint.selector.toBigInt());
      buffer.add(BigInt.parse(entrypoint.offset));
    }
    final constructors = computeHashOnElements(buffer);
    return EntryPointsHashes(externals, l1handlers, constructors);
  }

  /// Compute hash for builtins
  /// https://docs.starknet.io/documentation/architecture_and_concepts/Contracts/contract-hash/
  BigInt builtinsHash() {
    return computeHashOnElements((program["builtins"] as List)
        .map((e) => Felt.fromString(e).toBigInt())
        .toList());
  }

  /// Compute program hash
  /// https://docs.starknet.io/documentation/architecture_and_concepts/Contracts/contract-hash/
  BigInt programHash() {
    final encoded = encode();
    return starknetKeccak(ascii.encode(encoded)).toBigInt();
  }

  /// Compute bytecode hash
  /// https://docs.starknet.io/documentation/architecture_and_concepts/Contracts/contract-hash/
  BigInt byteCodeHash() {
    return computeHashOnElements((program["data"] as List)
        .map((e) => Felt.fromHexString(e).toBigInt())
        .toList());
  }

  /// Compute contract class hash
  /// https://docs.starknet.io/documentation/architecture_and_concepts/Contracts/contract-hash/
  BigInt classHash() {
    List<BigInt> elements = [];
    elements.add(BigInt.from(0)); // FIXME: API VERSION
    final hashes = entrypointsHashes();
    elements.add(hashes.externals);
    elements.add(hashes.l1handlers);
    elements.add(hashes.constructors);
    elements.add(builtinsHash());
    elements.add(programHash());
    elements.add(byteCodeHash());
    final res = computeHashOnElements(elements);
    return res;
  }
}

class EntryPointsHashes {
  final BigInt externals;
  final BigInt l1handlers;
  final BigInt constructors;

  EntryPointsHashes(this.externals, this.l1handlers, this.constructors);
}

String compressProgram(Map<String, Object?> program) {
  return base64.encode(gzip.encode(utf8.encode(jsonEncode(program))));
}

/// JSON encoder to mimic Python json dumps
class CompiledContractJsonEncoder extends JsonEncoder {
  final bool filterRuntimeType;

  CompiledContractJsonEncoder({this.filterRuntimeType = true});

  @override
  String convert(Object? object) =>
      _JsonStringStringifier.stringify(object, _contractJsonCleanup, indent);

  Object? _contractJsonCleanup(
    dynamic object,
  ) {
    // freezed/json serializable add 'runtimeType'
    if (filterRuntimeType) {
      if (object is ContractAbiEntry) {
        var res = object.toJson();
        res.remove("runtimeType");
        return res;
      }
    }
    return object.toJson();
  }
}

// 2023-02-03: since these symbols is not exported by dart sdk,
// I have to duplicate the code here
// ignore_for_file: constant_identifier_names
// ignore_for_file: use_function_type_syntax_for_parameters
// ignore_for_file: no_leading_underscores_for_local_identifiers
// ignore_for_file: annotate_overrides

// Implementation of encoder/stringifier.
dynamic _defaultToEncodable(dynamic object) => object.toJson();

abstract class _JsonStringifier {
  // Character code constants.
  static const int backspace = 0x08;
  static const int tab = 0x09;
  static const int newline = 0x0a;
  static const int carriageReturn = 0x0d;
  static const int formFeed = 0x0c;
  static const int quote = 0x22;
  static const int char_0 = 0x30;
  static const int backslash = 0x5c;
  static const int char_b = 0x62;
  static const int char_d = 0x64;
  static const int char_f = 0x66;
  static const int char_n = 0x6e;
  static const int char_r = 0x72;
  static const int char_t = 0x74;
  static const int char_u = 0x75;
  static const int surrogateMin = 0xd800;
  static const int surrogateMask = 0xfc00;
  static const int surrogateLead = 0xd800;
  static const int surrogateTrail = 0xdc00;

  /// List of objects currently being traversed. Used to detect cycles.
  final List _seen = [];

  /// Function called for each un-encodable object encountered.
  final Function(dynamic) _toEncodable;

  _JsonStringifier(dynamic toEncodable(dynamic o)?)
      : _toEncodable = toEncodable ?? _defaultToEncodable;

  String? get _partialResult;

  /// Append a string to the JSON output.
  void writeString(String characters);

  /// Append part of a string to the JSON output.
  void writeStringSlice(String characters, int start, int end);

  /// Append a single character, given by its code point, to the JSON output.
  void writeCharCode(int charCode);

  /// Write a number to the JSON output.
  void writeNumber(num number);

  // ('0' + x) or ('a' + x - 10)
  static int hexDigit(int x) => x < 10 ? 48 + x : 87 + x;

  /// Write, and suitably escape, a string's content as a JSON string literal.
  void writeStringContent(String s) {
    var offset = 0;
    final length = s.length;
    for (var i = 0; i < length; i++) {
      var charCode = s.codeUnitAt(i);
      if (charCode > backslash) {
        if (charCode >= surrogateMin) {
          // Possible surrogate. Check if it is unpaired.
          if (((charCode & surrogateMask) == surrogateLead &&
                  !(i + 1 < length &&
                      (s.codeUnitAt(i + 1) & surrogateMask) ==
                          surrogateTrail)) ||
              ((charCode & surrogateMask) == surrogateTrail &&
                  !(i - 1 >= 0 &&
                      (s.codeUnitAt(i - 1) & surrogateMask) ==
                          surrogateLead))) {
            // Lone surrogate.
            if (i > offset) writeStringSlice(s, offset, i);
            offset = i + 1;
            writeCharCode(backslash);
            writeCharCode(char_u);
            writeCharCode(char_d);
            writeCharCode(hexDigit((charCode >> 8) & 0xf));
            writeCharCode(hexDigit((charCode >> 4) & 0xf));
            writeCharCode(hexDigit(charCode & 0xf));
          }
        }
        continue;
      }
      if (charCode < 32) {
        if (i > offset) writeStringSlice(s, offset, i);
        offset = i + 1;
        writeCharCode(backslash);
        switch (charCode) {
          case backspace:
            writeCharCode(char_b);
            break;
          case tab:
            writeCharCode(char_t);
            break;
          case newline:
            writeCharCode(char_n);
            break;
          case formFeed:
            writeCharCode(char_f);
            break;
          case carriageReturn:
            writeCharCode(char_r);
            break;
          default:
            writeCharCode(char_u);
            writeCharCode(char_0);
            writeCharCode(char_0);
            writeCharCode(hexDigit((charCode >> 4) & 0xf));
            writeCharCode(hexDigit(charCode & 0xf));
            break;
        }
      } else if (charCode == quote || charCode == backslash) {
        if (i > offset) writeStringSlice(s, offset, i);
        offset = i + 1;
        writeCharCode(backslash);
        writeCharCode(charCode);
      }
    }
    if (offset == 0) {
      writeString(s);
    } else if (offset < length) {
      writeStringSlice(s, offset, length);
    }
  }

  /// Check if an encountered object is already being traversed.
  ///
  /// Records the object if it isn't already seen. Should have a matching call to
  /// [_removeSeen] when the object is no longer being traversed.
  void _checkCycle(Object? object) {
    for (var i = 0; i < _seen.length; i++) {
      if (identical(object, _seen[i])) {
        throw JsonCyclicError(object);
      }
    }
    _seen.add(object);
  }

  /// Remove [object] from the list of currently traversed objects.
  ///
  /// Should be called in the opposite order of the matching [_checkCycle]
  /// calls.
  void _removeSeen(Object? object) {
    assert(_seen.isNotEmpty);
    assert(identical(_seen.last, object));
    _seen.removeLast();
  }

  /// Write an object.
  ///
  /// If [object] isn't directly encodable, the [_toEncodable] function gets one
  /// chance to return a replacement which is encodable.
  void writeObject(Object? object) {
    // Tries stringifying object directly. If it's not a simple value, List or
    // Map, call toJson() to get a custom representation and try serializing
    // that.
    if (writeJsonValue(object)) return;
    _checkCycle(object);
    try {
      var customJson = _toEncodable(object);
      if (!writeJsonValue(customJson)) {
        throw JsonUnsupportedObjectError(object, partialResult: _partialResult);
      }
      _removeSeen(object);
    } catch (e) {
      throw JsonUnsupportedObjectError(object,
          cause: e, partialResult: _partialResult);
    }
  }

  /// Serialize a [num], [String], [bool], [Null], [List] or [Map] value.
  ///
  /// Returns true if the value is one of these types, and false if not.
  /// If a value is both a [List] and a [Map], it's serialized as a [List].
  bool writeJsonValue(Object? object) {
    if (object is num) {
      if (!object.isFinite) return false;
      writeNumber(object);
      return true;
    } else if (identical(object, true)) {
      writeString('true');
      return true;
    } else if (identical(object, false)) {
      writeString('false');
      return true;
    } else if (object == null) {
      writeString('null');
      return true;
    } else if (object is String) {
      writeString('"');
      writeStringContent(object);
      writeString('"');
      return true;
    } else if (object is List) {
      _checkCycle(object);
      writeList(object);
      _removeSeen(object);
      return true;
    } else if (object is Map) {
      _checkCycle(object);
      // writeMap can fail if keys are not all strings.
      var success = writeMap(object);
      _removeSeen(object);
      return success;
    } else if (object is BigInt) {
      // add BigInt since I'm using them as a workaround
      // for JSON parsing using num (64 bits) to store number
      writeStringContent(object.toString());
      return true;
    } else {
      return false;
    }
  }

  /// Serialize a [List].
  void writeList(List<Object?> list) {
    writeString('[');
    if (list.isNotEmpty) {
      writeObject(list[0]);
      for (var i = 1; i < list.length; i++) {
        writeString(', '); // add a space as in python json dumps
        writeObject(list[i]);
      }
    }
    writeString(']');
  }

  /// Serialize a [Map].
  bool writeMap(Map<Object?, Object?> map) {
    if (map.isEmpty) {
      writeString("{}");
      return true;
    }
    var keyValueList = List<Object?>.filled(map.length * 2, null);
    var i = 0;
    var allStringKeys = true;
    Map.fromEntries(map.entries.toList()
          ..sort((e1, e2) =>
              (e1.key as String).naturalCompareTo(e2.key as String)))
        .forEach((key, value) {
      if (key is! String) {
        allStringKeys = false;
      }
      keyValueList[i++] = key;
      keyValueList[i++] = value;
    });
    if (!allStringKeys) return false;
    writeString('{');
    var separator = '"';
    for (var i = 0; i < keyValueList.length; i += 2) {
      writeString(separator);
      separator = ', "'; // add a space as in python json dumps
      writeStringContent(keyValueList[i] as String);
      writeString('": '); // add a space as in python json dumps
      writeObject(keyValueList[i + 1]);
    }
    writeString('}');
    return true;
  }
}

/// A specialization of [_JsonStringifier] that writes its JSON to a string.
class _JsonStringStringifier extends _JsonStringifier {
  final StringSink _sink;

  _JsonStringStringifier(
      this._sink, dynamic Function(dynamic object)? _toEncodable)
      : super(_toEncodable);

  /// Convert object to a string.
  ///
  /// The [toEncodable] function is used to convert non-encodable objects
  /// to encodable ones.
  ///
  /// If [indent] is not `null`, the resulting JSON will be "pretty-printed"
  /// with newlines and indentation. The `indent` string is added as indentation
  /// for each indentation level. It should only contain valid JSON whitespace
  /// characters (space, tab, carriage return or line feed).
  static String stringify(
      Object? object, dynamic toEncodable(dynamic object)?, String? indent) {
    var output = StringBuffer();
    printOn(object, output, toEncodable, indent);
    return output.toString();
  }

  /// Convert object to a string, and write the result to the [output] sink.
  ///
  /// The result is written piecemally to the sink.
  static void printOn(Object? object, StringSink output,
      dynamic toEncodable(dynamic o)?, String? indent) {
    _JsonStringifier stringifier;
    stringifier = _JsonStringStringifier(output, toEncodable);
    stringifier.writeObject(object);
  }

  String? get _partialResult => _sink is StringBuffer ? _sink.toString() : null;

  @override
  void writeNumber(num number) {
    _sink.write(number);
  }

  @override
  void writeString(String string) {
    _sink.write(string);
  }

  @override
  void writeStringSlice(String string, int start, int end) {
    _sink.write(string.substring(start, end));
  }

  @override
  void writeCharCode(int charCode) {
    _sink.writeCharCode(charCode);
  }
}

extension ContractCompare on String {
  int naturalCompareTo(String other) {
    // handle case where string is an integer (for hint)
    int? me = int.tryParse(this);
    int? you = int.tryParse(other);
    if (me != null && you != null) {
      if (me == you) {
        return 0;
      } else if (me > you) {
        return 1;
      } else {
        return -1;
      }
    }
    return compareTo(other);
  }
}
