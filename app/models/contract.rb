class Contract < ApplicationRecord
  include ContractErrors
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  has_many :states, primary_key: 'address', foreign_key: 'contract_address', class_name: "ContractState"
  belongs_to :contract_transaction, foreign_key: :transaction_hash, primary_key: :transaction_hash, optional: true

  # belongs_to :ethscription, primary_key: 'transaction_hash', foreign_key: 'transaction_hash', optional: true
  
  has_many :contract_calls, foreign_key: :effective_contract_address, primary_key: :address
  has_one :transaction_receipt, through: :contract_transaction
  delegate :implements?, to: :implementation

  attr_reader :implementation
  
  attr_accessor :state_snapshots
  
  after_initialize :ensure_initial_state_snapshot
  
  def ensure_initial_state_snapshot
    take_state_snapshot if state_snapshots.empty?
  end
  
  def state_snapshots
    @state_snapshots ||= []
  end
  
  def take_state_snapshot
    state_snapshots.push({
      state: current_state,
      type: current_type,
      init_code_hash: current_init_code_hash
    })
  end
  
  def load_last_snapshot
    self.current_init_code_hash = state_snapshots.last[:init_code_hash]
    self.current_type = state_snapshots.last[:type]
    self.current_state = state_snapshots.last[:state]
  end
  
  def should_save_new_state?
    JsonSorter.sort_hash(state_snapshots.first) != JsonSorter.sort_hash(state_snapshots.last)
  end
  
  
  def new_state_for_save(block_number:)
    return unless should_save_new_state?

    ContractState.new(
      contract_address: address,
      block_number: block_number,
      state: state_snapshots.last[:state],
      type: state_snapshots.last[:type],
      init_code_hash: state_snapshots.last[:init_code_hash]
    )
  end
  
  
  def implementation_class
    return unless current_init_code_hash
    
    BlockContext.supported_contract_class(
      current_init_code_hash, validate: false
    )
  end
  
  def self.types_that_implement(base_type)
    ContractArtifact.types_that_implement(base_type)
  end
  
  def execute_function(function_name, args, is_static_call:)
    with_correct_implementation do
      if !implementation.public_abi[function_name]
        raise ContractError.new("Call to unknown function: #{function_name}", self)
      end
      
      read_only = implementation.public_abi[function_name].read_only?
      
      if is_static_call && !read_only
        raise ContractError.new("Cannot call non-read-only function in static call: #{function_name}", self)
      end
      
      result = if args.is_a?(Hash)
        implementation.public_send(function_name, **args)
      else
        implementation.public_send(function_name, *Array.wrap(args))
      end
      
      unless read_only
        self.current_state = self.current_state.merge(implementation.state_proxy.serialize)
      end
      
      result
    end
  end
  
  def with_correct_implementation
    old_implementation = implementation
    @implementation = implementation_class.new(
      initial_state: old_implementation&.state_proxy&.serialize ||
        current_state
    )
    
    result = yield
    
    post_execution_state = implementation.state_proxy.serialize
    
    if old_implementation
      @implementation = old_implementation
      implementation.state_proxy.load(post_execution_state)
    end
    
    result
  end
  
  def fresh_implementation_with_current_state
    implementation_class.new(initial_state: current_state)
  end
  
  def self.deployable_contracts
    ContractArtifact.deployable_contracts
  end
  
  def self.all_abis(...)
    ContractArtifact.all_abis(...)
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :address,
          :transaction_hash,
          :current_init_code_hash,
          :current_type
        ]
      )
    ).tap do |json|
      if implementation_class
        json['abi'] = implementation_class.abi.as_json
      end
      
      if association(:transaction_receipt).loaded?
        json['deployment_transaction'] = transaction_receipt
      end
      
      json['current_state'] = if options[:include_current_state]
        current_state
      else
        {}
      end
      
      json['current_state']['contract_type'] = current_type
      
      json['source_code'] = [
        {
          language: 'ruby',
          code: implementation_class&.source_code
        }
      ]
    end
  end
  
  def static_call(name, args = {})
    ContractTransaction.make_static_call(
      contract: address, 
      function_name: name, 
      function_args: args
    )
  end
end
