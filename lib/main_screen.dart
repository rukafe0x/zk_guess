import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:starknet/starknet.dart';
import 'package:starknet_provider/starknet_provider.dart';
import 'package:poseidon/poseidon.dart';
import 'services.dart';
import 'package:mopro_flutter/mopro_flutter.dart';
import 'package:mopro_flutter/mopro_types.dart';

void main() {
  runApp(MainScreen(accountAddress: '', accountNickname: ''));
}

class MainScreen extends StatefulWidget {
  final String accountAddress;
  final String accountNickname;
  const MainScreen({
    super.key,
    required this.accountAddress,
    required this.accountNickname,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  CircomProofResult? _circomProofResult;
  bool? _circomValid;
  final _moproFlutterPlugin = MoproFlutter();
  bool isProving = false;
  Exception? _error;
  late TabController _tabController;

  // Controllers to handle user input
  final TextEditingController _controllerGameId =
      TextEditingController(); // Game ID
  final TextEditingController _controllerX =
      TextEditingController(); // Private: secret number
  final TextEditingController _controllerSalt =
      TextEditingController(); // Private: random salt
  final TextEditingController _controllerH =
      TextEditingController(); // Public: commitment
  final TextEditingController _controllerY =
      TextEditingController(); // Public: guess
  final TextEditingController _controllerMyGuess =
      TextEditingController(); // My guess of opponent's number
  final TextEditingController _controllerOut = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Choose a random game id between 9000000000000000000 and 10000000000000000000
    final gameid = Random().nextInt(4294967296).toString();
    final salt = Random().nextInt(4294967296).toString();

    _controllerGameId.text = gameid; // Game ID
    //_controllerX.text = "42"; // Secret number
    _controllerSalt.text = salt; // Random salt
    _controllerH.text =
        "13245343514578030741594369900290446682530842171781363792498777812991056803829"; // Commitment
    //_controllerY.text = "42"; // Guess
    //_controllerOut.text = "55";
    _tabController = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildCircomTab() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isProving) const CircularProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error.toString()),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerGameId,
              decoration: const InputDecoration(
                labelText: "Game ID",
                hintText: "For example, 1",
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerX,
              decoration: const InputDecoration(
                labelText: "Private input `x` (secret number)",
                hintText: "For example, 42",
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerSalt,
              enabled: false,
              decoration: const InputDecoration(
                labelText: "Private input `salt` (random salt)",
                hintText: "Auto-generated random salt",
                disabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerH,
              enabled: false,
              decoration: const InputDecoration(
                labelText: "Public input `h` (commitment)",
                hintText: "Calculated from secret number and salt",
                disabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerMyGuess,
              decoration: const InputDecoration(
                labelText: "My guess of opponent's number",
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerY,
              decoration: const InputDecoration(
                labelText: "Public input `y` (Opponent's guess)",
                hintText: "For example, 42",
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OutlinedButton(
              onPressed: () async {
                try {
                  // Approve 1 STRK as entry fee
                  final entryFee = Uint256.fromBigInt(
                    BigInt.parse("1000000000000000000"),
                  ); // 1 STRK
                  final txHash = await approveEntryFee(entryFee);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Entry fee approved successfully: $txHash"),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error approving entry fee: $e")),
                  );
                }
              },
              child: const Text("Approve Entry Fee (Bet 1 STRK)"),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OutlinedButton(
              onPressed: () async {
                if (_controllerGameId.text.isEmpty ||
                    _controllerX.text.isEmpty ||
                    _controllerSalt.text.isEmpty) {
                  return;
                }

                try {
                  // Convert inputs to BigInt
                  final gameId = BigInt.parse(_controllerGameId.text);
                  final x = BigInt.parse(_controllerX.text);
                  final salt = BigInt.parse(_controllerSalt.text);

                  // Calculate Poseidon hash using SNARK-compatible implementation
                  final hash = poseidon2([x, salt]);

                  // Update the commitment field
                  setState(() {
                    _controllerH.text = hash.toString();
                  });

                  print("Poseidon hash calculated: $hash");
                  // now invoke invokeRegisterCommitment from services.dart with game ID
                  final gameIdU256 = Uint256.fromBigInt(
                    BigInt.parse(gameId.toString()),
                  );
                  final hashU256 = Uint256.fromBigInt(
                    BigInt.parse(hash.toString()),
                  );
                  final txHash = await invokeRegisterCommitment(
                    gameIdU256,
                    hashU256,
                  );
                  // once done, display a snackbar with the message "Commitment registered successfully"
                  //and the txHash
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Commitment registered successfully: $txHash",
                      ),
                    ),
                  );
                } catch (e) {
                  print("Error calculating Poseidon hash: $e");
                  setState(() {
                    _error = Exception("Error calculating hash: $e");
                  });
                }
              },
              child: const Text(
                "Register your secret number in Starknet(commitment)",
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OutlinedButton(
              onPressed: () {
                // Dummy button - does nothing
                print("Send My Guess button pressed - dummy action");
                //display a snackbar with the message "My guess sent successfully"
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Sending my guess to the opponent thru contract events. (NOT IMPLEMENTED YET)",
                    ),
                  ),
                );
              },
              child: const Text("Send My Guess to the opponent."),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OutlinedButton(
              onPressed: () async {
                if (_controllerGameId.text.isEmpty ||
                    _controllerX.text.isEmpty ||
                    _controllerSalt.text.isEmpty ||
                    _controllerH.text.isEmpty ||
                    _controllerY.text.isEmpty ||
                    isProving) {
                  return;
                }
                setState(() {
                  _error = null;
                  isProving = true;
                });

                FocusManager.instance.primaryFocus?.unfocus();
                CircomProofResult? proofResult;
                try {
                  var inputs =
                      '{"x":["${_controllerX.text}"],"salt":["${_controllerSalt.text}"],"h":["${_controllerH.text}"],"y":["${_controllerY.text}"]}';
                  print("Starting proof generation...");
                  print(inputs);
                  proofResult = await _moproFlutterPlugin.generateCircomProof(
                    "assets/guess_0001.zkey",
                    inputs,
                    ProofLib.arkworks,
                  ); // DO NOT change the proofLib if you don't build for rapidsnark
                  print("Proof generation completed!");
                  // display a snackbar with the message "Proof generation completed!"
                  // concatenated with the proofResult as a json string with properties keys and values doublequoted
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Proof generation completed! Proof: ${proofResult?.proof ?? ""}",
                      ),
                    ),
                  );
                } on Exception catch (e) {
                  print("Error: $e");
                  proofResult = null;
                  setState(() {
                    _error = e;
                  });
                }

                if (!mounted) return;

                setState(() {
                  isProving = false;
                  _circomProofResult = proofResult;
                });
              },
              child: const Text("Generate Proof locally (hidden to the user)"),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OutlinedButton(
              onPressed: () async {
                if (_controllerX.text.isEmpty ||
                    _controllerSalt.text.isEmpty ||
                    _controllerH.text.isEmpty ||
                    _controllerY.text.isEmpty ||
                    isProving) {
                  return;
                }
                setState(() {
                  _error = null;
                  isProving = true;
                });

                FocusManager.instance.primaryFocus?.unfocus();
                bool? valid;
                try {
                  //var proofResult = _circomProofResult;
                  //create a var proofResult with _circomProofResult values
                  //but clone "inputs" field in  _circomProofResult as "public_inputs" in proofResult
                  var proofResult = _circomProofResult;
                  // Create a modified map for HTTP request with "public_inputs"
                  var httpPayload = proofResult!.toMap();
                  httpPayload['public_inputs'] = httpPayload['inputs'];
                  // Remove the original "inputs" field
                  httpPayload.remove('inputs');

                  // change input in the proof to check rejection
                  //proofResult!.inputs[0] = "6";
                  //before call verifyCircomProof, print the proofResult
                  //as a json string with properties keys and values doublequoted
                  print(jsonEncode(proofResult.toMap()));
                  // Before verification call localhost:8080 api sending the doublequoted proof as body
                  // and getting the response
                  var response = await http.post(
                    Uri.parse('http://10.0.2.2:8080'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(httpPayload),
                  );
                  print(response.body);

                  // now, importing and using starknet.dart package from: https://github.com/focustree/starknet.dart
                  // verify the proof calling the verify_groth16_proof_bn254 function in
                  // sepolia contract
                  final Felt contractAddress = Felt.fromHexString(
                    "0x03972115bee003c73565bf05aac494701a03840d06d264807fdedf4d8a87ba8e",
                  );
                  final provider = JsonRpcProvider(
                    nodeUri: Uri.parse(
                      'https://starknet-sepolia.public.blastapi.io',
                    ),
                  );
                  // convert response.body to list of felt but
                  // without the [ and ] at the beginning and the end
                  // and without the quotes
                  //but the first element in calldata must be the list elements count which must be calculated
                  final elementsCount = response.body
                      .substring(1, response.body.length - 1)
                      .split(",")
                      .length;
                  var calldata = [
                    Felt(BigInt.parse(elementsCount.toString())),
                    ...response.body
                        .substring(1, response.body.length - 1)
                        .split(",")
                        .map(
                          (felt) =>
                              Felt(BigInt.parse(felt.replaceAll("\"", ""))),
                        )
                        .toList(),
                  ];
                  // calldata[1] = Felt(
                  //   BigInt.parse(elementsCount.toString()),
                  // );
                  print("Calldata: $calldata");
                  // send the game id and proof result as calldata
                  final txHash = await invokeVerifyIntent(
                    Uint256.fromBigInt(BigInt.parse(_controllerGameId.text)),
                    calldata,
                  );
                  // once done, display a snackbar with the message "Proof verified successfully"
                  // and the txHash
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Proof verified successfully: $txHash"),
                    ),
                  );
                  valid = true;
                  //valid = result.when(
                  //  result: (result) => true,
                  //  error: (error) => false,
                  //);

                  // valid = await _moproFlutterPlugin.verifyCircomProof(
                  //   "assets/age_verification_0001.zkey",
                  //   proofResult!,
                  //   ProofLib.arkworks,
                  // ); // DO NOT change the proofLib if you don't build for rapidsnark
                } on Exception catch (e) {
                  print("Error: $e");
                  valid = false;
                  setState(() {
                    _error = e;
                  });
                } on TypeError catch (e) {
                  print("Error: $e");
                  valid = false;
                  setState(() {
                    _error = Exception(e.toString());
                  });
                }

                if (!mounted) return;

                setState(() {
                  isProving = false;
                  _circomValid = valid;
                });
              },
              child: const Text("Check Result (Verify Proof in blockchain)"),
            ),
          ),
          if (_circomProofResult != null)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  //child: Text('Proof is valid: ${_circomValid ?? false}'),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  //child: Text('Proof inputs: ${_circomProofResult?.inputs ?? ""}',
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  //child: Text('Proof: ${_circomProofResult?.proof ?? ""}'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZK Extrasensory Perception (ESP) Game'),
        actions: [
          if (widget.accountAddress.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy account address',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.accountAddress));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Account address copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: widget.accountAddress.isNotEmpty
                  ? 'Account: ${widget.accountAddress.substring(0, 6)}...${widget.accountAddress.substring(widget.accountAddress.length - 4)}'
                  : 'Circom',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCircomTab()],
      ),
    );
  }
}
