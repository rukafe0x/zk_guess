import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:starknet/starknet.dart';
import 'package:avnu_provider/avnu_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:math';
import 'main_screen.dart';
import 'services.dart';

class AccountSelectionScreen extends StatefulWidget {
  const AccountSelectionScreen({Key? key}) : super(key: key);

  @override
  _AccountSelectionScreenState createState() => _AccountSelectionScreenState();
}

class _AccountSelectionScreenState extends State<AccountSelectionScreen> {
  final _storage = const FlutterSecureStorage();
  List<Map<String, String>> _accounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Get all stored keys
      final allKeys = await _storage.readAll();

      // Filter and parse account data
      final accounts = <Map<String, String>>[];
      for (var key in allKeys.keys) {
        if (key.startsWith('account_')) {
          final accountData = jsonDecode(allKeys[key]!);
          accounts.add({
            'nickname': accountData['nickname'],
            'privateKey': accountData['privateKey'],
            'address': accountData['address'],
          });
        }
      }

      // Add hardcoded account 1
      // final account1 = {
      //   'nickname': dotenv.env['ACCOUNT1_NICKNAME'] ?? 'Admin',
      //   'privateKey': dotenv.env['ACCOUNT1_PRIVATE_KEY'] ?? '',
      //   'address': dotenv.env['ACCOUNT1_ADDRESS'] ?? '',
      // };
      // accounts.add(account1);

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading accounts: $e')));
    }
  }

  Future<void> _selectAccount(Map<String, String> account) async {
    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Do you want to use the account "${account['nickname']}"?'),
              const SizedBox(height: 16),
              Text(
                'Account Address: ${account['address']}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                '⚠️ Important:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const Text(
                '• Save your account address - you will need to charge it with STRK tokens to participate in challenges.',
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Ok'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      // Store selected account in secure storage
      await _storage.write(key: 'selected_account', value: jsonEncode(account));

      // Navigate to main screen with the selected account
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(
              accountAddress: account['address']!,
              accountNickname: account['nickname']!,
            ),
          ),
        );
      }
    }
  }

  AvnuProvider getAvnuProvider({BigInt? publicKey, String? apiKey}) {
    final env = dotenv.env;
    if (env['AVNU_RPC'] == null) {
      throw Exception('AVNU_RPC environment variable is not set');
    }

    return AvnuJsonRpcProvider(
      nodeUri: Uri.parse(env['AVNU_RPC']!),
      publicKey: publicKey,
      apiKey: apiKey,
    );
  }

  Future<void> _createSponsoredAccount() async {
    try {
      // Show dialog to get nickname
      final nickname = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          String tempNickname = '';
          return AlertDialog(
            title: const Text('Account Nickname'),
            content: TextField(
              decoration: const InputDecoration(
                hintText: 'Enter a nickname for your account',
                labelText: 'Nickname',
              ),
              onChanged: (value) {
                tempNickname = value;
              },
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: const Text('Create'),
                onPressed: () {
                  if (tempNickname.trim().isNotEmpty) {
                    Navigator.of(context).pop(tempNickname);
                  }
                },
              ),
            ],
          );
        },
      );

      if (nickname == null || nickname.trim().isEmpty) {
        return; // User cancelled or entered empty nickname
      }

      const apiKey = '04a163bf-65e0-4ff7-870d-64379f3d6c92';
      final publicKey = BigInt.parse(
        "0429c489be63b21c399353e03a9659cfc1650b24bae1e9ebdde0aef2b38deb44",
        radix: 16,
      );
      final avnuProvider = getAvnuProvider(
        publicKey: publicKey,
        apiKey: apiKey,
      );

      // generate a new private key (not cryptographically secure)
      // only for MVP purpose
      final randomValue = Random().nextInt(1 << 32);
      final ownerSigner = StarkSigner(privateKey: Felt.fromInt(randomValue));
      final classHash = Felt.fromHexString(
        '0x01a736d6ed154502257f02b1ccdf4d9d1089f80811cd6acad48e6b6a9d1f2003',
      );
      final calldata = [ownerSigner.publicKey, Felt.zero];
      final salt = ownerSigner.publicKey;
      final accountAddress = Contract.computeAddress(
        classHash: classHash,
        calldata: calldata,
        salt: salt,
      );

      final deploymentData = AvnuDeploymentData(
        classHash: classHash.toHexString(),
        salt: ownerSigner.publicKey.toHexString(),
        unique: Felt.zero.toHexString(),
        calldata: calldata.map((e) => e.toHexString()).toList(),
        sigdata: [],
      );
      final avnuDeploy = await avnuProvider.deployAccount(
        AvnuDeployAccountRequest(
          userAddress: accountAddress.toHexString(),
          deploymentData: deploymentData,
        ),
      );
      final result = avnuDeploy as AvnuDeployAccountResult;
      print('AVNU Transaction hash: ${result.transactionHash}');
      print('Account address: ${accountAddress.toHexString()}');

      // Create a new account entry
      final newAccount = {
        'nickname': nickname.trim(),
        'privateKey': ownerSigner.privateKey.toHexString(),
        'address': accountAddress.toHexString(),
      };

      // Store the new account
      await _storage.write(
        key: 'account_${_accounts.length}',
        value: jsonEncode(newAccount),
      );

      // Reload accounts
      await _loadAccounts();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account created: ${accountAddress.toHexString()}'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating account: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extrasensory Perception (ESP)\nSelect Account'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Remove all accounts',
            onPressed: () async {
              // Show confirmation dialog
              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Remove All Accounts'),
                    content: const Text(
                      'Are you sure you want to remove all accounts? This action cannot be undone.',
                    ),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: const Text('Remove All'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  );
                },
              );

              if (confirm == true) {
                try {
                  // Get all keys
                  final allKeys = await _storage.readAll();

                  // Delete each key
                  for (var key in allKeys.keys) {
                    await _storage.delete(key: key);
                  }

                  // Reload accounts
                  await _loadAccounts();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All accounts have been removed'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error removing accounts: $e')),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/pes.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _accounts.length < 1
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 24),
                    const Text(
                      'No accounts found',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _createSponsoredAccount,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Create New Account'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _accounts.length,
                      itemBuilder: (context, index) {
                        final account = _accounts[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ListTile(
                            title: Text(
                              'Press here to sign in: ${account['nickname'] ?? ''}',
                            ),
                            subtitle: Text(
                              'Address: ${account['address']?.substring(0, 10)}...',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () => _selectAccount(account),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
