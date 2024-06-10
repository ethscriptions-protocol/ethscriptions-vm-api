class ContractArtifact < ApplicationRecord
  include ContractErrors
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true
  has_many :contracts, foreign_key: :current_init_code_hash, primary_key: :init_code_hash
  
  has_many :contract_dependencies, -> { order(:position) }, foreign_key: :contract_artifact_init_code_hash, primary_key: :init_code_hash, dependent: :destroy, inverse_of: :contract_artifact
  has_many :dependencies, through: :contract_dependencies, source: :dependency
  has_many :dependent_contract_dependencies, class_name: 'ContractDependency', foreign_key: :dependency_init_code_hash, primary_key: :init_code_hash, inverse_of: :dependency
  
  scope :newest_first, -> {
    order(
      block_number: :desc,
      transaction_index: :desc
    ) 
  }
  
  class << self
    include Memery
    
    def sort_and_hash(data)
      json = JSON.generate(recursive_sort(data), max_nesting: false)
      "0x" + Digest::Keccak256.hexdigest(json)
    end
    memoize :sort_and_hash
    
    def recursive_sort(value)
      case value
      when Hash
        value.keys.sort.each_with_object({}) do |key, hash|
          hash[key] = recursive_sort(value[key])
        end
      when Array
        value.map { |element| recursive_sort(element) }
      else
        value
      end
    end
  end
  
  def set_abi
    self.abi = build_class.abi.as_json
  end
  
  def self.from_name(name)
    raise if Rails.env.production?
    a = RubidityTranspiler.new(name).generate_contract_artifact_json
    parse_and_store(a)
  end
  
  def to_serializable_hash
    {
      name: name,
      ast: ast,
      init_code_hash: init_code_hash,
      # legacy_source_code: legacy_source_code,
      dependencies: dependencies.map(&:to_serializable_hash)
    }.tap do |hsh|
      # if legacy_source_code
      #   hsh[:legacy_source_code] = legacy_source_code
      # end
      
      # if legacy_init_code_hash
      #   hsh[:legacy_init_code_hash] = legacy_init_code_hash
      # end
    end
  end

  def legacy_init_code_hash
    RubidityTranspiler.new(legacy_source_code).legacy_init_code_hash
  end
  
  def self.precompute_hashes(artifact_data, legacy_mode: false)
    # binding.pry unless legacy_mode
    artifact_data = artifact_data.deep_symbolize_keys
  
    # Recursively compute hashes for dependencies
    artifact_data[:dependencies] = artifact_data[:dependencies].map do |dep_data|
      precompute_hashes(dep_data, legacy_mode: legacy_mode)
    end
    
    if legacy_mode
      # Compute hash for legacy mode
      artifact_data[:init_code_hash] = RubidityTranspiler.new(artifact_data[:legacy_source_code]).
        legacy_init_code_hash
    else
      # Compute hash for normal mode
      combined_data = {
        name: artifact_data[:name],
        ast: artifact_data[:ast],
        dependencies: artifact_data[:dependencies].map { |dep| dep[:init_code_hash] }
      }
      computed_init_code_hash = sort_and_hash(combined_data)
  
      # Check if provided init_code_hash matches computed hash
      if artifact_data[:init_code_hash] && artifact_data[:init_code_hash] != computed_init_code_hash
        binding.pry
        raise "Provided init_code_hash does not match computed hash for #{artifact_data[:name]}"
      end
  
      artifact_data[:init_code_hash] = computed_init_code_hash
    end
  
    artifact_data
  end
  
  def self.parse_and_store(artifact_data, context = nil, legacy_mode: false)
    precomputed_data = precompute_hashes(
      artifact_data.deep_symbolize_keys,
      legacy_mode: legacy_mode
    )
    
    parse_and_store_recursively(precomputed_data, context)
  end
  
  def self.parse_and_store_recursively(artifact_data, context = nil)
    artifact = new(
      name: artifact_data[:name],
      ast: artifact_data[:ast],
      init_code_hash: artifact_data[:init_code_hash],
      legacy_source_code: artifact_data[:legacy_source_code]
    )

    # First pass: Parse and store dependencies
    dependencies = artifact_data[:dependencies].map do |dep_data|
      parse_and_store_recursively(dep_data, context)
    end

    # Second pass: Build associations
    dependencies.each_with_index do |dependency, index|
      artifact.contract_dependencies.build(dependency: dependency, position: index + 1)
      artifact.dependencies.target << dependency
    end

    # Calculate execution_source_code
    artifact.generate_execution_source_code

    if context
      context.add_contract_artifact(artifact)
    end

    artifact
  end
  
  def generate_execution_source_code
    self.execution_source_code ||= CombinedProcessor.new(ast).process
  end
  
  def source_code
    legacy_source_code
  end
  
  def contract_class
    return @_contract_class if @_contract_class
    
    @_contract_class = ContractBuilder.build_contract_class(self)
    self.abi = @_contract_class.abi
    @_contract_class
  end
  
  def build_class
    contract_class
  end
  
  def as_json(options = {})
    super(
      options.merge(
        only: [
          :name,
          :ast,
          :init_code_hash,
          :execution_source_code,
        ],
        methods: [
          :verbose_execution_source_code
        ]
      )
    ).with_indifferent_access.tap do |json|
      json[:dependencies] = dependencies.map(&:as_json)
      json[:source_code] = source_code
      json[:abi] ||= contract_class.abi
      json[:abi] = json[:abi].as_json
      json[:create_payload] = to_serializable_hash
    end
  end
  
  def generate_ast_array
    (dependencies.map(&:generate_ast_array) + [ast]).flatten
  end
  
  def verbose_execution_source_code
    generate_ast_array.map do |ast|
      CombinedProcessor.new(ast).process
    end.join("\n")
  end
end
