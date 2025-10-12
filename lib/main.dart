import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:starknet/starknet.dart';
import 'package:starknet_provider/starknet_provider.dart';
import 'package:poseidon/poseidon.dart';

import 'package:mopro_flutter/mopro_flutter.dart';
import 'package:mopro_flutter/mopro_types.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  CircomProofResult? _circomProofResult;
  bool? _circomValid;
  final _moproFlutterPlugin = MoproFlutter();
  bool isProving = false;
  Exception? _error;
  late TabController _tabController;

  // Controllers to handle user input
  final TextEditingController _controllerX =
      TextEditingController(); // Private: secret number
  final TextEditingController _controllerSalt =
      TextEditingController(); // Private: random salt
  final TextEditingController _controllerH =
      TextEditingController(); // Public: commitment
  final TextEditingController _controllerY =
      TextEditingController(); // Public: guess
  final TextEditingController _controllerOut = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Choose a random salt
    final salt = Random().nextInt(1000000).toString();
    _controllerX.text = "42"; // Secret number
    _controllerSalt.text = salt; // Random salt
    _controllerH.text =
        "13245343514578030741594369900290446682530842171781363792498777812991056803829"; // Commitment
    _controllerY.text = "42"; // Guess
    _controllerOut.text = "55";
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
              decoration: const InputDecoration(
                labelText: "Private input `salt` (random salt)",
                hintText: "For example, 12345",
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerH,
              decoration: const InputDecoration(
                labelText: "Public input `h` (commitment)",
                hintText: "Commitment hash value",
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextFormField(
              controller: _controllerY,
              decoration: const InputDecoration(
                labelText: "Public input `y` (guess)",
                hintText: "For example, 42",
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OutlinedButton(
              onPressed: () async {
                if (_controllerX.text.isEmpty || _controllerSalt.text.isEmpty) {
                  return;
                }

                try {
                  // Convert inputs to BigInt
                  final x = BigInt.parse(_controllerX.text);
                  final salt = BigInt.parse(_controllerSalt.text);

                  // Calculate Poseidon hash using SNARK-compatible implementation
                  final hash = poseidon2([x, salt]);

                  // Update the commitment field
                  setState(() {
                    _controllerH.text = hash.toString();
                  });

                  print("Poseidon hash calculated: $hash");
                } catch (e) {
                  print("Error calculating Poseidon hash: $e");
                  setState(() {
                    _error = Exception("Error calculating hash: $e");
                  });
                }
              },
              child: const Text("Calculate Poseidon Hash"),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                  child: const Text("Generate Proof"),
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
                      final result = await provider.call(
                        request: FunctionCall(
                          contractAddress: contractAddress,
                          entryPointSelector: getSelectorByName(
                            "verify_groth16_proof_bn254",
                          ),
                          // response.body has a [ and a ] at the beginning and the end
                          // remove them and then split by comma
                          calldata: calldata,
                        ),
                        blockId: BlockId.latest,
                      );

                      valid = result.when(
                        result: (result) => true,
                        error: (error) => false,
                      );

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
                  child: const Text("Verify Proof"),
                ),
              ),
            ],
          ),
          if (_circomProofResult != null)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Proof is valid: ${_circomValid ?? false}'),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Proof inputs: ${_circomProofResult?.inputs ?? ""}',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Proof: ${_circomProofResult?.proof ?? ""}'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('ZK Guessing Game'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Circom')],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [_buildCircomTab()],
        ),
      ),
    );
  }
}
