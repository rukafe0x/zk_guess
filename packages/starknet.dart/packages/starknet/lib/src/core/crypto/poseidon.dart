import 'model/poseidon_params.dart';

List<BigInt> _hadesRound({
  required List<BigInt> values,
  required int roundIdx,
  required bool isFullRound,
  required PoseidonParams params,
}) {
  final nbElements = values.length;
  final fieldPrime = params.fieldPrime;

  // add round key
  var vals = <BigInt>[];
  for (var idx = 0; idx < nbElements; idx++) {
    final value = (values[idx] + params.roundKeys[roundIdx][idx]) % fieldPrime;
    vals.add(value);
  }

  // subwords
  if (isFullRound) {
    vals = vals.map((e) => e.pow(nbElements) % fieldPrime).toList();
  } else {
    final tmp = vals[vals.length - 1];
    vals[vals.length - 1] = tmp.pow(nbElements) % fieldPrime;
  }

  // mix layer
  final results = <BigInt>[];
  for (var idx = 0; idx < params.mds.length; idx++) {
    var result = BigInt.zero;
    for (var j = 0; j < nbElements; j++) {
      result += vals[j] * params.mds[idx][j];
    }
    results.add(result % fieldPrime);
  }
  return results;
}

List<BigInt> _hadesPermutation({
  required List<BigInt> values,
  required PoseidonParams params,
}) {
  var vals = <BigInt>[...values];

  final fullRounds = params.fullRounds.toInt();
  final partialRounds = params.partialRounds.toInt();

  var roundIdx = 0;

  // apply half of full rounds
  for (var idx = 0; idx < fullRounds / 2; idx++) {
    vals = _hadesRound(
      values: vals,
      roundIdx: roundIdx,
      isFullRound: true,
      params: params,
    );
    roundIdx += 1;
  }

  // apply partial rounds
  for (var idx = 0; idx < partialRounds; idx++) {
    vals = _hadesRound(
      values: vals,
      roundIdx: roundIdx,
      isFullRound: false,
      params: params,
    );
    roundIdx += 1;
  }

  // apply half of full rounds
  for (var idx = 0; idx < fullRounds / 2; idx++) {
    vals = _hadesRound(
      values: vals,
      roundIdx: roundIdx,
      isFullRound: true,
      params: params,
    );
    roundIdx += 1;
  }
  return vals;
}

class _Poseidon {
  final PoseidonParams params;

  _Poseidon(this.params);

  BigInt hash(BigInt x, BigInt y) =>
      _hadesPermutation(values: [x, y, BigInt.two], params: params)[0];

  BigInt hashSingle(BigInt x) => _hadesPermutation(
        values: [x, BigInt.zero, BigInt.one],
        params: params,
      )[0];

  BigInt hashMany(List<BigInt> values) {
    final r = params.rate.toInt();
    final c = params.capacity.toInt();
    final m = r + c;

    final vals = <BigInt>[...values];
    // pads input
    vals.add(BigInt.one);
    for (var idx = 0; idx < (-vals.length % r); idx++) {
      vals.add(BigInt.zero);
    }

    // Why not 'r' here ?
    var state = List<BigInt>.generate(m, (index) => BigInt.zero);

    var idx = 0;
    while (idx < vals.length) {
      final tmp = <BigInt>[];
      for (var i = 0; i < r; i++) {
        tmp.add(state[i] + vals[idx + i]);
      }
      tmp.add(state[state.length - 1]);
      state = _hadesPermutation(values: tmp, params: params);
      idx += r;
    }
    // we don't have any remaining since vals.length % r == 0
    return state[0];
  }
}

final poseidonHasher = _Poseidon(poseidonParams);
