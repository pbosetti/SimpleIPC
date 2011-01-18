#!/usr/bin/env ruby
#  simple_ipc
#
#  Created by Paolo Bosetti on 2011-01-18.
#  Copyright (c) 2011 University of Trento. All rights reserved.
#

require "yaml"
require "socket"
require "timeout"

# SimpleIPC implements a simple inter process communication
# @author Paolo Bosetti
class SimpleIPC
  LOCALHOST = "127.0.0.1"
  LENGTH_CODE = 'N'
  LENGTH_SIZE = [0].pack(LENGTH_CODE).size
  
  attr_accessor :cfg
  
  def initialize(args = {})
    raise ArgumentError, "expecting an Hash" unless args.kind_of? Hash
    @cfg = {:port => 5000, :host => LOCALHOST, :timeout => 0}
    @cfg.merge! args
    @socket = UDPSocket.new
  end
  
  # Sends something to the server
  # @param [Object] something an object
  def send(something)
    if block_given? then
      payload = yield(something)
    else
      payload = YAML.dump(something)
    end
    length = [payload.size].pack(LENGTH_CODE)
    @socket.connect(@cfg[:host], @cfg[:port])
    @socket.print length
    @socket.print payload
    return payload
  end
  
  def listen
    @socket.bind(LOCALHOST, @cfg[:port])
  end
  
  def get
    result = nil
    begin
      if @cfg[:timeout] > 0 and !@cfg[:nonblock] then
        Timeout::timeout(@cfg[:timeout]) do |to|
          result = get_
        end
      else 
        result = get_
      end
    rescue Timeout::Error
      result = nil
    rescue Errno::EAGAIN
      return nil
    end
    
    if block_given? then
      return yield(result)
    else
      return YAML.load(result)
    end
  end
  
  def close
    @socket.close
  end
  
  def test_method
    
  end
  
  private
  def get_
    if @cfg[:nonblock] then
      msg, sender = @socket.recv_nonblock(LENGTH_SIZE)
    else
      msg = @socket.recvfrom(LENGTH_SIZE)[0]
    end
    length = msg.unpack(LENGTH_CODE)[0]
    msg, sender = @socket.recvfrom(length)
    return msg
  end
  
end

if $0 == __FILE__ then
  ary = [1,2,3,4]
  if ARGV[0] == "server" then
    from_client = SimpleIPC.new :port => 5000, :nonblock => true
    from_client.listen
    running = true
    while running != "stop" do
      running = from_client.get
      p running if running
      sleep 0.01
    end
    # p from_client.get
    # p from_client.get {|s| s.split(",").map {|v| v.to_f}}
    # p from_client.get {|s| s.unpack("N4")}
    
  else # client
    to_server = SimpleIPC.new :port => 5000
    to_server.send([1,2,3, "test"])
    to_server.send({:a => "test", :b => "prova"})
    to_server.send("stop")
    
    # to_server.send([1,2,3,4]) {|o| o * ","}
    # to_server.send(ary) {|o| o.pack("N#{ary.size}")}
    to_server.close
  end
end



