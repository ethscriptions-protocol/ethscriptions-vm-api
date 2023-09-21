class Contracts::EtherBridge < ContractImplementation
  pragma :rubidity, "1.0.0"
  
  is :ERC20

  event :InitiateWithdrawal, { from: :address, amount: :uint256, withdrawalId: :bytes32 }
  event :WithdrawalComplete, { to: :address, amounts: [:uint256], withdrawalIds: [:bytes32] }

  address :public, :trustedSmartContract
  mapping ({ address: :uint256 }), :public, :pendingWithdrawalAmounts
  mapping ({ address: array(:bytes32) }), :public, :pendingUserWithdrawalIds

  constructor(
    name: :string,
    symbol: :string,
    trustedSmartContract: :address
  ) {
    ERC20.constructor(name: name, symbol: symbol, decimals: 18)
    
    s.trustedSmartContract = trustedSmartContract
  }
  
  function :bridgeIn, { to: :address, amount: :uint256 }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      "Only the trusted smart contract can bridge in tokens"
    )
    
    _mint(to: to, amount: amount)
  end
  
  function :bridgeOut, { amount: :uint256 }, :public do
    _burn(from: msg.sender, amount: amount)
    
    withdrawalId = TransactionContext.transaction_hash
    
    s.pendingWithdrawalAmounts[msg.sender] += amount
    s.pendingUserWithdrawalIds[msg.sender].push(withdrawalId)
    
    emit :InitiateWithdrawal, from: msg.sender, amount: amount, withdrawalId: withdrawalId
  end
  
  function :markWithdrawalComplete, {
    to: :address,
    amounts: [:uint256],
    withdrawalIds: [:bytes32]
  }, :public do
    require(
      msg.sender == s.trustedSmartContract,
      'Only the trusted smart contract can mark withdrawals as complete'
    )
    
    for i in 0...withdrawalIds.length
      withdrawalId = withdrawalIds[i]
      amount = amounts[i]
      
      require(
        s.pendingWithdrawalAmounts[to] >= amount,
        'Insufficient pending withdrawal'
      )
      
      require(
        _removeFirstOccurenceOfValueFromArray(
          s.pendingUserWithdrawalIds[to],
          withdrawalId
        ),
        "Withdrawal id not found"
      )
      
      s.pendingWithdrawalAmounts[to] -= amount
    end
      
    emit :WithdrawalComplete, to: to, amounts: amounts, withdrawalIds: withdrawalIds
  end
  
  function :getPendingWithdrawalsForUser, { user: :address }, :public, :view, returns: [:bytes32] do
    return s.pendingUserWithdrawalIds[user]
  end
  
  function :_removeFirstOccurenceOfValueFromArray, { arr: array(:bytes32), value: :bytes32 }, :internal do
    for i in 0...arr.length
      if arr[i] == value
        return _removeItemAtIndex(arr: arr, indexToRemove: i)
      end
    end
    
    return false
  end
  
  function :_removeItemAtIndex, { arr: array(:bytes32), indexToRemove: :uint256 }, :internal, returns: :bool do
    lastIndex = arr.length - 1
    
    if lastIndex != indexToRemove
      lastItem = arr[lastIndex]
      arr[indexToRemove] = lastItem
    end
    
    arr.pop
    
    return true
  end
end
