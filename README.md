This repo is an example meant to demonstrate an issue with EM-Websockets (or
EventMachine itself) when running in a thread under JRuby.

1. `rvm use ruby-2.2.1 && rvm gemset use em-example && bundle install`
1. `rackup &`
1. `./websockets.rb`
1. Direct your browser to `http://localhost:9292/?LR-verbose=true`
1. If you have Firebug installed, go to the console and turn on "Persist."  You
   will see debug messages from LiveReload indicating that it's connected and
   then that it is reloading the page when it receives the `reload` command from
   the WebSockets connection.  You can also see the page refreshing itself
   although it's quick since it's a very small page.  This is the correct
   behavior.

Repeat the above process but this time invoke `./websockets.rb threaded`.
Everything will continue working correctly.

Now switch to JRuby:

`rvm use jruby-9.0.5.0 && rvm gemset use em-example && bundle install`

* Repeat with `./websockets.rb`.  Again everything will work.
* Repeat with `./websockets.rb threaded`.  At this point, LiveReload will stop
  working.

I have attached two packet captures made with WireShark, `working.pcapng` and
`not_working.pcapng`.  The first was made under threaded mode with Ruby 2.2.1
and the second with threaded mode under JRuby.  You can see in the second
capture that the `reload` messages aren't even being sent.
