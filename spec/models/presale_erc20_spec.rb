require 'rails_helper'

RSpec.describe "PresaleERC20", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner_address) { "0x000000000000000000000000000000000000000a" }
  let(:buyer_address) { "0x000000000000000000000000000000000000000b" }
  let(:seller_address) { "0x000000000000000000000000000000000000000c" }
  let(:max_supply) { 10_000_000.ether }
  let(:presale_token_percentage) { 45 }
  let(:tokens_for_presale) { ((max_supply * presale_token_percentage) / 100).floor }
  let(:presale_duration) { 1.hour }

  let(:weth_contract) do
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "PublicMintERC20",
          args: {
            name: "WETH",
            symbol: "WETH",
            maxSupply: 100_000_000_000.ether,
            perMintLimit: 1_000_000.ether,
            decimals: 18
          }
        }
      }
    )
  end
  let(:factory_contract) do
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "FacetSwapV1Factory02",
          args: { _feeToSetter: owner_address }
        }
      }
    )
  end
  let(:router_contract) do
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "FacetSwapV1Router03",
          args: {
            _factory: factory_contract.address,
            _WETH: weth_contract.address,
            protocolFeeBPS: 0,
            initialPauseState: false
          }
        }
      }
    )
  end
  let(:presale_contract) do
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        op: :create,
        data: {
          type: "PresaleERC20",
          args: {
            name: "PresaleToken",
            symbol: "PST",
            _wethAddress: weth_contract.address,
            _facetSwapRouterAddress: router_contract.address,
            _maxSupply: max_supply,
            _presaleTokenPercentage: 45,
            _presaleDuration: presale_duration
          }
        }
      }
    )
  end

  before do
    update_supported_contracts(
      "FacetSwapV1Factory02",
      "PublicMintERC20",
      "PresaleERC20"
    )
    trigger_contract_interaction_and_expect_success(
      from: buyer_address,
      payload: {
        to: weth_contract.address,
        data: {
          function: "mint",
          args: {
            amount: 1_000_000.ether
          }
        }
      }
    )
  end

  describe 'presale process' do
    it 'does not allow buying shares before the presale' do
      buy_amount = 100.ether
      buy_shares_error(buy_amount, "Presale has not started")
    end

    context 'after presale starts' do
      before(:each) do
        start_presale_success()
      end

      it 'does not allow starting presale twice' do
        start_presale_error("Already started")
      end

      it 'allows buying shares during the presale' do
        buy_amount = 100.ether

        expect {
          buy_shares_success(buy_amount)
        }.to change {
          get_contract_state(presale_contract.address, "shares", buyer_address)
        }.from(0).to(buy_amount)
      end

      it 'allows selling shares during the presale' do
        buy_amount = 100.ether
        buy_shares_success(buy_amount)

        sell_amount = 5.ether
        sell_shares_success(sell_amount)

        expect(get_contract_state(presale_contract.address, "shares", buyer_address)).to eq(buy_amount - sell_amount)
      end

      it 'does not allow finalizing before the presale ends' do
        buy_amount = 100.ether
        buy_shares_success(buy_amount)

        finalize_presale_error("Presale not finished")
      end
    end

    context 'after presale ends' do
      before(:each) do
        start_presale_success()
        buy_shares_success(100.ether)
        travel_to Time.now + 1.hour
      end

      it 'does not allow buying shares after the presale' do
        buy_shares_error(100.ether, "Presale has ended")
      end

      it 'does not allow selling shares after the presale' do
        sell_shares_error(5.ether, "Presale has ended")
      end

      it 'allows claiming tokens after the presale is finalized' do
        finalize_presale_success()
        pair_address = get_contract_state(presale_contract.address, "pairAddress")
        expect(pair_address).not_to be_nil
        expect(get_contract_state(presale_contract.address, "balanceOf", pair_address)).to eq(tokens_for_presale)
        expect(get_contract_state(weth_contract.address, "balanceOf", pair_address)).to eq(100.ether)

        claim_receipt = claim_tokens_success()
        expect(claim_receipt.logs).to include(hash_including('event' => 'TokensClaimed'))
        expect(claim_receipt.logs.last["data"]).to include("shareAmount" => 100.ether)
        expect(claim_receipt.logs.last["data"]).to include("tokenAmount" => tokens_for_presale)
      end

      it 'does not allow claiming tokens twice' do
        claim_tokens_success()
        claim_tokens_error("User does not own shares")
      end

      it 'does not allow finalizing twice' do
        finalize_presale_success()
        finalize_presale_error("Already finalized")
      end

      it 'allows team to claim tokens' do
        finalize_presale_success()

        withdraw_receipt = withdraw_tokens_success(owner_address)
        expect(withdraw_receipt.logs).to include(hash_including('event' => 'Transfer'))
        expect(withdraw_receipt.logs.first["data"]).to include("amount" => max_supply - (tokens_for_presale * 2))
        expect(withdraw_receipt.logs.first["data"]).to include("to" => owner_address)
      end

      it 'does not allow team to claim tokens twice' do
        finalize_presale_success()

        withdraw_tokens_success(owner_address)
        withdraw_tokens_error(owner_address, "No token balance")
      end
    end
    
    context 'after presale ends with no shares bought' do
      before(:each) do
        start_presale_success()
        travel_to Time.now + 1.hour
      end

      it 'handles no shares bought during presale' do
        trigger_contract_interaction_and_expect_error(
          error_msg_includes: "Division by zero",
          from: owner_address,
          payload: {
            to: presale_contract.address,
            data: {
              function: "finalize",
              args: {}
            }
          }
        )
      end
    end
  end

  # HELPER FUNCTIONS

  def set_weth_allowance(wallet, amount)
    trigger_contract_interaction_and_expect_success(
      from: wallet,
      payload: {
        to: weth_contract.address,
        data: {
          function: "approve",
          args: {
            spender: presale_contract.address,
            amount: amount
          }
        }
      }
    )
  end

  def finalize_presale_success
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "finalize",
          args: {}
        }
      }
    )
  end

  def finalize_presale_error(error_msg)
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: error_msg,
      from: owner_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "finalize",
          args: {}
        }
      }
    )
  end

  def start_presale_success
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "startPresale",
          args: {}
        }
      }
    )
  end

  def start_presale_error(error_msg)
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: error_msg,
      from: owner_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "startPresale",
          args: {}
        }
      }
    )
  end

  def buy_shares_success(buy_amount)
    set_weth_allowance(buyer_address, buy_amount)
    trigger_contract_interaction_and_expect_success(
      from: buyer_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "buyShares",
          args: {
            recipient: buyer_address,
            amount: buy_amount
          }
        }
      }
    )
  end

  def buy_shares_error(buy_amount, error_msg)
    set_weth_allowance(buyer_address, buy_amount)
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: error_msg,
      from: buyer_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "buyShares",
          args: {
            recipient: buyer_address,
            amount: buy_amount
          }
        }
      }
    )
  end

  def sell_shares_success(sell_amount)
    trigger_contract_interaction_and_expect_success(
      from: buyer_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "sellShares",
          args: {
            amount: sell_amount
          }
        }
      }
    )
  end

  def sell_shares_error(sell_amount, error_msg)
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: error_msg,
      from: buyer_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "sellShares",
          args: {
            amount: sell_amount
          }
        }
      }
    )
  end

  def claim_tokens_success
    trigger_contract_interaction_and_expect_success(
      from: buyer_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "claimTokens",
          args: {}
        }
      }
    )
  end

  def claim_tokens_error(error_msg)
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: error_msg,
      from: buyer_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "claimTokens",
          args: {}
        }
      }
    )
  end

  def withdraw_tokens_success(recipient)
    trigger_contract_interaction_and_expect_success(
      from: owner_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "withdrawTokens",
          args: {
            recipient: recipient
          }
        }
      }
    )
  end

  def withdraw_tokens_error(recipient, error_msg)
    trigger_contract_interaction_and_expect_error(
      error_msg_includes: error_msg,
      from: owner_address,
      payload: {
        to: presale_contract.address,
        data: {
          function: "withdrawTokens",
          args: {
            recipient: recipient
          }
        }
      }
    )
  end

  def get_contract_state(contract_address, function_name, *args, **kwargs)
    ContractTransaction.make_static_call(
      contract: contract_address,
      function_name: function_name,
      function_args: kwargs.presence || args
    )
  end

  def get_contract_state(contract_address, function_name, *args, **kwargs)
    ContractTransaction.make_static_call(
      contract: contract_address,
      function_name: function_name,
      function_args: kwargs.presence || args
    )
  end
end
