SimpleIPC
=========

Description
-----------

SimpleIPC is a library for doing simple inter-process communication in Ruby.

Install
-------

Available as a gem:

    gem install simple_ipc

Example
-------

Server example:

    from_client = SimpleIPC::IPC.new :port => 5000, :nonblock => true, :kind => :unix
    from_client.listen
    running = true
    while running != "stop" do
      running = from_client.get
      p running if running
      sleep 0.01
    end


Client example:

    to_server = SimpleIPC::IPC.new :kind => :unix
    to_server.send([1,2,3, "test"])
    to_server.send({:a => "test", :b => "prova"})
    to_server.send("stop")


