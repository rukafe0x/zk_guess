// This contract is for ZK game where a user A think a number, register the commitment in the contract
// and then user B try to guess the number calling the guess_intent function which will store the intent in the contract.
// Once A or B made their intent, user will send the proof to the verifier to check if the opponent guess is correct.
// If guess is correct, then the user will call the send_reward function for give reward to the opponent.
//  --- PRIVATE INPUTS (solo A los conoce) ---
// signal input x;      // número secreto elegido por A
// signal input salt;   // sal aleatoria para el compromiso

//  --- PUBLIC INPUTS (visibles en blockchain) ---
// signal input h;      // compromiso publicado on-chain
// signal input y;      // intento del jugador B
// signal output equal; // resultado (1 si acierta, 0 si no)

use super::groth16_verifier_constants::{N_PUBLIC_INPUTS, vk, ic, precomputed_lines};

#[starknet::interface]
pub trait IGroth16VerifierBN254<TContractState> {
    // Verify a Groth16 proof
    fn verify_groth16_proof_bn254(
        self: @TContractState,
        full_proof_with_hints: Span<felt252>,
    ) -> Option<Span<u256>>;
    // Register the commitment of the number
    fn register_commitment(
        ref self: TContractState,
        game_id: u256,
        commitment: u256,
    );
    // Send the intent of the number
    fn send_intent(ref self: TContractState, game_id: u256, intent: u256);
    // Verify intent
    fn verify_intent(ref self: TContractState, game_id: u256, full_proof_with_hints: Span<felt252>);
    // Claim the reward to the winner
    fn claim_reward(ref self: TContractState, game_id: u256);
}

#[starknet::contract]
mod Groth16VerifierBN254 {
    use starknet::SyscallResultTrait;
    use garaga::definitions::{G1Point, G1G2Pair};
    use garaga::groth16::{multi_pairing_check_bn254_3P_2F_with_extra_miller_loop_result};
    use garaga::ec_ops::{G1PointTrait, ec_safe_add};
    use garaga::ec_ops_g2::{G2PointTrait};
    use garaga::utils::calldata::{deserialize_full_proof_with_hints_bn254};
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use super::{N_PUBLIC_INPUTS, vk, ic, precomputed_lines};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map,
    };
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use core::traits::TryInto;
    use starknet::{get_block_info};

    const ECIP_OPS_CLASS_HASH: felt252 = 0x146ee805dd0252256484a6001dc932dd940b1787c0f24e65629f4f6645f0692;

    #[storage]
    struct Storage {
        game_id: Map<u256, game_struct>,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct game_struct {
        player1: ContractAddress,
        player2: ContractAddress,
        commitment1: u256,
        commitment2: u256,
        intent1: u256,
        intent2: u256,
        reward: u256,
        last_intent1_blocknumber: u64,
        last_intent2_blocknumber: u64,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Intent: Intent,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Intent {
        #[key]
        pub intent: u256,
    }

    #[abi(embed_v0)]
    impl IGroth16VerifierBN254 of super::IGroth16VerifierBN254<ContractState> {
        fn register_commitment(
            ref self: ContractState,
            game_id: u256,
            commitment: u256,
        ) {
            // Register the commitment
            let mut game=self.game_id.entry(game_id);
            // if player1 is not set, set it
            if game.player1.read()==0.try_into().unwrap() {
                game.player1.write(get_caller_address());
                game.commitment1.write(commitment);
            } else {
                if game.player2.read()==0.try_into().unwrap() {
                game.player2.write(get_caller_address());
                    game.commitment2.write(commitment);
                } else {
                    panic!("Game already has two players");
                }
            }
        }

        fn send_intent(ref self: ContractState, game_id: u256, intent: u256) {
            // TODO: Implement the function
            // check which player is calling the function
            let mut game=self.game_id.entry(game_id);
            if game.player1.read()==get_caller_address() {
                game.intent1.write(intent);
                game.last_intent1_blocknumber.write(get_block_info().block_number.into());
            } else {
                game.intent2.write(intent);
                game.last_intent2_blocknumber.write(get_block_info().block_number.into());
            }
            // Write intent as an event
            //Event::Intent(Intent { intent }).emit();
        }

        fn claim_reward(ref self: ContractState, game_id: u256) {
            //check if blocknumber has advanced 1000 blocks since last intent
            let mut game=self.game_id.entry(game_id);
            if game.player1.read()==get_caller_address() {
                if get_block_info().block_number-game.last_intent1_blocknumber.read()>1000 {
                    panic!("Blocknumber has not advanced 1000 blocks since last intent");
                } else {
                    //transfer reward to player1
                    let reward=game.reward.read();
                    let strk_token_dispatcher = ERC20ABIDispatcher {
                        contract_address: 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap() // STRK Contract Address
                    };
                    strk_token_dispatcher.transfer(game.player1.read(), reward);
                }
            }
            if game.player2.read()==get_caller_address() {
                if get_block_info().block_number-game.last_intent2_blocknumber.read()>1000 {
                    panic!("Blocknumber has not advanced 1000 blocks since last intent");
                } else {
                    //transfer reward to player2
                    let reward=game.reward.read();
                    let strk_token_dispatcher = ERC20ABIDispatcher {
                        contract_address: 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap() // STRK Contract Address
                    };
                    strk_token_dispatcher.transfer(game.player2.read(), reward);
                }
            }
        }

        fn verify_intent(ref self: ContractState, game_id: u256, full_proof_with_hints: Span<felt252>) {
            // TODO: Implement the function
            // First verify the proof
            let player_address=get_caller_address();
            // get the opponent address depending on the player calling the function 
            // if messender is player1, then opponent is player2
            // if messender is player2, then opponent is player1
            let mut opponent_address=self.game_id.entry(game_id).player2.read();
            let mut commitment=self.game_id.entry(game_id).commitment2.read();
            if player_address==opponent_address {
                opponent_address=self.game_id.entry(game_id).player1.read();
                commitment=self.game_id.entry(game_id).commitment1.read();
            }
            // verify the proof and get the public inputs
            let public_inputs=self.verify_groth16_proof_bn254(full_proof_with_hints);
            match public_inputs {
                Some(public_inputs) => {
                    //let public_inputs_span=public_inputs.span();
                    // Then verify the commitment
                    if commitment==*public_inputs.at(1) {
                        // Send the reward to the opponent
                        let reward=self.game_id.entry(game_id).reward.read();
                        let strk_token_dispatcher = ERC20ABIDispatcher {
                            contract_address: 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap() // STRK Contract Address
                        };
                        strk_token_dispatcher.transfer(opponent_address, reward);
                    } else {
                        panic!("Commitment is invalid");
                    }
                },
                None => {
                    panic!("Public inputs are None");
                }
            }
        }

        fn verify_groth16_proof_bn254(
            self: @ContractState,
            full_proof_with_hints: Span<felt252>,
        ) -> Option<Span<u256>> {
            // DO NOT EDIT THIS FUNCTION UNLESS YOU KNOW WHAT YOU ARE DOING.
            // This function returns an Option for the public inputs if the proof is valid.
            // If the proof is invalid, the execution will either fail or return None.
            // Read the documentation to learn how to generate the full_proof_with_hints array given a proof and a verifying key.
            let fph = deserialize_full_proof_with_hints_bn254(full_proof_with_hints);
            let groth16_proof = fph.groth16_proof;
            let mpcheck_hint = fph.mpcheck_hint;
            let small_Q = fph.small_Q;
            let msm_hint = fph.msm_hint;

            groth16_proof.a.assert_on_curve(0);
            groth16_proof.b.assert_on_curve(0);
            groth16_proof.c.assert_on_curve(0);

            let ic = ic.span();

            let vk_x: G1Point = match ic.len() {
                0 => panic!("Malformed VK"),
                1 => *ic.at(0),
                _ => {
                    // Start serialization with the hint array directly to avoid copying it.
                    let mut msm_calldata: Array<felt252> = array![];
                    // Add the points from VK and public inputs to the proof.
                    Serde::serialize(@ic.slice(1, N_PUBLIC_INPUTS), ref msm_calldata);
                    Serde::serialize(@groth16_proof.public_inputs, ref msm_calldata);
                    // Complete with the curve indentifier (0 for BN254):
                    msm_calldata.append(0);
                    // Add the hint array.
                    for x in msm_hint {
                        msm_calldata.append(*x);
                    }

                    // Call the multi scalar multiplication endpoint on the Garaga ECIP ops contract
                    // to obtain vk_x.
                    let mut _vx_x_serialized = starknet::syscalls::library_call_syscall(
                        ECIP_OPS_CLASS_HASH.try_into().unwrap(),
                        selector!("msm_g1"),
                        msm_calldata.span()
                    )
                        .unwrap_syscall();

                    ec_safe_add(
                        Serde::<G1Point>::deserialize(ref _vx_x_serialized).unwrap(), *ic.at(0), 0
                    )
                }
            };
            // Perform the pairing check.
            let check = multi_pairing_check_bn254_3P_2F_with_extra_miller_loop_result(
                G1G2Pair { p: vk_x, q: vk.gamma_g2 },
                G1G2Pair { p: groth16_proof.c, q: vk.delta_g2 },
                G1G2Pair { p: groth16_proof.a.negate(0), q: groth16_proof.b },
                vk.alpha_beta_miller_loop_result,
                precomputed_lines.span(),
                mpcheck_hint,
                small_Q
            );
            if check == true {
                return Option::Some(groth16_proof.public_inputs);
            } else {
                return Option::None;
            }
        }
    }
}


    