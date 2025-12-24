use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};
use serde_json;
use num_bigint::BigUint;
use num_traits::Num; // Needed for from_str_radix
use std::sync::Once;

static INIT_LOGGER: Once = Once::new();
static INIT_PANIC: Once = Once::new();

fn init_logger() {
    INIT_LOGGER.call_once(|| {
        android_logger::init_once(
            android_logger::Config::default()
                .with_max_level(log::LevelFilter::Trace),
        );
    });
}

fn init_panic_hook() {
    INIT_PANIC.call_once(|| {
        std::panic::set_hook(Box::new(|info| {
            log::error!("[RUST PANIC] {}", info);
        }));
    });
}

use garaga_rs::calldata::full_proof_with_hints::groth16::{
    Groth16Proof,
    Groth16VerificationKey,
    get_groth16_calldata,
};
use garaga_rs::definitions::CurveID;

/// Input coming from Flutter
#[derive(Debug, Clone, Deserialize)]
pub struct Groth16Input {
    pub vk_json: String,
    pub proof_json: String,
    pub public_inputs_json: String,
}

/// Output returned to Flutter
/// We return a single flat list of calldata, because that is what garaga returns.
#[derive(Debug, Clone, Serialize)]
pub struct Groth16Calldata {
    pub calldata: Vec<String>, 
}

// --- Intermediate Structs for JSON Parsing (SnarkJS format) ---

// G1 point: {x, y, z}
#[derive(Deserialize)]
struct G1Point {
    x: String,
    y: String,
    z: String,
}

// G2 point: {x: [x0, x1], y: [y0, y1], z: [z0, z1]}
#[derive(Deserialize)]
struct G2Point {
    x: Vec<String>,
    y: Vec<String>,
    z: Vec<String>,
}

#[derive(Deserialize)]
struct RawProof {
    a: G1Point,
    b: G2Point,
    c: G1Point,
}

#[derive(Deserialize)]
struct RawVk {
    vk_alpha_1: Vec<String>,
    vk_beta_2: Vec<Vec<String>>,
    vk_gamma_2: Vec<Vec<String>>,
    vk_delta_2: Vec<Vec<String>>,
    IC: Vec<Vec<String>>,
}

// --- Helpers ---

/// Parse a hex or decimal string into BigUint
fn parse_biguint(s: &str) -> Result<BigUint, String> {
    if s.starts_with("0x") || s.starts_with("0X") {
        BigUint::from_str_radix(&s[2..], 16)
            .map_err(|e| format!("Invalid hex: {} ({})", s, e))
    } else {
        BigUint::from_str_radix(s, 10)
            .map_err(|e| format!("Invalid decimal: {} ({})", s, e))
    }
}

/// Flatten a standard SnarkJS VK into the Vec<BigUint> expected by Garaga
/// Note: This assumes Garaga expects: [alpha(2), beta(4), gamma(4), delta(4), IC(2*N)...]
fn flatten_vk(raw: RawVk) -> Result<Vec<BigUint>, String> {
    let mut values = Vec::new();

    // Alpha (G1, 2 elements)
    for s in &raw.vk_alpha_1[0..2] { values.push(parse_biguint(s)?); }

    // Beta (G2, 4 elements: X0, X1, Y0, Y1)
    // SnarkJS usually gives [ [x0, x1], [y0, y1] ]
    for coord in &raw.vk_beta_2[0..2] {
        for s in coord { values.push(parse_biguint(s)?); }
    }

    // Gamma (G2, 4 elements)
    for coord in &raw.vk_gamma_2[0..2] {
        for s in coord { values.push(parse_biguint(s)?); }
    }

    // Delta (G2, 4 elements)
    for coord in &raw.vk_delta_2[0..2] {
        for s in coord { values.push(parse_biguint(s)?); }
    }

    // IC (G1 points, 2 elements each)
    for point in &raw.IC {
        for s in &point[0..2] { values.push(parse_biguint(s)?); }
    }

    Ok(values)
}

/// Flatten SnarkJS Proof into Vec<BigUint>
fn flatten_proof(raw: RawProof) -> Result<Vec<BigUint>, String> {
    let mut values = Vec::new();

    // A (G1, 2 elements: x, y)
    values.push(parse_biguint(&raw.a.x)?);
    values.push(parse_biguint(&raw.a.y)?);

    // B (G2, 4 elements: x[0], x[1], y[0], y[1])
    values.push(parse_biguint(&raw.b.x[0])?);
    values.push(parse_biguint(&raw.b.x[1])?);
    values.push(parse_biguint(&raw.b.y[0])?);
    values.push(parse_biguint(&raw.b.y[1])?);

    // C (G1, 2 elements: x, y)
    values.push(parse_biguint(&raw.c.x)?);
    values.push(parse_biguint(&raw.c.y)?);

    Ok(values)
}

#[frb]
pub fn generate_groth16_calldata(input: Groth16Input) -> Result<Groth16Calldata, String> {
    init_logger();
    log::info!("[RUST] 010");
    init_panic_hook();
    log::info!("[RUST] 020");
    // 1. Parse JSON to intermediate structs
    let raw_vk: RawVk = serde_json::from_str(&input.vk_json)
        .map_err(|e| format!("Invalid VK JSON: {:?}", e))?;
    let raw_proof: RawProof = serde_json::from_str(&input.proof_json)
        .map_err(|e| format!("Invalid Proof JSON: {:?}", e))?;
    log::info!("[RUST] 030");
    // 2. Parse Public Inputs
    // Format: ["0","2501343721281063719479114572326273050667879391105840216035629478346449471975","66"]
    let raw_public_inputs: Vec<String> = serde_json::from_str(&input.public_inputs_json)
        .map_err(|e| format!("Invalid Public Inputs JSON: {:?}", e))?;
    log::info!("[RUST] 040");
    // Convert public inputs to BigUint
    let public_inputs: Vec<BigUint> = raw_public_inputs
        .iter()
        .map(|s| parse_biguint(s))
        .collect::<Result<Vec<_>, _>>()?;

    let vk_values = flatten_vk(raw_vk)?;
    log::info!("[RUST] 050");
    let proof_values = flatten_proof(raw_proof)?;
    log::info!("[RUST] 060");
    
    // 3. Create Garaga Structs
    // Groth16Proof::from expects a single Vec<BigUint> with format:
    // [a_x, a_y, b_x0, b_x1, b_y0, b_y1, c_x, c_y, public_input_0, public_input_1, ...]
    let mut all_proof_values = proof_values;
    all_proof_values.extend(public_inputs);

    log::info!("[RUST] 070");
    let vk = Groth16VerificationKey::from(vk_values);
    log::info!("[RUST] 080");
    let proof_obj = Groth16Proof::from(all_proof_values, None, None);
    log::info!("[RUST] 090");
    // 4. Generate Calldata
    // Your error said this returns `Vec<BigUint>`, not a tuple.
    let calldata_bigints = get_groth16_calldata(&proof_obj, &vk, CurveID::BN254)
        .map_err(|e| format!("Groth16 generation error: {:?}", e))?;
    log::info!("[RUST] 100");
    // 5. Convert to Hex Strings for Flutter
    let calldata_hex: Vec<String> = calldata_bigints.iter()
        .map(|b| format!("0x{}", b.to_str_radix(16)))
        .collect();
    log::info!("[RUST] 110");
    Ok(Groth16Calldata {
        calldata: calldata_hex,
    })
}