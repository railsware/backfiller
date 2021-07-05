# frozen_string_literal: true

class LoggerMock
  attr_reader :messages

  def initialize
    @messages = []
  end

  %i[
    debug
    info
    warn
    error
  ].each do |name|
    define_method(name) do |message|
      @messages << message
    end

    define_method(:"#{name}?") do
      true
    end
  end

  def reset
    @messages.clear
  end
end
