class Esc
  include ContractErrors
  
  def initialize(ethscription)
    @ethscription = ethscription
    @as_of = if Rails.env.test?
      "0xf5b2a0296d6be54483955e55c5f921f054e63c6ea6b3b5fc8f686d94f08b97e7"
    else
      if ethscription.mock_for_simulate_transaction
        Ethscription.newest_first.second.ethscription_id
      else
        ethscription.ethscription_id
      end
    end
  end

  def findEthscriptionById(id)
    id = TypedVariable.create_or_validate(:bytes32, id).value

    begin
      Ethscription.esc_findEthscriptionById(id, @as_of)
    rescue ContractErrors::UnknownEthscriptionError => e
      raise ContractError.new(
        "findEthscriptionById: unknown ethscription: #{id}"
      )
    end
  end

  def currentTransactionHash
    TransactionContext.transaction_hash
  end

  def base64Encode(str)
    Base64.strict_encode64(str)
  end
  
  def upgradeContract(new_init_code_hash)
    # TODO: enforce bytes32
    new_init_code_hash = new_init_code_hash.value.sub(/^0x/, '')
    
    target = TransactionContext.call_stack.current_frame.to_contract
    new_implementation_class = TransactionContext.implementation_from_init_code(new_init_code_hash)
    
    target.implementation_versions.create!(
      transaction_hash: TransactionContext.transaction_hash,
      block_number: TransactionContext.block_number,
      transaction_index: TransactionContext.transaction_index,
      internal_transaction_index: TransactionContext.current_call.internal_transaction_index,
      init_code_hash: new_init_code_hash
    )
    
    target.update!(
      type: new_implementation_class.name,
      current_init_code_hash: new_init_code_hash
    )
    
    nil
  end
end
