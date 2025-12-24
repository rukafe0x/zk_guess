/// Declare given compiled contracts on devnet
///
/// ```shell
/// ```
library;

import 'package:starknet/starknet.dart';

void main(List<String> args) async {
  final account = account0;
  final sierraPath = args[0];
  final compiledPath = args[1];
  final sierraContract = await CompiledContract.fromPath(sierraPath);
  final compiledContract = await CASMCompiledContract.fromPath(compiledPath);

  var sierraClassHash = Felt(sierraContract.classHash());
  final compiledClassHash = compiledContract.classHash();

  print(
    '$sierraPath : ${sierraClassHash.toHexString()}',
  );
  print(
    '$compiledPath: ${Felt(compiledClassHash).toHexString()}',
  );

  var txHash = Felt.zero;
  final declareTx = await account.declare(
    compiledContract: sierraContract,
    compiledClassHash: compiledClassHash,
  );
  declareTx.when(
    result: (result) {
      sierraClassHash = result.classHash;
      txHash = result.transactionHash;
      print(
        'Contract ClassHash: ${sierraClassHash.toHexString()} (${txHash.toHexString()})',
      );
    },
    error: (error) {
      throw Exception(
        'Failed to declare contract: ${error.code}: ${error.message}',
      );
    },
  );
  final txStatus = await waitForAcceptance(
    transactionHash: txHash.toHexString(),
    provider: account.provider,
  );
  if (!txStatus) {
    final tx = await account.provider.getTransactionByHash(txHash);
    print('Contract declare transaction failed');
    prettyPrintJson(tx.toJson());
    throw Exception('Declare transaction failed');
  } else {
    final txReceipt = await account.provider.getTransactionReceipt(txHash);
    print('Contract declare transaction OK!');
    prettyPrintJson(txReceipt.toJson());
  }
}
