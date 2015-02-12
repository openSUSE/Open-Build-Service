class Buildresult < ActiveXML::Node

  Avail_status_values = %w(succeeded failed unresolvable broken blocked dispatching scheduled
                           building finished signing disabled excluded locked deleting unknown)
  @@status_hash = nil

  def self.avail_status_values
    Avail_status_values
  end

  def self.code2index(code)
    unless @@status_hash
      @@status_hash = Hash.new
      Avail_status_values.each_with_index do |s,index|
        @@status_hash[s] = index
      end
    end
    raise ArgumentError, "code '#{code}' unknown #{@@status_hash.inspect}" unless @@status_hash[code]
    @@status_hash[code]
  end

  def self.index2code(index)
    Avail_status_values[index]
  end

end
