package com.example.mopro_flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

import uniffi.mopro.*

import io.flutter.plugin.common.StandardMethodCodec

class FlutterG1(x: String, y: String, z: String) {
    val x = x
    val y = y
    val z = z
}

class FlutterG2(x: List<String>, y: List<String>, z: List<String>) {
    val x = x
    val y = y
    val z = z
}

class FlutterCircomProof(a: FlutterG1, b: FlutterG2, c: FlutterG1, protocol: String, curve: String) {
    val a = a
    val b = b
    val c = c
    val protocol = protocol
    val curve = curve
}

class FlutterCircomProofResult(proof: FlutterCircomProof, inputs: List<String>) {
    val proof = proof
    val inputs = inputs
}

fun convertCircomProof(res: CircomProofResult): Map<String, Any> {
    val g1a = FlutterG1(res.proof.a.x, res.proof.a.y, res.proof.a.z)
    val g2b = FlutterG2(res.proof.b.x, res.proof.b.y, res.proof.b.z)
    val g1c = FlutterG1(res.proof.c.x, res.proof.c.y, res.proof.c.z)
    val circomProof = FlutterCircomProof(g1a, g2b, g1c, res.proof.protocol, res.proof.curve)
    val circomProofResult = FlutterCircomProofResult(circomProof, res.inputs)
    // Convert to Map before sending
    val resultMap = mapOf(
        "proof" to mapOf(
            "a" to mapOf(
                "x" to circomProofResult.proof.a.x,
                "y" to circomProofResult.proof.a.y,
                "z" to circomProofResult.proof.a.z
            ),
            "b" to mapOf(
                "x" to circomProofResult.proof.b.x,
                "y" to circomProofResult.proof.b.y,
                "z" to circomProofResult.proof.b.z
            ),
            "c" to mapOf(
                "x" to circomProofResult.proof.c.x,
                "y" to circomProofResult.proof.c.y,
                "z" to circomProofResult.proof.c.z
            ),
            "protocol" to circomProofResult.proof.protocol,
            "curve" to circomProofResult.proof.curve
        ),
        "inputs" to circomProofResult.inputs
    )
    return resultMap
}
fun convertCircomProofResult(proofResult: Map<String, Any>): CircomProofResult {
    val proofMap = proofResult["proof"] as Map<String, Any>
    val aMap = proofMap["a"] as Map<String, Any>
    val g1a = G1(
        aMap["x"] as String,
        aMap["y"] as String,
        aMap["z"] as String
    )
    val bMap = proofMap["b"] as Map<String, Any>
    val g2b = G2(
        bMap["x"] as List<String>,
        bMap["y"] as List<String>,
        bMap["z"] as List<String>
    )
    val cMap = proofMap["c"] as Map<String, Any>
    val g1c = G1(
        cMap["x"] as String,
        cMap["y"] as String,
        cMap["z"] as String
    )
    val circomProof = CircomProof(
        g1a,
        g2b,
        g1c,
        proofMap["protocol"] as String,
        proofMap["curve"] as String
    )
    val circomProofResult = CircomProofResult(circomProof, proofResult["inputs"] as List<String>)
    return circomProofResult
}

/** MoproFlutterPlugin */
class MoproFlutterPlugin : FlutterPlugin, MethodCallHandler {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "mopro_flutter",
            StandardMethodCodec.INSTANCE
        )
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "generateCircomProof") {
            val zkeyPath = call.argument<String>("zkeyPath") ?: return result.error(
                "ARGUMENT_ERROR",
                "Missing zkeyPath",
                null
            )

            val inputs =
                call.argument<String>("circuitInputs") ?: return result.error(
                    "ARGUMENT_ERROR",
                    "Missing inputs",
                    null
                )

            val proofLibIndex = call.argument<Int>("proofLib") ?: return result.error(
                "ARGUMENT_ERROR",
                "Missing proofLib",
                null
            )

            val proofLib = if (proofLibIndex == 0) ProofLib.ARKWORKS else ProofLib.RAPIDSNARK

            val res = generateCircomProof(zkeyPath, inputs, proofLib)
            val resultMap = convertCircomProof(res)


            result.success(resultMap)
        } else if (call.method == "verifyCircomProof") {
            val zkeyPath = call.argument<String>("zkeyPath") ?: return result.error(
                "ARGUMENT_ERROR",
                "Missing zkeyPath",
                null
            )

            val proof = call.argument<Map<String, Any>>("proofResult") ?: return result.error(
                "ARGUMENT_ERROR",
                "Missing proof",
                null
            )

            val proofLibIndex = call.argument<Int>("proofLib") ?: return result.error(
                "ARGUMENT_ERROR",
                "Missing proofLib",
                null
            )

            val proofLib = if (proofLibIndex == 0) ProofLib.ARKWORKS else ProofLib.RAPIDSNARK

            val circomProofResult = convertCircomProofResult(proof)
            val res = verifyCircomProof(zkeyPath, circomProofResult, proofLib)
            result.success(res)

        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}