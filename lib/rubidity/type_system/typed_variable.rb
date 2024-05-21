class TypedVariable
  include ContractErrors
  extend Memoist
  class << self; extend Memoist; end
  
  [:==, :>, :<=, :>=, :<, :!, :!=].each do |method|
    undef_method(method) if method_defined?(method)
  end
  
  attr_accessor :value, :type
  
  def initialize(type, value = nil, **options)
    self.type = type
    self.value = value.nil? ? type.default_value : value
  end
  
  def self.create(type, value = nil, **options)
    type = Type.create(type)
    
    if type.array?
      ArrayVariable.new(type, value, **options)
    elsif type.contract?
      ContractVariable.new(type, value, **options)
    elsif type.struct?
      StructVariable.new(type, value, **options)
    elsif type.string?
      StringVariable.new(type, value, **options)
    elsif type.bytes?
      BytesVariable.new(type, value, **options)
    elsif type.address?
      AddressVariable.new(type, value, **options)
    elsif type.is_int? || type.is_uint?
      IntegerVariable.new(type, value, **options)
    elsif type.null?
      NullVariable.instance
    else
      GenericVariable.new(type, value, **options)
    end
  end
  
  def self.create_as_proxy(...)
    ::TypedVariableProxy.new(create(...))
  end
  
  def self.create_or_validate(type, value = nil)
    if value.is_a?(StoragePointer)
      if value.current_type.array?
        value = value.load_array
      elsif value.current_type.struct?
        value = value.load_struct
      end
    end
    
    if value.is_a?(TypedVariable)
      unless Type.create(type).can_be_assigned_from?(value.type)
        raise VariableTypeError.new("invalid #{type}: #{value.inspect}")
      end
      
      value = value.value
    end
    
    create(type, value)
  end
  
  def self.validated_value(type, value, allow_nil: false)
    return nil if value.nil? && allow_nil
    
    create_or_validate(type, value).value
  end
  
  def as_json(args = {})
    serialize
  end
  
  def serialize
    value
  end
  
  def to_s
    if type.string?
      value
    else
      raise "No string conversion"
    end
  end
  
  def has_default_value?
    value == type.default_value
  end
  
  # TODO: Make immutable for value types
  def value=(new_value)
    if type.bool? && !@value.nil?
      raise TypeError.new("Cannot change value of #{self.value.inspect}")
    end
    
    new_value = type.check_and_normalize_literal(new_value)
    
    if @value != new_value
      if type.is_value_type? && @value != type.default_value && !@value.nil?
        raise TypeError.new("Cannot change value of #{self.value.inspect}")
      end
      
      @value = new_value
    end
  end
  
  def hash
    [value.hash, type.hash].hash
  end

  def eql?(other)
    hash == other.hash
  end
end
