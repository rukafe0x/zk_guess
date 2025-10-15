// ignore_for_file: prefer_const_declarations, avoid_print

import 'package:starknet/starknet.dart';
import 'package:starknet_provider/starknet_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
//import 'package:starknet_sports_pool/utils/utils.dart';
//import '../models/game.dart';
//import '../models/tournament_template.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

final _storage = const FlutterSecureStorage();

Future<String> getSecretAccountAddress() async {
  final accountData = await _storage.read(key: 'selected_account');
  if (accountData == null) return '';
  final data = jsonDecode(accountData);
  return data['address'] ?? '';
}

Future<String> getSecretAccountPrivateKey() async {
  final accountData = await _storage.read(key: 'selected_account');
  if (accountData == null) return '';
  final data = jsonDecode(accountData);
  return data['privateKey'] ?? '';
}

Future<String?> getAccountNickname(String address) async {
  try {
    // Get all stored keys
    final allKeys = await _storage.readAll();

    // Search for the account with matching address
    for (var key in allKeys.keys) {
      if (key.startsWith('account_')) {
        final accountData = jsonDecode(allKeys[key]!);
        if (accountData['address'] == address) {
          return accountData['nickname'];
        }
      }
    }

    // Check if it's the hardcoded account 1
    final env = dotenv.env;
    if (env['ACCOUNT1_ADDRESS'] == address) {
      return env['ACCOUNT1_NICKNAME'] ?? 'Admin';
    }

    return null;
  } catch (e) {
    return null;
  }
}

final secretAccountAddress = getSecretAccountAddress();
final secretAccountPrivateKey = getSecretAccountPrivateKey();

final provider = JsonRpcProvider(
  nodeUri: Uri.parse(dotenv.env['STARKNET_NODE_URI'] ?? ''),
);
final contractAddress = dotenv.env['CONTRACT_ADDRESS'] ?? '';

Future<Account> getSignerAccount() async {
  final address = await getSecretAccountAddress();
  final privateKey = await getSecretAccountPrivateKey();
  return getAccount(
    accountAddress: Felt.fromHexString(address),
    privateKey: Felt.fromHexString(privateKey),
    nodeUri: Uri.parse(dotenv.env['STARKNET_NODE_URI'] ?? ''),
  );
}

// invoke zk_guess contract to register the commitment as
// specified in zk_guess.cairo
// invoke the contract with the hash as the calldata
Future<String> invokeRegisterCommitment(Uint256 gameId, Uint256 hash) async {
  final account = await getSignerAccount();
  final maxFee = await account.getEstimateMaxFeeForInvokeTx(
    functionCalls: [
      FunctionCall(
        contractAddress: Felt.fromHexString(contractAddress),
        entryPointSelector: getSelectorByName("register_commitment"),
        calldata: [gameId.low, gameId.high, hash.low, hash.high],
      ),
    ],
  );
  final response = await account.execute(
    functionCalls: [
      FunctionCall(
        contractAddress: Felt.fromHexString(contractAddress),
        entryPointSelector: getSelectorByName("register_commitment"),
        calldata: [gameId.low, gameId.high, hash.low, hash.high],
      ),
    ],
    incrementNonceIfNonceRelatedError: true,
    maxAttempts: 5,
    l1GasConsumed: maxFee.l1GasConsumed,
    l1GasPrice: maxFee.l1GasPrice,
    l2GasConsumed: maxFee.l2GasConsumed,
    l2GasPrice: maxFee.l2GasPrice,
    l1DataGasConsumed: maxFee.l1DataGasConsumed,
    l1DataGasPrice: maxFee.l1DataGasPrice,
  );
  final txHash = response.when(
    result: (result) => result.transaction_hash,
    error: (err) => throw Exception("Failed to invoke register commitment"),
  );
  print('Invoking register commitment TX : $txHash');
  await waitForAcceptance(transactionHash: txHash, provider: provider);
  return txHash;
}

// function to invoke verify_intent defined as:
// fn verify_intent(ref self: TContractState, game_id: u256, full_proof_with_hints: Span<felt252>);

Future<String> invokeVerifyIntent(
  Uint256 gameId,
  List<Felt> fullProofWithHints,
) async {
  final account = await getSignerAccount();
  final calldata = [
    gameId.low,
    gameId.high,
    ...fullProofWithHints.map((felt) => felt),
  ];
  print("Calldata: $calldata");
  final maxFee = await account.getEstimateMaxFeeForInvokeTx(
    functionCalls: [
      FunctionCall(
        contractAddress: Felt.fromHexString(contractAddress),
        entryPointSelector: getSelectorByName("verify_intent"),
        calldata: calldata,
      ),
    ],
  );
  final response = await account.execute(
    functionCalls: [
      FunctionCall(
        contractAddress: Felt.fromHexString(contractAddress),
        entryPointSelector: getSelectorByName("verify_intent"),
        calldata: [
          gameId.low,
          gameId.high,
          ...fullProofWithHints.map((felt) => felt),
        ],
      ),
    ],
    incrementNonceIfNonceRelatedError: true,
    maxAttempts: 5,
    l1GasConsumed: maxFee.l1GasConsumed,
    l1GasPrice: maxFee.l1GasPrice,
    l2GasConsumed: maxFee.l2GasConsumed,
    l2GasPrice: maxFee.l2GasPrice,
    l1DataGasConsumed: maxFee.l1DataGasConsumed,
    l1DataGasPrice: maxFee.l1DataGasPrice,
  );
  final txHash = response.when(
    result: (result) => result.transaction_hash,
    error: (err) => throw Exception("Failed to invoke verify intent"),
  );
  print('Invoking verify intent TX : $txHash');
  await waitForAcceptance(transactionHash: txHash, provider: provider);
  return txHash;
}

Future<String> approveEntryFee(Uint256 entryFee) async {
  final account = await getSignerAccount();
  final strkTokenAddress = dotenv.env['STRK_TOKEN_ADDRESS'] ?? '';
  final calldata = [
    Felt.fromHexString(contractAddress), // spender (contract address)
    entryFee.low, // amount low
    entryFee.high, // amount high
  ];
  // first estimate the max fee
  final maxFee = await account.getEstimateMaxFeeForInvokeTx(
    functionCalls: [
      FunctionCall(
        contractAddress: Felt.fromHexString(strkTokenAddress),
        entryPointSelector: getSelectorByName("approve"),
        calldata: calldata,
      ),
    ],
  );
  final response = await account.execute(
    functionCalls: [
      FunctionCall(
        contractAddress: Felt.fromHexString(strkTokenAddress),
        entryPointSelector: getSelectorByName("approve"),
        calldata: calldata,
      ),
    ],
    incrementNonceIfNonceRelatedError: true,
    maxAttempts: 5,
    l1GasConsumed: maxFee.l1GasConsumed,
    l1GasPrice: maxFee.l1GasPrice,
    l2GasConsumed: maxFee.l2GasConsumed,
    l2GasPrice: maxFee.l2GasPrice,
    l1DataGasConsumed: maxFee.l1DataGasConsumed,
    l1DataGasPrice: maxFee.l1DataGasPrice,
  );

  final txHash = response.when(
    result: (result) => result.transaction_hash,
    error: (err) => throw Exception("Failed to approve entry fee"),
  );

  await waitForAcceptance(transactionHash: txHash, provider: provider);

  print('Approving entry fee TX: $txHash');
  return txHash;
}
