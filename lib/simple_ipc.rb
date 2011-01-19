#!/usr/bin/env ruby
#  simple_ipc
#
#  Created by Paolo Bosetti on 2011-01-18.
#  Copyright (c) 2011 University of Trento. All rights reserved.
#

require "yaml"
require "socket"
require "timeout"
require "fileutils"


# SimpleIPC implements a simple inter process communication
# @author Paolo Bosetti
module SimpleIPC
  VERSION = "1.1"
  LOCALHOST = "127.0.0.1"
  BROADCAST = "" # Accept connections from INADDR_ANY
  LENGTH_CODE = 'N'
  LENGTH_SIZE = [0].pack(LENGTH_CODE).size
  
  def SimpleIPC.version; VERSION; end
  
  # Wrapper class exposing the same API for +UNIXSocket+ and +UDPSocket+ classes.
  class Socket
    
    # Default initialization hash is:
    #   {
    #     :port => 5000,       # port, only used for UDPSockets
    #     :host => LOCALHOST,  # Host to talk with, only used for UDPSockets
    #     :kind => :unix,      # kind of socket, either :unix or :udp
    #     :force => true       # if true, force removing of stale socket files
    #   }
    # @param [Hash] args a hash of config values
    def initialize(args = {})
      @cfg = {
        :port => 5000,
        :host => LOCALHOST,
        :kind => :unix,
        :force => true    
      }
      @cfg.merge! args
      case @cfg[:kind]
      when :unix
        @socket_file = "/tmp/#{$0}.sok"
        @socket = nil
      when :udp
        @socket = UDPSocket.new
      else
        raise ArgumentError, "Either :unix or :udp allowed"
      end
      @open = false
    end
    
    # Opens the connection. Only has to be called once before sending messages.
    # Only used for client sockets.
    def connect
      return false if @open
      case @cfg[:kind]
      when :unix
        @socket = UNIXSocket.open(@socket_file)
      when :udp
        @socket.connect(@cfg[:host], @cfg[:port])
      end
      @open = true
    end
    
    # Sends a +String+ through the socket.
    # @param [String] string the message to be sent
    def print(string)
      @socket.print(string)
    end
  
    # Listens for incoming messages, i.e. becomes a server. If +@cfg[:force]+
    # is true, it also silently removes any existing stale socket file, otherwise
    # stops.
    # @raise [Errno::EADDRINUSE] when +@cfg[:force]+ is false and a socket file 
    #   already exists
    def listen
      case @cfg[:kind]
      when :unix
        @socket = UNIXServer.open(@socket_file).accept
      when :udp
        @socket.bind(BROADCAST, @cfg[:port])
      end
    rescue Errno::EADDRINUSE
      if @cfg[:force] then
        FileUtils::rm(@socket_file)
        retry
      else
        raise Errno::EADDRINUSE, $!
      end
    end
    
    # Receives a message of length +bytes+.
    # @param [Integer] bytes the number of characters to be read
    # @return [String]
    def recvfrom(bytes)
      @socket.recvfrom(bytes)
    end
  
    # Receives a message of length +bytes+ in non-blocking way.
    # @param [Integer] bytes the number of characters to be read
    # @return [String]
    def recv_nonblock(bytes)
      @socket.recv_nonblock(bytes)
    end
    
    # Closes the socket and removes the socket file if it exists.
    def close
      @socket.close
      @open = false
      FileUtils::rm(@socket_file) if @socket_file
    end
  
  end #Socket Class

  class IPC  
    attr_accessor :cfg
    
    # Default initialization hash is:
    #   {:port => 5000,      # Port to listen at
    #    :host => LOCALHOST, # Host to talk to
    #    :timeout => 0,      # Timeout for blocking connections
    #    :blocking => false} # use blocking read
    # @param [Hash] args a hash of config values
    def initialize(args = {})
      raise ArgumentError, "expecting an Hash" unless args.kind_of? Hash
      @cfg = {:port => 5000, :host => LOCALHOST, :timeout => 0}
      @cfg.merge! args
      @socket = Socket.new @cfg
    end
  
    # Sends a general object to the server. If an optional block is given, then it
    # is used to perform the object serialization. Otherwise, YAML#dump is used
    # for serialization.
    # @param [Object] something an object
    # @yield [Object] a block that serializes the received +Object+
    def send(something)
      if block_given? then
        payload = yield(something)
      else
        payload = YAML.dump(something)
      end
      length = [payload.size].pack(LENGTH_CODE)
      @socket.connect
      @socket.print length
      @socket.print payload
      return payload
    end
    
    # Puts the object in listening state (becomes a server).
    def listen
      @socket.listen
    end
    
    # Gets an object (only valid if it is a server). An optional block can be 
    # given for parsing the received +String+. If no block is given, then the
    # YAML#load deserialization is automatically used.
    # @return [Object] a parsed object
    # @yield [String] a block that deserializes the received +String+
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
    
    # Closes the socket.
    def close
      @socket.close
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
  
  end #IPC Class
end #SimpleIPC module

if $0 == __FILE__ then
  puts "Using SimpleIPC version #{SimpleIPC::version}"
  ary = [1,2,3,4]
  if ARGV[0] == "server" then
    from_client = SimpleIPC::IPC.new :port => 5000, :nonblock => true, :kind => :udp
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
    to_server = SimpleIPC::IPC.new :port => 5000, :kind => :udp
    to_server.send([1,2,3, "test"])
    to_server.send({:a => "test", :b => "prova"})
    to_server.send("stop")
  
    # to_server.send([1,2,3,4]) {|o| o * ","}
    # to_server.send(ary) {|o| o.pack("N#{ary.size}")}
    to_server.close
  end
end


