/// Declare given compiled contracts on devnet
///
/// ```shell
/// ```
library;

import 'package:starknet/starknet.dart';

void main(List<String> args) async {
  final account = account0;
  for (final arg in args) {
    final contractPath = arg;
    final compiledContract =
        await DeprecatedCompiledContract.fromPath(contractPath);
    var classHash = Felt(compiledContract.classHash());

    print(
      '$contractPath : ${classHash.toHexString()}',
    );
    var txHash = Felt.zero;
    final declareTx = await account.declare(
      compiledContract: compiledContract,
      compiledClassHash: compiledContract.classHash(),
    );
    declareTx.when(
      result: (result) {
        classHash = result.classHash;
        txHash = result.transactionHash;
        print(
          'Contract ClassHash: ${classHash.toHexString()} (${txHash.toHexString()})',
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
}
