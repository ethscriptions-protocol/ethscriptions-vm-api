class TypedVariable
  include TypedObject
  
  include ContractErrors
  extend AttrPublicReadPrivateWrite
  
  attr_accessor :value, :on_change
  attr_public_read_private_write :type

  def initialize(type, value = nil, on_change: nil, **options)
    self.type = type
    self.value = value.nil? ? type.default_value : value
    self.on_change = on_change
    
    if type.bool?
      raise TypeError.new("Use literals instead of TypedVariable for booleans")
    end
    
    extend_with_type_methods
  end
  
  def self.create(type, value = nil, on_change: nil, **options)
    type = Type.create(type)
    
    if type.bool?
      return value.nil? ? type.default_value :
        type.check_and_normalize_literal(value)
    end
    
    options[:on_change] = on_change
    
    if type.mapping?
      MappingVariable.new(type, value, **options)
    elsif type.array?
      ArrayVariable.new(type, value, **options)
    elsif type.contract?
      ContractVariable.new(type, value, **options)
    elsif type.struct?
      StructVariable.new(type, value, **options)
    else
      new(type, value, **options)
    end
  end
  
  def self.create_or_validate(type, value = nil, on_change: nil)
    if value.is_a?(TypedObject)
      unless Type.create(type).can_be_assigned_from?(value.type)
        raise VariableTypeError.new("invalid #{type}: #{value.inspect}")
      end
      
      value = value.value
    end
    
    create(type, value, on_change: on_change)
  end
  
  def self.validated_value(type, value, allow_nil: false)
    return nil if value.nil? && allow_nil
    
    create_or_validate(type, value).value
  end
  
  def as_json(args = {})
    serialize
  end
  
  def to_s
    if type.string?
      value
    else
      raise "No string conversion"
    end
  end
  
  def deserialize(serialized_value)
    self.value = serialized_value
  end
  
  def value=(new_value)
    new_value = type.check_and_normalize_literal(new_value)
    
    if @value != new_value
      on_change&.call
      
      if new_value.respond_to?(:on_change=)
        new_value.on_change = on_change
      end
      
      @value = new_value
    end
  end
  
  def method_missing(name, *args, &block)
    if value.respond_to?(name)
      result = value.send(name, *args, &block)
      
      if result.class == value.class
        begin
          result = type.check_and_normalize_literal(result)
        rescue ContractErrors::VariableTypeError => e
          if type.is_uint?
            result = TypedVariable.create(:uint256, result)
          else
            raise
          end
        end
      end
      
      result
    else
      super
    end
  rescue ZeroDivisionError => e
    raise ContractErrors::VariableTypeError.new("Division by zero")
  end

  def respond_to_missing?(name, include_private = false)
    value.respond_to?(name, include_private) || super
  end
  
  def !
    raise TypeError.new("Cannot negate `TypedVariable's")
  end
  
  def !=(other)
    !(self == other)
  end
  
  def ==(other)
    if other.is_a?(TypedObject)
      return false unless type.values_can_be_compared?(other.type)
      return value == other.value
    else
      return value == TypedVariable.create(type, other).value
    end
  end
  
  def hash
    [value, type].hash
  end

  def eql?(other)
    hash == other.hash
  end
  
  def toPackedBytes
    TypedVariable.create(:bytes, value)
  end
  
  private
  
  def extend_with_type_methods
    if type.address?
      extend RubidityTypeExtensions::AddressMethods
    end
    
    if type.string?
      extend RubidityTypeExtensions::StringMethods
    end
    
    if type.bytes?
      extend RubidityTypeExtensions::BytesMethods
    end
    
    if type.is_int? || type.is_uint?
      extend RubidityTypeExtensions::UintOrIntMethods
    end
  end
end
